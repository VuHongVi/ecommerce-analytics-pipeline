import json

from ecommerce_analytics.transformers.pancake_order import (
    serialize_and_hash_order,
)


def test_order_payload_removes_sensitive_data():
    source_order = {
        "id": "order-1",
        "bill_phone_number": "0900000000",
        "customer": {
            "name": "Customer Name",
            "phone_number": "0900000000",
        },
        "shipping_address": {
            "province_name": "Hà Nội",
            "full_address": "Private address",
            "phone_number": "0900000000",
        },
        "partner": {
            "partner_name": "GHTK",
            "service_partner": {
                "user_secret": "private-secret",
            },
        },
        "items": [
            {
                "id": "item-1",
                "variation_info": {
                    "name": "Sản phẩm A",
                },
                "assigning_seller": {
                    "name": "Nhân viên A",
                    "email": "private@example.com",
                },
            }
        ],
    }

    payload_json, payload_hash = serialize_and_hash_order(
        source_order
    )
    sanitized_order = json.loads(payload_json)

    assert "customer" not in sanitized_order
    assert "bill_phone_number" not in sanitized_order

    assert sanitized_order["shipping_address"] == {
        "province_name": "Hà Nội"
    }

    assert sanitized_order["partner"] == {
        "partner_name": "GHTK"
    }

    seller = sanitized_order["items"][0]["assigning_seller"]
    assert seller == {"name": "Nhân viên A"}

    assert len(payload_hash) == 32