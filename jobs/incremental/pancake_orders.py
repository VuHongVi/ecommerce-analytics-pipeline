import argparse
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

import pyodbc

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

INITIAL_LOOKBACK = timedelta(days=7)
CHECKPOINT_OVERLAP = timedelta(hours=48)
BATCH_SIZE = 100


def batched(
    orders: Iterator[dict[str, Any]],
) -> Iterator[list[dict[str, Any]]]:
    batch = []

    for order in orders:
        batch.append(order)

        if len(batch) >= BATCH_SIZE:
            yield batch
            batch = []

    if batch:
        yield batch


def get_checkpoint(
    connection: pyodbc.Connection,
    shop_id: str,
) -> datetime | None:
    row = (
        connection.cursor()
        .execute(
            """
        SELECT last_source_updated_at
        FROM ctl.sync_checkpoints
        WHERE source_name = 'pancake'
          AND entity_name = 'orders'
          AND partition_key = ?;
        """,
            shop_id,
        )
        .fetchone()
    )

    if row is None or row[0] is None:
        return None

    checkpoint = row[0]

    if checkpoint.tzinfo is None:
        return checkpoint.replace(tzinfo=UTC)

    return checkpoint.astimezone(UTC)


def save_checkpoint(
    connection: pyodbc.Connection,
    *,
    shop_id: str,
    checkpoint: datetime,
    run_id: UUID,
) -> None:
    checkpoint_utc = checkpoint.astimezone(UTC).replace(tzinfo=None)
    cursor = connection.cursor()

    cursor.execute(
        """
        UPDATE ctl.sync_checkpoints
        SET
            last_source_updated_at = ?,
            last_successful_run_id = ?,
            updated_at_utc = SYSUTCDATETIME()
        WHERE source_name = 'pancake'
          AND entity_name = 'orders'
          AND partition_key = ?;
        """,
        checkpoint_utc,
        str(run_id),
        shop_id,
    )

    if cursor.rowcount == 0:
        cursor.execute(
            """
            INSERT INTO ctl.sync_checkpoints (
                source_name,
                entity_name,
                partition_key,
                last_source_updated_at,
                last_successful_run_id
            )
            VALUES (
                'pancake',
                'orders',
                ?,
                ?,
                ?
            );
            """,
            shop_id,
            checkpoint_utc,
            str(run_id),
        )

    connection.commit()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--shop-limit",
        type=int,
        default=None,
    )

    args = parser.parse_args()

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

    window_end = datetime.now(UTC)
    fallback_start = window_end - INITIAL_LOOKBACK

    connection = connect_sql_server(settings)

    run_id = start_run(
        connection,
        pipeline_name="pancake_orders_incremental",
        source_name="pancake",
        run_type="incremental",
        window_start_utc=fallback_start,
        window_end_utc=window_end,
    )

    extracted_orders = 0
    loaded_versions = 0
    processed_shops = 0
    skipped_shops = 0

    try:
        with PancakeClient(settings.pancake_api_key) as client:
            shops = client.get_shops()

            if args.shop_limit is not None:
                shops = shops[: args.shop_limit]

            for shop in shops:
                shop_id_value = shop.get("id") or shop.get("shop_id")

                if shop_id_value is None:
                    skipped_shops += 1
                    continue

                shop_id = str(shop_id_value)
                checkpoint = get_checkpoint(
                    connection,
                    shop_id,
                )

                if checkpoint is None:
                    shop_window_start = fallback_start
                else:
                    shop_window_start = checkpoint - CHECKPOINT_OVERLAP

                try:
                    order_iterator = client.iter_orders(
                        shop_id=shop_id,
                        start_datetime=shop_window_start,
                        end_datetime=window_end,
                        update_status="updated_at",
                    )

                    for order_batch in batched(order_iterator):
                        extracted_orders += len(order_batch)

                        loaded_versions += load_order_batch(
                            connection,
                            run_id=run_id,
                            shop_id=shop_id,
                            orders=order_batch,
                        )

                    save_checkpoint(
                        connection,
                        shop_id=shop_id,
                        checkpoint=window_end,
                        run_id=run_id,
                    )
                    processed_shops += 1

                except PancakePermissionError:
                    skipped_shops += 1

        finish_run(
            connection,
            run_id,
            status=("partial" if skipped_shops > 0 else "succeeded"),
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

    print("Pancake incremental sync: OK")
    print(f"Orders extracted: {extracted_orders}")
    print(f"Versions loaded: {loaded_versions}")
    print(f"Shops processed: {processed_shops}")
    print(f"Shops skipped: {skipped_shops}")


if __name__ == "__main__":
    main()
