import argparse
from datetime import UTC, date, datetime, time, timedelta

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


def parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("Date must use YYYY-MM-DD format.") from error


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=("Backfill Meta Ads daily ad-level insights into SQL Server RAW.")
    )

    parser.add_argument(
        "--since",
        required=True,
        type=parse_date,
        help="Inclusive start date in YYYY-MM-DD.",
    )
    parser.add_argument(
        "--until",
        required=True,
        type=parse_date,
        help="Inclusive end date in YYYY-MM-DD.",
    )
    parser.add_argument(
        "--chunk-days",
        type=int,
        default=7,
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

    if args.until < args.since:
        raise ValueError("--until must not be before --since.")

    if args.chunk_days < 1:
        raise ValueError("--chunk-days must be at least 1.")

    if args.account_limit is not None and args.account_limit < 1:
        raise ValueError("--account-limit must be at least 1.")

    settings = load_settings()
    settings.require("meta_access_token")
    settings.require("meta_business_id")

    window_start_utc = datetime.combine(
        args.since,
        time.min,
        tzinfo=UTC,
    )
    window_end_utc = datetime.combine(
        args.until + timedelta(days=1),
        time.min,
        tzinfo=UTC,
    )
    extracted_at_utc = datetime.now(UTC)

    connection = connect_sql_server(settings)

    run_id = start_run(
        connection,
        pipeline_name="meta_ads_backfill",
        source_name="meta_marketing_api",
        run_type="backfill",
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
            accounts = client.get_ad_accounts(settings.meta_business_id)
            account_count = len(accounts)

            snapshot_count = load_account_snapshots(
                connection,
                run_id=run_id,
                extracted_at_utc=extracted_at_utc,
                accounts=accounts,
            )

            active_accounts, scan_errors = client.scan_accounts_with_spend(
                accounts,
                args.since,
                args.until,
            )

            active_account_count = len(active_accounts)

            if args.account_limit is not None:
                active_accounts = active_accounts[: args.account_limit]

            total_accounts_to_process = len(active_accounts)

            for account_index, account in enumerate(
                active_accounts,
                start=1,
            ):
                print(f"Processing Meta account {account_index}/{total_accounts_to_process}")

                account_failed = False

                for chunk_since, chunk_until in iter_date_chunks(
                    args.since,
                    args.until,
                    args.chunk_days,
                ):
                    try:
                        extracted, loaded = extract_and_load_range(
                            client=client,
                            connection=connection,
                            run_id=run_id,
                            extracted_at_utc=(extracted_at_utc),
                            account=account,
                            since=chunk_since,
                            until=chunk_until,
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
            error_message = f"scan_errors={scan_errors}; failed_chunks={failed_chunks}"
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
            error_message=(f"{type(error).__name__}: {str(error)[:1000]}"),
        )
        raise

    finally:
        connection.close()

    print("Meta Ads backfill: OK")
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
