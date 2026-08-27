import json
from collections.abc import Iterator
from datetime import date
from decimal import Decimal, InvalidOperation
from typing import Any
from urllib.parse import urlencode

import requests
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

RETRYABLE_HTTP_STATUS_CODES = {
    429,
    500,
    502,
    503,
    504,
}

RETRYABLE_META_ERROR_CODES = {
    1,
    2,
    4,
    17,
    32,
    613,
}

ACCOUNT_FIELDS = (
    "id",
    "account_id",
    "name",
    "account_status",
    "currency",
    "timezone_name",
)

ACCOUNT_SOURCES = {
    "system_user_accessible": "/me/adaccounts",
    "business_owned": "/{business_id}/owned_ad_accounts",
    "business_client": "/{business_id}/client_ad_accounts",
}

INSIGHT_FIELDS = (
    "date_start",
    "date_stop",
    "account_id",
    "account_name",
    "campaign_id",
    "campaign_name",
    "adset_id",
    "adset_name",
    "ad_id",
    "ad_name",
    "objective",
    "optimization_goal",
    "impressions",
    "reach",
    "frequency",
    "clicks",
    "inline_link_clicks",
    "spend",
    "cpm",
    "cpc",
    "ctr",
    "actions",
    "action_values",
    "cost_per_action_type",
)


class MetaAPIError(RuntimeError):
    """Raised when a Meta API request fails."""


class MetaRetryableError(MetaAPIError):
    """Raised for temporary Meta API failures."""


