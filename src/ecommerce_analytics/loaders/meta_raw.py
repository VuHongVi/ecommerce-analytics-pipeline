import hashlib
import json
from datetime import UTC, date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any
from uuid import UUID


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )


def _payload_hash(payload_json: str) -> bytes:
    return hashlib.sha256(
        payload_json.encode("utf-8")
    ).digest()


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value

    return value.astimezone(UTC).replace(tzinfo=None)


def _to_text(value: Any) -> str | None:
    if value is None:
        return None

    text = str(value).strip()
    return text or None


def _to_int(value: Any) -> int | None:
    if value in (None, ""):
        return None

    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None

    if not number.is_finite():
        return None

    return int(number)


def _to_decimal(value: Any) -> Decimal | None:
    if value in (None, ""):
        return None

    try:
        number = Decimal(str(value))
    except (InvalidOperation, TypeError, ValueError):
        return None

    if not number.is_finite():
        return None

    return number


def _to_date(value: Any) -> date | None:
    if isinstance(value, datetime):
        return value.date()

    if isinstance(value, date):
        return value

    if isinstance(value, str):
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None

    return None


def _json_or_none(value: Any) -> str | None:
    if value is None:
        return None

    return _canonical_json(value)


def load_account_snapshots(
    connection: Any,
    *,
    run_id: UUID,
    extracted_at_utc: datetime,
    accounts: list[dict[str, Any]],
) -> int:
    if not accounts:
        return 0

    extracted_at = _utc_naive(extracted_at_utc)
    rows: list[tuple[Any, ...]] = []

    for account in accounts:
        account_object_id = _to_text(
            account.get("account_object_id")
        )

        if not account_object_id:
            continue

        discovery_sources = sorted(
            str(source)
            for source in account.get(
                "discovery_sources",
                [],
            )
        )

        snapshot = {
            "account_object_id": account_object_id,
            "account_id": _to_text(
                account.get("account_id")
            ),
            "account_name": _to_text(
                account.get("account_name")
            ),
            "account_status": _to_int(
                account.get("account_status")
            ),
            "currency": _to_text(
                account.get("currency")
            ),
            "timezone_name": _to_text(
                account.get("timezone_name")
            ),
            "discovery_sources": discovery_sources,
        }

        snapshot_json = _canonical_json(snapshot)
        discovery_sources_json = _canonical_json(
            discovery_sources
        )

        rows.append(
            (
                str(run_id),
                extracted_at,
                snapshot["account_object_id"],
                snapshot["account_id"],
                snapshot["account_name"],
                snapshot["account_status"],
                snapshot["currency"],
                snapshot["timezone_name"],
                discovery_sources_json,
                _payload_hash(snapshot_json),
            )
        )

    if not rows:
        return 0

    cursor = connection.cursor()

    cursor.execute(
        """
        IF OBJECT_ID(
            'tempdb..#meta_account_snapshots'
        ) IS NOT NULL
            DROP TABLE #meta_account_snapshots;

        CREATE TABLE #meta_account_snapshots (
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,
            account_object_id NVARCHAR(100) NOT NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,
            account_status INT NULL,
            currency VARCHAR(10) NULL,
            timezone_name NVARCHAR(100) NULL,
            discovery_sources_json NVARCHAR(MAX) NOT NULL,
            snapshot_hash BINARY(32) NOT NULL
        );
        """
    )

    cursor.executemany(
        """
        INSERT INTO #meta_account_snapshots (
            extract_run_id,
            extracted_at_utc,
            account_object_id,
            account_id,
            account_name,
            account_status,
            currency,
            timezone_name,
            discovery_sources_json,
            snapshot_hash
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """,
        rows,
    )

    inserted_count = cursor.execute(
        """
        SET NOCOUNT ON;

        ;WITH deduplicated AS (
            SELECT
                source.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        source.account_object_id,
                        source.snapshot_hash
                    ORDER BY source.account_object_id
                ) AS row_number
            FROM #meta_account_snapshots AS source
        )
        INSERT INTO raw.meta_ad_account_snapshots (
            extract_run_id,
            extracted_at_utc,
            account_object_id,
            account_id,
            account_name,
            account_status,
            currency,
            timezone_name,
            discovery_sources_json,
            snapshot_hash
        )
        SELECT
            source.extract_run_id,
            source.extracted_at_utc,
            source.account_object_id,
            source.account_id,
            source.account_name,
            source.account_status,
            source.currency,
            source.timezone_name,
            source.discovery_sources_json,
            source.snapshot_hash
        FROM deduplicated AS source
        WHERE source.row_number = 1
          AND NOT EXISTS (
              SELECT 1
              FROM raw.meta_ad_account_snapshots AS target
              WHERE target.account_object_id =
                    source.account_object_id
                AND target.snapshot_hash =
                    source.snapshot_hash
          );

        SELECT CAST(@@ROWCOUNT AS INT);
        """
    ).fetchone()[0]

    connection.commit()
    cursor.close()

    return int(inserted_count)


