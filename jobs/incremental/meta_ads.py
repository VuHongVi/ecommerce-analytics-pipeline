import argparse
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

from ecommerce_analytics.clients.meta import (
    MetaAPIError,
    MetaClient,
)
from ecommerce_analytics.clients.sql_server import (
    connect_sql_server,
)
from ecommerce_analytics.extractors.meta_insights import (
    extract_and_load_range,
    iter_date_chunks,
)
from ecommerce_analytics.loaders.meta_raw import (
    load_account_snapshots,
)
from ecommerce_analytics.loaders.pancake_raw import (
    finish_run,
    start_run,
)
from ecommerce_analytics.settings import load_settings


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Incrementally synchronize recent Meta Ads "
            "insights into SQL Server RAW."
        )
    )

    parser.add_argument(
        "--lookback-days",
        type=int,
        default=8,
        help=(
            "Number of completed business days "
            "to synchronize."
        ),
    )
    parser.add_argument(
        "--chunk-days",
        type=int,
        default=8,
        help="Number of days per Insights request.",
    )
    parser.add_argument(
        "--account-limit",
        type=int,
        default=None,
        help="Optional account limit for controlled tests.",
    )

    return parser


def main() -> int:
    args = build_parser().parse_args()

    if args.lookback_days < 1:
        raise ValueError(
            "--lookback-days must be at least 1."
        )

    if args.chunk_days < 1:
        raise ValueError(
            "--chunk-days must be at least 1."
        )

    if (
        args.account_limit is not None
        and args.account_limit < 1
    ):
        raise ValueError(
            "--account-limit must be at least 1."
        )

    settings = load_settings()
    settings.require("meta_access_token")
    settings.require("meta_business_id")

    business_timezone = ZoneInfo(
        settings.business_timezone
    )
    business_today = datetime.now(
        business_timezone
    ).date()

    until = business_today - timedelta(days=1)
    since = until - timedelta(
        days=args.lookback_days - 1
    )

    window_start_utc = datetime.combine(
        since,
        time.min,
        tzinfo=business_timezone,
    ).astimezone(UTC)

    window_end_utc = datetime.combine(
        until + timedelta(days=1),
        time.min,
        tzinfo=business_timezone,
    ).astimezone(UTC)

    extracted_at_utc = datetime.now(UTC)
    connection = connect_sql_server(settings)

    run_id = start_run(
        connection,
        pipeline_name="meta_ads_incremental",
        source_name="meta_marketing_api",
        run_type="incremental",
        window_start_utc=window_start_utc,
        window_end_utc=window_end_utc,
    )

    account_count = 0
    active_account_count = 0
    snapshot_count = 0
    insight_count = 0
    loaded_count = 0
    processed_accounts = 0
    skipped_accounts = 0
    failed_chunks = 0
    scan_errors = 0

    try:
        with MetaClient(
            settings.meta_access_token,
            settings.meta_api_version,
        ) as client:
            accounts = client.get_ad_accounts(
                settings.meta_business_id
            )
            account_count = len(accounts)

            snapshot_count = load_account_snapshots(
                connection,
                run_id=run_id,
                extracted_at_utc=extracted_at_utc,
                accounts=accounts,
            )

            active_accounts, scan_errors = (
                client.scan_accounts_with_spend(
                    accounts,
                    since,
                    until,
                )
            )

            active_account_count = len(
                active_accounts
            )

            if args.account_limit is not None:
                active_accounts = active_accounts[
                    : args.account_limit
                ]

            total_accounts_to_process = len(
                active_accounts
            )

            for account_index, account in enumerate(
                active_accounts,
                start=1,
            ):
                print(
                    "Processing Meta account "
                    f"{account_index}/"
                    f"{total_accounts_to_process}"
                )

                account_failed = False

                for chunk_since, chunk_until in (
                    iter_date_chunks(
                        since,
                        until,
                        args.chunk_days,
                    )
                ):
                    try:
                        extracted, loaded = (
                            extract_and_load_range(
                                client=client,
                                connection=connection,
                                run_id=run_id,
                                extracted_at_utc=(
                                    extracted_at_utc
                                ),
                                account=account,
                                since=chunk_since,
                                until=chunk_until,
                            )
                        )
                    except MetaAPIError:
                        failed_chunks += 1
                        account_failed = True
                        continue

                    insight_count += extracted
                    loaded_count += loaded

                if account_failed:
                    skipped_accounts += 1
                else:
                    processed_accounts += 1

        if scan_errors or failed_chunks:
            status = "partial"
            error_message = (
                f"scan_errors={scan_errors}; "
                f"failed_chunks={failed_chunks}"
            )
        else:
            status = "succeeded"
            error_message = None

        finish_run(
            connection,
            run_id,
            status=status,
            error_message=error_message,
        )

    except Exception as error:
        finish_run(
            connection,
            run_id,
            status="failed",
            error_message=(
                f"{type(error).__name__}: "
                f"{str(error)[:1000]}"
            ),
        )
        raise

    finally:
        connection.close()

    print("Meta Ads incremental sync: OK")
    print("Window since:", since)
    print("Window until:", until)
    print("Accounts discovered:", account_count)
    print(
        "Accounts with spend:",
        active_account_count,
    )
    print(
        "Account snapshots loaded:",
        snapshot_count,
    )
    print(
        "Insight rows extracted:",
        insight_count,
    )
    print(
        "Insight versions loaded:",
        loaded_count,
    )
    print(
        "Accounts processed:",
        processed_accounts,
    )
    print(
        "Accounts skipped:",
        skipped_accounts,
    )
    print("Failed chunks:", failed_chunks)
    print("Account scan errors:", scan_errors)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())