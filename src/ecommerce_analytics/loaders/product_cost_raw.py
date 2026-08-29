import hashlib
import json
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any

from ecommerce_analytics.extractors.product_cost import (
    ProductCostWorkbook,
)


@dataclass(frozen=True)
class ProductCostLoadResult:
    batch_id: int
    already_loaded: bool
    master_rows_loaded: int
    history_rows_loaded: int


def _canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )


def _row_hash(row_json: str) -> bytes:
    return hashlib.sha256(row_json.encode("utf-8")).digest()


def _to_text(value: Any) -> str | None:
    if value in (None, ""):
        return None

    text = str(value).strip()
    return text or None


def _to_decimal(value: Any) -> Decimal | None:
    if value in (None, "") or isinstance(value, bool):
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

    if not isinstance(value, str):
        return None

    text = value.strip()

    for date_format in (
        "%Y-%m-%d",
        "%d/%m/%Y",
        "%d-%m-%Y",
    ):
        try:
            return datetime.strptime(
                text[:10],
                date_format,
            ).date()
        except ValueError:
            continue

    return None


def load_product_cost_workbook(
    connection: Any,
    *,
    workbook: ProductCostWorkbook,
) -> ProductCostLoadResult:
    cursor = connection.cursor()

    try:
        existing_batch = cursor.execute(
            """
            SELECT
                product_cost_import_batch_id,
                master_row_count,
                history_row_count
            FROM raw.product_cost_import_batches
            WHERE source_file_sha256 = ?;
            """,
            workbook.source_file_sha256,
        ).fetchone()

        if existing_batch is not None:
            return ProductCostLoadResult(
                batch_id=int(existing_batch[0]),
                already_loaded=True,
                master_rows_loaded=int(existing_batch[1]),
                history_rows_loaded=int(existing_batch[2]),
            )

        inserted_batch = cursor.execute(
            """
            INSERT INTO raw.product_cost_import_batches (
                source_file_name,
                source_file_sha256,
                source_file_size_bytes,
                source_file_modified_at_utc,
                master_sheet_name,
                history_sheet_name,
                master_row_count,
                history_row_count
            )
            OUTPUT
                INSERTED.product_cost_import_batch_id
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            workbook.source_file_name,
            workbook.source_file_sha256,
            workbook.source_file_size_bytes,
            workbook.source_file_modified_at_utc,
            workbook.master_sheet_name,
            workbook.history_sheet_name,
            len(workbook.master_rows),
            len(workbook.history_rows),
        ).fetchone()

        batch_id = int(inserted_batch[0])

        master_records: list[tuple[Any, ...]] = []

        for row in workbook.master_rows:
            source_row_number = int(row["source_row_number"])
            product_name = _to_text(row["product_name"])
            unit_cost = _to_decimal(row["unit_cost"])

            source_row_json = _canonical_json(
                {
                    "source_row_number": source_row_number,
                    "product_name": product_name,
                    "unit_cost": unit_cost,
                }
            )

            master_records.append(
                (
                    batch_id,
                    workbook.master_sheet_name,
                    source_row_number,
                    product_name,
                    unit_cost,
                    source_row_json,
                    _row_hash(source_row_json),
                )
            )

        if master_records:
            cursor.executemany(
                """
                INSERT INTO raw.product_cost_master_rows (
                    product_cost_import_batch_id,
                    source_sheet_name,
                    source_row_number,
                    product_name,
                    unit_cost,
                    source_row_json,
                    source_row_hash
                )
                VALUES (?, ?, ?, ?, ?, ?, ?);
                """,
                master_records,
            )

        history_records: list[tuple[Any, ...]] = []

        for row in workbook.history_rows:
            source_row_number = int(row["source_row_number"])
            product_name = _to_text(row["product_name"])
            approved_quantity = _to_decimal(row["approved_quantity"])
            import_date = _to_date(row["import_date"])
            warehouse_arrival_date = _to_date(row["warehouse_arrival_date"])
            actual_unit_cost = _to_decimal(row["actual_unit_cost"])

            source_row_json = _canonical_json(
                {
                    "source_row_number": source_row_number,
                    "product_name": product_name,
                    "approved_quantity": approved_quantity,
                    "import_date": import_date,
                    "warehouse_arrival_date": warehouse_arrival_date,
                    "actual_unit_cost": actual_unit_cost,
                }
            )

            history_records.append(
                (
                    batch_id,
                    workbook.history_sheet_name,
                    source_row_number,
                    product_name,
                    approved_quantity,
                    import_date,
                    warehouse_arrival_date,
                    actual_unit_cost,
                    source_row_json,
                    _row_hash(source_row_json),
                )
            )

        if history_records:
            cursor.executemany(
                """
                INSERT INTO raw.product_cost_history_rows (
                    product_cost_import_batch_id,
                    source_sheet_name,
                    source_row_number,
                    product_name,
                    approved_quantity,
                    import_date,
                    warehouse_arrival_date,
                    actual_unit_cost,
                    source_row_json,
                    source_row_hash
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                history_records,
            )

        connection.commit()

        return ProductCostLoadResult(
            batch_id=batch_id,
            already_loaded=False,
            master_rows_loaded=len(master_records),
            history_rows_loaded=len(history_records),
        )

    except Exception:
        connection.rollback()
        raise

    finally:
        cursor.close()
