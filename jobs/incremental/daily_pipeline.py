"""Orchestrate daily extraction, SQL refreshes, and quality checks."""

import argparse
import subprocess
import sys
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pyodbc

from ecommerce_analytics.clients.sql_server import (
    connect_sql_server,
)
from ecommerce_analytics.loaders.pancake_raw import (
    finish_run,
    start_run,
)
from ecommerce_analytics.settings import load_settings


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
QUALITY_SCRIPT_PATH = (
    REPOSITORY_ROOT
    / "sql"
    / "04_quality"
    / "001_validate_daily_pipeline.sql"
)


@dataclass(frozen=True)
class ExtractStep:
    name: str
    pipeline_name: str
    script_path: Path
    arguments: tuple[str, ...] = ()


@dataclass(frozen=True)
class PipelineRun:
    run_id: str
    status: str
    error_message: str | None


PROCEDURES = (
    "stg.refresh_pancake_staging",
    "stg.refresh_meta_staging",
    "stg.refresh_product_cost_staging",
    "stg.refresh_order_item_cost_staging",
    "mart.refresh_dim_date",
    "mart.refresh_order_economics",
    "mart.refresh_dim_meta_ads",
    "mart.refresh_dim_products",
    "mart.refresh_ad_economics_daily",
    "mart.refresh_order_item_economics",
    "mart.refresh_product_ad_economics_daily",
    "mart.refresh_business_scope_assignments",
)