class MetaClient:
    def __init__(
        self,
        access_token: str,
        api_version: str,
        *,
        timeout: int = 90,
    ) -> None:
        if not access_token.strip():
            raise ValueError("Meta access token is required.")

        if not api_version.strip():
            raise ValueError("Meta API version is required.")

        self._access_token = access_token
        self._base_url = (
            f"https://graph.facebook.com/"
            f"{api_version.strip('/')}"
        )
        self._timeout = timeout
        self._session = requests.Session()

        self._session.headers.update(
            {
                "Authorization": f"Bearer {access_token}",
            }
        )

    def close(self) -> None:
        self._session.headers.clear()
        self._session.close()
        self._access_token = ""

    def __enter__(self) -> "MetaClient":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @retry(
        retry=retry_if_exception_type(
            (
                requests.Timeout,
                requests.ConnectionError,
                MetaRetryableError,
            )
        ),
        wait=wait_exponential(
            multiplier=1,
            min=1,
            max=60,
        ),
        stop=stop_after_attempt(5),
        reraise=True,
    )
    def _get(
        self,
        path: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        response = self._session.get(
            f"{self._base_url}/{path.lstrip('/')}",
            params=params,
            timeout=self._timeout,
        )

        try:
            payload = response.json()
        except ValueError as error:
            if response.status_code in RETRYABLE_HTTP_STATUS_CODES:
                raise MetaRetryableError(
                    "Meta API returned invalid JSON."
                ) from error

            raise MetaAPIError(
                "Meta API returned invalid JSON."
            ) from error

        if not isinstance(payload, dict):
            raise MetaAPIError(
                "Meta API payload must be an object."
            )

        error_payload = payload.get("error")

        if isinstance(error_payload, dict):
            error_code = int(
                error_payload.get("code") or 0
            )

            if (
                response.status_code
                in RETRYABLE_HTTP_STATUS_CODES
                or error_code in RETRYABLE_META_ERROR_CODES
            ):
                raise MetaRetryableError(
                    f"Temporary Meta API error: {error_code}"
                )

            raise MetaAPIError(
                f"Meta API error code: {error_code}"
            )

        if response.status_code >= 400:
            raise MetaAPIError(
                f"Meta API returned HTTP "
                f"{response.status_code}."
            )

        return payload

    @retry(
        retry=retry_if_exception_type(
            (
                requests.Timeout,
                requests.ConnectionError,
                MetaRetryableError,
            )
        ),
        wait=wait_exponential(
            multiplier=1,
            min=1,
            max=60,
        ),
        stop=stop_after_attempt(5),
        reraise=True,
    )
    def _send_batch(
        self,
        operations: list[dict[str, str]],
    ) -> list[dict[str, Any]]:
        if not operations:
            return []

        if len(operations) > 50:
            raise ValueError(
                "Meta Batch API supports at most 50 operations."
            )

        response = self._session.post(
            f"{self._base_url}/",
            data={
                "access_token": self._access_token,
                "batch": json.dumps(
                    operations,
                    separators=(",", ":"),
                ),
            },
            timeout=self._timeout,
        )

        try:
            payload = response.json()
        except ValueError as error:
            if response.status_code in RETRYABLE_HTTP_STATUS_CODES:
                raise MetaRetryableError(
                    "Meta Batch API returned invalid JSON."
                ) from error

            raise MetaAPIError(
                "Meta Batch API returned invalid JSON."
            ) from error

        if isinstance(payload, dict):
            error_payload = payload.get("error")

            if isinstance(error_payload, dict):
                error_code = int(
                    error_payload.get("code") or 0
                )

                if (
                    response.status_code
                    in RETRYABLE_HTTP_STATUS_CODES
                    or error_code
                    in RETRYABLE_META_ERROR_CODES
                ):
                    raise MetaRetryableError(
                        "Temporary Meta Batch API error: "
                        f"{error_code}"
                    )

                raise MetaAPIError(
                    f"Meta Batch API error code: {error_code}"
                )

        if response.status_code >= 400:
            raise MetaAPIError(
                f"Meta Batch API returned HTTP "
                f"{response.status_code}."
            )

        if not isinstance(payload, list):
            raise MetaAPIError(
                "Meta Batch API payload must be a list."
            )

        return [
            item
            for item in payload
            if isinstance(item, dict)
        ]

    def iter_edge(
        self,
        path: str,
        params: dict[str, Any],
    ) -> Iterator[dict[str, Any]]:
        request_params = dict(params)
        after_cursor: str | None = None

        while True:
            if after_cursor:
                request_params["after"] = after_cursor

            payload = self._get(
                path,
                params=request_params,
            )
            records = payload.get("data", [])

            if not isinstance(records, list):
                raise MetaAPIError(
                    "Meta edge data must be a list."
                )

            for record in records:
                if isinstance(record, dict):
                    yield record

            paging = payload.get("paging", {})

            if not isinstance(paging, dict):
                break

            cursors = paging.get("cursors", {})

            if not isinstance(cursors, dict):
                break

            next_url = paging.get("next")
            next_cursor = cursors.get("after")

            if not next_url or not next_cursor:
                break

            after_cursor = str(next_cursor)

    def get_ad_accounts(
        self,
        business_id: str,
    ) -> list[dict[str, Any]]:
        if not business_id.strip():
            raise ValueError("Meta Business ID is required.")

        accounts: dict[str, dict[str, Any]] = {}

        for source_name, path_template in (
            ACCOUNT_SOURCES.items()
        ):
            path = path_template.format(
                business_id=business_id
            )

            for source_account in self.iter_edge(
                path,
                params={
                    "fields": ",".join(ACCOUNT_FIELDS),
                    "limit": 100,
                },
            ):
                account_object_id = source_account.get("id")

                if not account_object_id:
                    continue

                account_object_id = str(account_object_id)

                account = accounts.setdefault(
                    account_object_id,
                    {
                        "account_object_id": (
                            account_object_id
                        ),
                        "account_id": source_account.get(
                            "account_id"
                        ),
                        "account_name": source_account.get(
                            "name"
                        ),
                        "account_status": source_account.get(
                            "account_status"
                        ),
                        "currency": source_account.get(
                            "currency"
                        ),
                        "timezone_name": source_account.get(
                            "timezone_name"
                        ),
                        "discovery_sources": set(),
                    },
                )

                account["discovery_sources"].add(
                    source_name
                )

        normalized_accounts = []

        for account in accounts.values():
            account["discovery_sources"] = sorted(
                account["discovery_sources"]
            )
            normalized_accounts.append(account)

        return sorted(
            normalized_accounts,
            key=lambda account: account[
                "account_object_id"
            ],
        )

    def scan_accounts_with_spend(
        self,
        accounts: list[dict[str, Any]],
        since: date,
        until: date,
        *,
        batch_size: int = 50,
    ) -> tuple[list[dict[str, Any]], int]:
        if until < since:
            raise ValueError(
                "Meta scan until date must not be "
                "before since date."
            )

        if not 1 <= batch_size <= 50:
            raise ValueError(
                "Meta batch size must be between 1 and 50."
            )

        valid_accounts: list[dict[str, Any]] = []
        error_count = 0

        for account in accounts:
            if account.get("account_object_id"):
                valid_accounts.append(account)
            else:
                error_count += 1

        accounts_with_spend: list[dict[str, Any]] = []

        for start_index in range(
            0,
            len(valid_accounts),
            batch_size,
        ):
            account_batch = valid_accounts[
                start_index : start_index + batch_size
            ]
            operations: list[dict[str, str]] = []

            for account in account_batch:
                account_object_id = str(
                    account["account_object_id"]
                )

                insight_params = {
                    "fields": (
                        "account_id,date_start,"
                        "date_stop,spend"
                    ),
                    "level": "account",
                    "time_increment": "all_days",
                    "time_range": json.dumps(
                        {
                            "since": since.isoformat(),
                            "until": until.isoformat(),
                        },
                        separators=(",", ":"),
                    ),
                    "limit": 10,
                }

                relative_url = (
                    f"{account_object_id}/insights?"
                    f"{urlencode(insight_params)}"
                )

                operations.append(
                    {
                        "method": "GET",
                        "relative_url": relative_url,
                    }
                )

            responses = self._send_batch(operations)

            if len(responses) < len(account_batch):
                error_count += (
                    len(account_batch) - len(responses)
                )

            for account, subresponse in zip(
                account_batch,
                responses,
                strict=False,
            ):
                try:
                    response_code = int(
                        subresponse.get("code") or 0
                    )
                except (TypeError, ValueError):
                    error_count += 1
                    continue

                if response_code != 200:
                    error_count += 1
                    continue

                response_body = subresponse.get("body")

                if not isinstance(response_body, str):
                    error_count += 1
                    continue

                try:
                    body_payload = json.loads(
                        response_body
                    )
                except json.JSONDecodeError:
                    error_count += 1
                    continue

                if not isinstance(body_payload, dict):
                    error_count += 1
                    continue

                if isinstance(
                    body_payload.get("error"),
                    dict,
                ):
                    error_count += 1
                    continue

                insight_rows = body_payload.get(
                    "data",
                    [],
                )

                if not isinstance(insight_rows, list):
                    error_count += 1
                    continue

                total_spend = Decimal("0")
                invalid_spend = False

                for insight_row in insight_rows:
                    if not isinstance(insight_row, dict):
                        continue

                    try:
                        total_spend += Decimal(
                            str(
                                insight_row.get("spend")
                                or "0"
                            )
                        )
                    except InvalidOperation:
                        invalid_spend = True
                        break

                if invalid_spend:
                    error_count += 1
                    continue

                if total_spend > 0:
                    accounts_with_spend.append(account)

        return accounts_with_spend, error_count

    def iter_ad_insights(
        self,
        account_object_id: str,
        since: date,
        until: date,
    ) -> Iterator[dict[str, Any]]:
        if not account_object_id.strip():
            raise ValueError(
                "Meta account object ID is required."
            )

        if until < since:
            raise ValueError(
                "Meta insight until date must not be "
                "before since date."
            )

        time_range = json.dumps(
            {
                "since": since.isoformat(),
                "until": until.isoformat(),
            },
            separators=(",", ":"),
        )

        yield from self.iter_edge(
            f"/{account_object_id}/insights",
            params={
                "fields": ",".join(INSIGHT_FIELDS),
                "level": "ad",
                "time_increment": 1,
                "time_range": time_range,
                "use_account_attribution_setting": (
                    "true"
                ),
                "limit": 500,
            },
        )