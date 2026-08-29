from collections.abc import Iterator
from datetime import date, datetime, timedelta
from typing import Any
from uuid import UUID

from ecommerce_analytics.clients.meta import (
    MetaClient,
    MetaRetryableError,
)
from ecommerce_analytics.loaders.meta_raw import (
    load_insight_batch,
)


def iter_date_chunks(
    since: date,
    until: date,
    chunk_days: int,
) -> Iterator[tuple[date, date]]:
    chunk_start = since

    while chunk_start <= until:
        chunk_end = min(
            chunk_start + timedelta(days=chunk_days - 1),
            until,
        )

        yield chunk_start, chunk_end
        chunk_start = chunk_end + timedelta(days=1)


def extract_and_load_range(
    *,
    client: MetaClient,
    connection: Any,
    run_id: UUID,
    extracted_at_utc: datetime,
    account: dict[str, Any],
    since: date,
    until: date,
) -> tuple[int, int]:
    account_object_id = str(account["account_object_id"])

    try:
        insights = list(
            client.iter_ad_insights(
                account_object_id,
                since,
                until,
            )
        )
    except MetaRetryableError:
        if since >= until:
            raise

        range_days = (until - since).days
        midpoint = since + timedelta(days=range_days // 2)

        left_extracted, left_loaded = extract_and_load_range(
            client=client,
            connection=connection,
            run_id=run_id,
            extracted_at_utc=extracted_at_utc,
            account=account,
            since=since,
            until=midpoint,
        )

        right_extracted, right_loaded = extract_and_load_range(
            client=client,
            connection=connection,
            run_id=run_id,
            extracted_at_utc=extracted_at_utc,
            account=account,
            since=midpoint + timedelta(days=1),
            until=until,
        )

        return (
            left_extracted + right_extracted,
            left_loaded + right_loaded,
        )

    loaded_count = load_insight_batch(
        connection,
        run_id=run_id,
        extracted_at_utc=extracted_at_utc,
        account=account,
        insights=insights,
    )

    return len(insights), loaded_count