class PipelineStepError(RuntimeError):
    """Raised when one daily pipeline step does not succeed."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run the ecommerce analytics incremental pipeline "
            "from RAW extraction through MART refreshes."
        )
    )

    execution_mode = parser.add_mutually_exclusive_group()

    execution_mode.add_argument(
        "--sql-only",
        action="store_true",
        help=(
            "Skip Pancake and Meta API extraction and only "
            "refresh STAGING and MART."
        ),
    )
    execution_mode.add_argument(
        "--quality-only",
        action="store_true",
        help=(
            "Skip extraction and refresh procedures and only "
            "run the quality gate."
        ),
    )
    parser.add_argument(
        "--allow-partial-extracts",
        action="store_true",
        help=(
            "Continue when an extraction job records partial "
            "instead of succeeded."
        ),
    )
    parser.add_argument(
        "--meta-lookback-days",
        type=int,
        default=8,
        help="Completed business days to refresh from Meta.",
    )
    parser.add_argument(
        "--meta-chunk-days",
        type=int,
        default=8,
        help="Days per Meta Insights request.",
    )

    args = parser.parse_args()

    if args.meta_lookback_days < 1:
        parser.error(
            "--meta-lookback-days must be at least 1."
        )

    if args.meta_chunk_days < 1:
        parser.error(
            "--meta-chunk-days must be at least 1."
        )

    return args


def fetch_latest_run(
    connection: pyodbc.Connection,
    pipeline_name: str,
) -> PipelineRun | None:
    row = connection.cursor().execute(
        """
        SELECT TOP (1)
            run_id,
            [status],
            error_message
        FROM ctl.pipeline_runs
        WHERE pipeline_name = ?
        ORDER BY
            started_at_utc DESC,
            run_id DESC;
        """,
        pipeline_name,
    ).fetchone()

    if row is None:
        return None

    return PipelineRun(
        run_id=str(row[0]),
        status=str(row[1]),
        error_message=(
            str(row[2]) if row[2] is not None else None
        ),
    )


def run_extract_step(
    connection: pyodbc.Connection,
    step: ExtractStep,
    *,
    allow_partial: bool,
) -> None:
    previous_run = fetch_latest_run(
        connection,
        step.pipeline_name,
    )

    command = [
        sys.executable,
        str(step.script_path),
        *step.arguments,
    ]

    print("")
    print(f"START EXTRACT: {step.name}")

    completed = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        check=False,
    )

    current_run = fetch_latest_run(
        connection,
        step.pipeline_name,
    )

    if completed.returncode != 0:
        detail = (
            current_run.error_message
            if current_run is not None
            else None
        )
        raise PipelineStepError(
            f"{step.name} exited with code "
            f"{completed.returncode}. "
            f"{detail or 'No run error was recorded.'}"
        )

    if current_run is None:
        raise PipelineStepError(
            f"{step.name} did not create a pipeline run."
        )

    if (
        previous_run is not None
        and current_run.run_id == previous_run.run_id
    ):
        raise PipelineStepError(
            f"{step.name} did not create a new pipeline run."
        )

    if current_run.status == "partial" and allow_partial:
        print(
            f"WARNING: {step.name} completed with "
            "partial status."
        )
        return

    if current_run.status != "succeeded":
        raise PipelineStepError(
            f"{step.name} recorded status "
            f"{current_run.status!r}. "
            f"{current_run.error_message or ''}"
        )

    print(f"FINISH EXTRACT: {step.name}")


def format_value(value: Any) -> str:
    if value is None:
        return "NULL"

    return str(value)


def print_result_set(
    procedure_name: str,
    columns: list[str],
    rows: list[tuple[Any, ...]],
) -> None:
    if not rows:
        return

    print(f"RESULT: {procedure_name}")

    for row_index, row in enumerate(rows, start=1):
        values = ", ".join(
            f"{column}={format_value(value)}"
            for column, value in zip(
                columns,
                row,
                strict=True,
            )
        )
        print(f"  row {row_index}: {values}")


def execute_procedure(
    connection: pyodbc.Connection,
    procedure_name: str,
) -> None:
    print("")
    print(f"START PROCEDURE: {procedure_name}")

    cursor = connection.cursor()
    cursor.execute(f"EXEC {procedure_name};")

    while True:
        if cursor.description is not None:
            columns = [
                str(column[0])
                for column in cursor.description
            ]
            fetched_rows = cursor.fetchall()
            rows = [tuple(row) for row in fetched_rows]

            print_result_set(
                procedure_name,
                columns,
                rows,
            )

        if not cursor.nextset():
            break

    connection.commit()
    print(f"FINISH PROCEDURE: {procedure_name}")


def execute_quality_gate(
    connection: pyodbc.Connection,
) -> None:
    print("")
    print("START QUALITY GATE")

    if not QUALITY_SCRIPT_PATH.is_file():
        raise PipelineStepError(
            "Quality script was not found: "
            f"{QUALITY_SCRIPT_PATH}"
        )

    script = QUALITY_SCRIPT_PATH.read_text(
        encoding="utf-8"
    )
    cursor = connection.cursor()
    cursor.execute(script)
    checks: list[dict[str, Any]] = []

    while True:
        if cursor.description is not None:
            columns = [
                str(column[0])
                for column in cursor.description
            ]

            if {
                "check_name",
                "failure_count",
                "check_status",
            }.issubset(columns):
                for row in cursor.fetchall():
                    checks.append(
                        dict(
                            zip(
                                columns,
                                row,
                                strict=True,
                            )
                        )
                    )
            else:
                cursor.fetchall()

        if not cursor.nextset():
            break

    connection.commit()

    if not checks:
        raise PipelineStepError(
            "Quality gate returned no checks."
        )

    failures = []

    for check in checks:
        check_name = str(check["check_name"])
        failure_count = int(check["failure_count"])
        status = str(check["check_status"])

        print(
            f"QUALITY {status}: {check_name} "
            f"(failures={failure_count})"
        )

        if failure_count != 0:
            failures.append(check)

    if failures:
        failure_summary = ", ".join(
            f"{failure['check_name']}="
            f"{failure['failure_count']}"
            for failure in failures
        )
        raise PipelineStepError(
            "Quality gate failed: "
            f"{failure_summary}"
        )

    print(
        "FINISH QUALITY GATE: "
        f"{len(checks)} checks passed"
    )


def build_extract_steps(
    *,
    meta_lookback_days: int,
    meta_chunk_days: int,
) -> tuple[ExtractStep, ...]:
    incremental_directory = (
        REPOSITORY_ROOT / "jobs" / "incremental"
    )

    return (
        ExtractStep(
            name="Pancake orders",
            pipeline_name="pancake_orders_incremental",
            script_path=(
                incremental_directory / "pancake_orders.py"
            ),
        ),
        ExtractStep(
            name="Meta Ads",
            pipeline_name="meta_ads_incremental",
            script_path=(
                incremental_directory / "meta_ads.py"
            ),
            arguments=(
                "--lookback-days",
                str(meta_lookback_days),
                "--chunk-days",
                str(meta_chunk_days),
            ),
        ),
    )


def main() -> int:
    args = parse_args()
    settings = load_settings()
    pipeline_started_at = datetime.now(UTC)
    run_type = (
        "manual"
        if args.sql_only or args.quality_only
        else "incremental"
    )

    connection = connect_sql_server(settings)
    run_id = start_run(
        connection,
        pipeline_name="ecommerce_analytics_daily",
        source_name="multi_source",
        run_type=run_type,
        window_start_utc=pipeline_started_at,
        window_end_utc=pipeline_started_at,
    )

    try:
        if args.quality_only:
            print(
                "RAW extraction and SQL refresh skipped: "
                "--quality-only"
            )
        else:
            if args.sql_only:
                print("RAW extraction skipped: --sql-only")
            else:
                extract_steps = build_extract_steps(
                    meta_lookback_days=(
                        args.meta_lookback_days
                    ),
                    meta_chunk_days=args.meta_chunk_days,
                )

                for step in extract_steps:
                    run_extract_step(
                        connection,
                        step,
                        allow_partial=(
                            args.allow_partial_extracts
                        ),
                    )

            for procedure_name in PROCEDURES:
                execute_procedure(
                    connection,
                    procedure_name,
                )

        execute_quality_gate(connection)

        finish_run(
            connection,
            run_id,
            status="succeeded",
        )

    except Exception as error:
        connection.rollback()

        finish_run(
            connection,
            run_id,
            status="failed",
            error_message=(
                f"{type(error).__name__}: "
                f"{str(error)[:1900]}"
            ),
        )
        raise

    finally:
        connection.close()

    print("")
    print("DAILY PIPELINE: SUCCEEDED")
    print("Run ID:", run_id)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
