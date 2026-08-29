from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

import pyodbc

from ecommerce_analytics.transformers.pancake_order import (
    serialize_and_hash_order,
)


def _parse_datetime(value: Any) -> datetime | None:
    if value in {None, ""}:
        return None

    if isinstance(value, datetime):
        parsed_value = value
    else:
        parsed_value = datetime.fromisoformat(str(value).replace("Z", "+00:00"))

    if parsed_value.tzinfo is not None:
        parsed_value = parsed_value.astimezone(UTC)
        parsed_value = parsed_value.replace(tzinfo=None)

    return parsed_value


def start_run(
    connection: pyodbc.Connection,
    *,
    pipeline_name: str,
    source_name: str,
    run_type: str,
    window_start_utc: datetime,
    window_end_utc: datetime,
) -> UUID:
    run_id = uuid4()

    connection.cursor().execute(
        """
        INSERT INTO ctl.pipeline_runs (
            run_id,
            pipeline_name,
            source_name,
            run_type,
            window_start_utc,
            window_end_utc,
            started_at_utc,
            [status]
        )
        VALUES (?, ?, ?, ?, ?, ?, SYSUTCDATETIME(), 'running');
        """,
        str(run_id),
        pipeline_name,
        source_name,
        run_type,
        _parse_datetime(window_start_utc),
        _parse_datetime(window_end_utc),
    )

    connection.commit()
    return run_id


def load_order_batch(
    connection: pyodbc.Connection,
    *,
    run_id: UUID,
    shop_id: str,
    orders: list[dict[str, Any]],
) -> int:
    if not orders:
        return 0

    extracted_at_utc = datetime.now(UTC).replace(tzinfo=None)
    records = []

    for order in orders:
        order_id = order.get("id")

        if order_id in {None, ""}:
            raise ValueError("Pancake order is missing id.")

        inserted_at = _parse_datetime(order.get("inserted_at"))
        updated_at = _parse_datetime(order.get("updated_at"))

        if updated_at is None:
            updated_at = inserted_at

        if updated_at is None:
            raise ValueError(f"Pancake order {order_id} has no timestamp.")

        payload_json, payload_hash = serialize_and_hash_order(order)

        system_id = order.get("system_id")

        records.append(
            (
                str(run_id),
                extracted_at_utc,
                str(shop_id),
                str(order_id),
                str(system_id) if system_id is not None else None,
                inserted_at,
                updated_at,
                payload_hash,
                "v1",
                payload_json,
            )
        )

    cursor = connection.cursor()

    cursor.execute(
        """
        DROP TABLE IF EXISTS #pancake_order_batch;

        CREATE TABLE #pancake_order_batch (
            extract_run_id UNIQUEIDENTIFIER NOT NULL,
            extracted_at_utc DATETIME2(3) NOT NULL,
            shop_id NVARCHAR(100) NOT NULL,
            order_id NVARCHAR(100) NOT NULL,
            system_id NVARCHAR(100) NULL,
            source_inserted_at DATETIME2(3) NULL,
            source_updated_at DATETIME2(3) NOT NULL,
            payload_hash BINARY(32) NOT NULL,
            sanitization_version VARCHAR(20) NOT NULL,
            payload_json NVARCHAR(MAX) NOT NULL
        );
        """
    )

    cursor.executemany(
        """
        INSERT INTO #pancake_order_batch (
            extract_run_id,
            extracted_at_utc,
            shop_id,
            order_id,
            system_id,
            source_inserted_at,
            source_updated_at,
            payload_hash,
            sanitization_version,
            payload_json
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """,
        records,
    )

    cursor.execute(
        """
        WITH deduplicated_batch AS (
            SELECT
                *,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        shop_id,
                        order_id,
                        source_updated_at,
                        payload_hash
                    ORDER BY order_id
                ) AS row_number
            FROM #pancake_order_batch
        )
        INSERT INTO raw.pancake_order_versions (
            extract_run_id,
            extracted_at_utc,
            shop_id,
            order_id,
            system_id,
            source_inserted_at,
            source_updated_at,
            payload_hash,
            sanitization_version,
            payload_json
        )
        SELECT
            source.extract_run_id,
            source.extracted_at_utc,
            source.shop_id,
            source.order_id,
            source.system_id,
            source.source_inserted_at,
            source.source_updated_at,
            source.payload_hash,
            source.sanitization_version,
            source.payload_json
        FROM deduplicated_batch AS source
        WHERE source.row_number = 1
          AND NOT EXISTS (
              SELECT 1
              FROM raw.pancake_order_versions AS target
              WHERE target.shop_id = source.shop_id
                AND target.order_id = source.order_id
                AND target.source_updated_at =
                    source.source_updated_at
                AND target.payload_hash = source.payload_hash
          );
        """
    )

    rows_loaded = max(cursor.rowcount, 0)

    cursor.execute(
        """
        UPDATE ctl.pipeline_runs
        SET
            rows_extracted = rows_extracted + ?,
            rows_loaded = rows_loaded + ?
        WHERE run_id = ?;
        """,
        len(orders),
        rows_loaded,
        str(run_id),
    )

    connection.commit()
    return rows_loaded


def finish_run(
    connection: pyodbc.Connection,
    run_id: UUID,
    *,
    status: str = "succeeded",
    error_message: str | None = None,
) -> None:
    connection.cursor().execute(
        """
        UPDATE ctl.pipeline_runs
        SET
            completed_at_utc = SYSUTCDATETIME(),
            [status] = ?,
            error_message = ?
        WHERE run_id = ?;
        """,
        status,
        error_message,
        str(run_id),
    )

    connection.commit()