def load_insight_batch(
    connection: Any,
    *,
    run_id: UUID,
    extracted_at_utc: datetime,
    account: dict[str, Any],
    insights: list[dict[str, Any]],
) -> int:
    if not insights:
        return 0

    account_object_id = _to_text(
        account.get("account_object_id")
    )

    if not account_object_id:
        raise ValueError(
            "Meta account object ID is required."
        )

    extracted_at = _utc_naive(extracted_at_utc)
    rows: list[tuple[Any, ...]] = []

    for insight in insights:
        date_start = _to_date(
            insight.get("date_start")
        )
        date_stop = _to_date(
            insight.get("date_stop")
        )
        ad_id = _to_text(insight.get("ad_id"))

        if not date_start or not date_stop or not ad_id:
            continue

        payload_json = _canonical_json(insight)

        rows.append(
            (
                str(run_id),
                extracted_at,
                date_start,
                date_stop,
                account_object_id,
                _to_text(
                    insight.get("account_id")
                    or account.get("account_id")
                ),
                _to_text(
                    insight.get("account_name")
                    or account.get("account_name")
                ),
                _to_text(insight.get("campaign_id")),
                _to_text(insight.get("campaign_name")),
                _to_text(insight.get("adset_id")),
                _to_text(insight.get("adset_name")),
                ad_id,
                _to_text(insight.get("ad_name")),
                _to_text(insight.get("objective")),
                _to_text(
                    insight.get("optimization_goal")
                ),
                _to_int(insight.get("impressions")),
                _to_int(insight.get("reach")),
                _to_decimal(insight.get("frequency")),
                _to_int(insight.get("clicks")),
                _to_int(
                    insight.get("inline_link_clicks")
                ),
                _to_decimal(insight.get("spend")),
                _to_decimal(insight.get("cpm")),
                _to_decimal(insight.get("cpc")),
                _to_decimal(insight.get("ctr")),
                _json_or_none(insight.get("actions")),
                _json_or_none(
                    insight.get("action_values")
                ),
                _json_or_none(
                    insight.get(
                        "cost_per_action_type"
                    )
                ),
                _payload_hash(payload_json),
                payload_json,
            )
        )

    if not rows:
        return 0

    cursor = connection.cursor()

    cursor.execute(
        """
        IF OBJECT_ID(
            'tempdb..#meta_ad_insights'
        ) IS NOT NULL
            DROP TABLE #meta_ad_insights;

        CREATE TABLE #meta_ad_insights (
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,
            date_start DATE NOT NULL,
            date_stop DATE NOT NULL,
            account_object_id NVARCHAR(100) NOT NULL,
            account_id NVARCHAR(100) NULL,
            account_name NVARCHAR(500) NULL,
            campaign_id NVARCHAR(100) NULL,
            campaign_name NVARCHAR(500) NULL,
            adset_id NVARCHAR(100) NULL,
            adset_name NVARCHAR(500) NULL,
            ad_id NVARCHAR(100) NOT NULL,
            ad_name NVARCHAR(500) NULL,
            objective NVARCHAR(100) NULL,
            optimization_goal NVARCHAR(100) NULL,
            impressions BIGINT NULL,
            reach BIGINT NULL,
            frequency DECIMAL(19, 6) NULL,
            clicks BIGINT NULL,
            inline_link_clicks BIGINT NULL,
            spend DECIMAL(19, 6) NULL,
            cpm DECIMAL(19, 6) NULL,
            cpc DECIMAL(19, 6) NULL,
            ctr DECIMAL(19, 6) NULL,
            actions_json NVARCHAR(MAX) NULL,
            action_values_json NVARCHAR(MAX) NULL,
            cost_per_action_type_json NVARCHAR(MAX) NULL,
            payload_hash BINARY(32) NOT NULL,
            payload_json NVARCHAR(MAX) NOT NULL
        );
        """
    )

    placeholders = ", ".join(
        "?" for _ in range(29)
    )

    cursor.executemany(
        f"""
        INSERT INTO #meta_ad_insights (
            extract_run_id,
            extracted_at_utc,
            date_start,
            date_stop,
            account_object_id,
            account_id,
            account_name,
            campaign_id,
            campaign_name,
            adset_id,
            adset_name,
            ad_id,
            ad_name,
            objective,
            optimization_goal,
            impressions,
            reach,
            frequency,
            clicks,
            inline_link_clicks,
            spend,
            cpm,
            cpc,
            ctr,
            actions_json,
            action_values_json,
            cost_per_action_type_json,
            payload_hash,
            payload_json
        )
        VALUES ({placeholders});
        """,
        rows,
    )

    inserted_count = cursor.execute(
        """
        SET NOCOUNT ON;

        ;WITH deduplicated AS (
            SELECT
                source.*,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        source.account_object_id,
                        source.date_start,
                        source.ad_id,
                        source.payload_hash
                    ORDER BY source.date_stop
                ) AS row_number
            FROM #meta_ad_insights AS source
        )
        INSERT INTO raw.meta_ad_insight_versions (
            extract_run_id,
            extracted_at_utc,
            date_start,
            date_stop,
            account_object_id,
            account_id,
            account_name,
            campaign_id,
            campaign_name,
            adset_id,
            adset_name,
            ad_id,
            ad_name,
            objective,
            optimization_goal,
            impressions,
            reach,
            frequency,
            clicks,
            inline_link_clicks,
            spend,
            cpm,
            cpc,
            ctr,
            actions_json,
            action_values_json,
            cost_per_action_type_json,
            payload_hash,
            payload_json
        )
        SELECT
            source.extract_run_id,
            source.extracted_at_utc,
            source.date_start,
            source.date_stop,
            source.account_object_id,
            source.account_id,
            source.account_name,
            source.campaign_id,
            source.campaign_name,
            source.adset_id,
            source.adset_name,
            source.ad_id,
            source.ad_name,
            source.objective,
            source.optimization_goal,
            source.impressions,
            source.reach,
            source.frequency,
            source.clicks,
            source.inline_link_clicks,
            source.spend,
            source.cpm,
            source.cpc,
            source.ctr,
            source.actions_json,
            source.action_values_json,
            source.cost_per_action_type_json,
            source.payload_hash,
            source.payload_json
        FROM deduplicated AS source
        WHERE source.row_number = 1
          AND NOT EXISTS (
              SELECT 1
              FROM raw.meta_ad_insight_versions AS target
              WHERE target.account_object_id =
                    source.account_object_id
                AND target.date_start =
                    source.date_start
                AND target.ad_id =
                    source.ad_id
                AND target.payload_hash =
                    source.payload_hash
          );

        SELECT CAST(@@ROWCOUNT AS INT);
        """
    ).fetchone()[0]

    connection.commit()
    cursor.close()

    return int(inserted_count)