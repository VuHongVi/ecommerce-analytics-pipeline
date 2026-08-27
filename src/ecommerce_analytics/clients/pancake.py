import time
from collections.abc import Iterator
from datetime import UTC, datetime
from typing import Any

import requests
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

PANCAKE_BASE_URL = "https://pos.pages.fm/api/v1"
RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}


class PancakeAPIError(RuntimeError):
    """Raised when the Pancake API request fails."""


class PancakePermissionError(PancakeAPIError):
    """Raised when access to a Pancake shop is forbidden."""


class PancakeRetryableError(PancakeAPIError):
    """Raised for temporary Pancake API failures."""


def _unix_timestamp(value: datetime) -> int:
    if value.tzinfo is None:
        raise ValueError("Datetime must include timezone information.")

    return int(value.astimezone(UTC).timestamp())


class PancakeClient:
    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = PANCAKE_BASE_URL,
        page_size: int = 100,
        request_delay: float = 0.25,
        timeout: int = 90,
    ) -> None:
        if not api_key.strip():
            raise ValueError("Pancake API key is required.")

        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._page_size = page_size
        self._request_delay = request_delay
        self._timeout = timeout
        self._session = requests.Session()

    def close(self) -> None:
        self._session.close()

    def __enter__(self) -> "PancakeClient":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    @retry(
        retry=retry_if_exception_type(
            (
                requests.Timeout,
                requests.ConnectionError,
                PancakeRetryableError,
            )
        ),
        wait=wait_exponential(
            multiplier=1,
            min=1,
            max=30,
        ),
        stop=stop_after_attempt(5),
        reraise=True,
    )
    def _get(
        self,
        path: str,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        request_params = dict(params or {})
        request_params["api_key"] = self._api_key

        response = self._session.get(
            f"{self._base_url}/{path.lstrip('/')}",
            params=request_params,
            timeout=self._timeout,
        )

        if response.status_code in RETRYABLE_STATUS_CODES:
            raise PancakeRetryableError(
                f"Temporary Pancake API error: "
                f"HTTP {response.status_code}"
            )

        if response.status_code == 403:
            raise PancakePermissionError(
                "Pancake API returned HTTP 403."
            )

        if response.status_code >= 400:
            raise PancakeAPIError(
                f"Pancake API returned HTTP "
                f"{response.status_code}."
            )

        try:
            payload = response.json()
        except ValueError as error:
            raise PancakeRetryableError(
                "Pancake API returned invalid JSON."
            ) from error

        if not isinstance(payload, dict):
            raise PancakeAPIError(
                "Pancake API payload must be an object."
            )

        if payload.get("success") is False:
            raise PancakeAPIError(
                "Pancake API returned success=false."
            )

        return payload

    def get_shops(self) -> list[dict[str, Any]]:
        payload = self._get("/shops")
        shops = payload.get("shops", [])

        if not isinstance(shops, list):
            raise PancakeAPIError(
                "Pancake shops payload must be a list."
            )

        return [
            shop
            for shop in shops
            if isinstance(shop, dict)
        ]

    def iter_orders(
        self,
        shop_id: str,
        start_datetime: datetime,
        end_datetime: datetime,
        *,
        update_status: str,
    ) -> Iterator[dict[str, Any]]:
        if update_status not in {"inserted_at", "updated_at"}:
            raise ValueError(
                "update_status must be inserted_at or updated_at."
            )

        page_number = 1

        while True:
            payload = self._get(
                f"/shops/{shop_id}/orders",
                params={
                    "page_number": page_number,
                    "page_size": self._page_size,
                    "updateStatus": update_status,
                    "startDateTime": _unix_timestamp(start_datetime),
                    "endDateTime": _unix_timestamp(end_datetime),
                    "option_sort": f"{update_status}_asc",
                },
            )

            orders = payload.get("data", [])

            if not isinstance(orders, list):
                raise PancakeAPIError(
                    "Pancake orders payload must be a list."
                )

            for order in orders:
                if isinstance(order, dict):
                    yield order

            total_pages = int(payload.get("total_pages") or 1)

            if page_number >= total_pages:
                break

            page_number += 1
            time.sleep(self._request_delay)