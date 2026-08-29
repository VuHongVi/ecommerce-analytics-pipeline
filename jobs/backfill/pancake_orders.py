import argparse
from collections.abc import Iterator
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from ecommerce_analytics.clients.pancake import (
    PancakeClient,
    PancakePermissionError,
)
from ecommerce_analytics.clients.sql_server import (
    connect_sql_server,
)
from ecommerce_analytics.loaders.pancake_raw import (
    finish_run,
    load_order_batch,
    start_run,
)
from ecommerce_analytics.settings import load_settings


def batched(
    orders: Iterator[dict[str, Any]],
    batch_size: int,
) -> Iterator[list[dict[str, Any]]]:
    batch = []

    for order in orders:
        batch.append(order)

        if len(batch) >= batch_size:
            yield batch
            batch = []

    if batch:
        yield batch


def month_windows(
    start_datetime: datetime,
    end_datetime: datetime,
) -> Iterator[tuple[datetime, datetime]]:
    current_start = start_datetime

    while current_start < end_datetime:
        if current_start.month == 12:
            next_month = current_start.replace(
                year=current_start.year + 1,
                month=1,
                day=1,
            )
        else:
            next_month = current_start.replace(
                month=current_start.month + 1,
                day=1,
            )

        current_end = min(next_month, end_datetime)
        yield current_start, current_end
        current_start = current_end


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--since",
        required=True,
        type=date.fromisoformat,
    )
    parser.add_argument(
        "--until",
        required=True,
        type=date.fromisoformat,
    )
    parser.add_argument(
        "--shop-limit",
        type=int,
        default=None,
    )

    args = parser.parse_args()

    if args.until < args.since:
        parser.error("--until must be on or after --since.")

    if args.shop_limit is not None and args.shop_limit < 1:
        parser.error("--shop-limit must be at least 1.")

    return args


def main() -> None:
    args = parse_args()
    settings = load_settings()

    settings.require(
        "pancake_api_key",
        "sql_server",
        "sql_database",
        "sql_driver",
    )

    window_start = datetime.combine(
        args.since,
        time.min,
        tzinfo=UTC,
    )
    window_end = datetime.combine(
        args.until + timedelta(days=1),
        time.min,
        tzinfo=UTC,
    )

    connection = connect_sql_server(settings)

    run_id = start_run(
        connection,
        pipeline_name="pancake_orders_backfill",
        source_name="pancake",
        run_type="backfill",
        window_start_utc=window_start,
        window_end_utc=window_end,
    )

    extracted_orders = 0
    loaded_versions = 0
    skipped_shops = 0

    try:
        with PancakeClient(settings.pancake_api_key) as client:
            shops = client.get_shops()

            if args.shop_limit is not None:
                shops = shops[: args.shop_limit]

            for shop in shops:
                shop_id = shop.get("id") or shop.get("shop_id")

                if shop_id is None:
                    skipped_shops += 1
                    continue

                try:
                    for period_start, period_end in month_windows(
                        window_start,
                        window_end,
                    ):
                        order_iterator = client.iter_orders(
                            shop_id=str(shop_id),
                            start_datetime=period_start,
                            end_datetime=period_end,
                            update_status="inserted_at",
                        )

                        for order_batch in batched(
                            order_iterator,
                            batch_size=100,
                        ):
                            extracted_orders += len(order_batch)

                            loaded_versions += load_order_batch(
                                connection,
                                run_id=run_id,
                                shop_id=str(shop_id),
                                orders=order_batch,
                            )

                except PancakePermissionError:
                    skipped_shops += 1

        run_status = "partial" if skipped_shops > 0 else "succeeded"

        finish_run(
            connection,
            run_id,
            status=run_status,
        )

    except Exception as error:
        connection.rollback()

        finish_run(
            connection,
            run_id,
            status="failed",
            error_message=str(error)[:2000],
        )
        raise

    finally:
        connection.close()

    print("Pancake backfill: OK")
    print(f"Orders extracted: {extracted_orders}")
    print(f"Versions loaded: {loaded_versions}")
    print(f"Shops skipped: {skipped_shops}")


if __name__ == "__main__":
    main()
