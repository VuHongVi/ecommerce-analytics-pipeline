import hashlib
import json
from typing import Any

SENSITIVE_KEYS = frozenset(
    {
        "address",
        "avatar_url",
        "bank_payments",
        "bill_email",
        "bill_full_name",
        "bill_phone_number",
        "botcake_info",
        "conversation_id",
        "conversation_link",
        "customer",
        "customer_needs",
        "date_of_birth",
        "delivery_tel",
        "einvoices",
        "email",
        "emails",
        "fb_id",
        "full_address",
        "full_name",
        "histories",
        "identity_code",
        "link",
        "new_full_address",
        "note",
        "note_image",
        "note_print",
        "notes",
        "order_link",
        "phone_number",
        "phone_numbers",
        "pick_address",
        "pick_name",
        "pick_street",
        "pick_tel",
        "service_partner",
        "settings",
        "status_history",
        "tel",
        "tracking_link",
        "transfer_proofs",
        "user_name",
        "user_secret",
        "username",
    }
)


def sanitize_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            key: sanitize_value(child_value)
            for key, child_value in value.items()
            if key not in SENSITIVE_KEYS
        }

    if isinstance(value, list):
        return [sanitize_value(item) for item in value]

    return value


def serialize_and_hash_order(
    order: dict[str, Any],
) -> tuple[str, bytes]:
    sanitized_order = sanitize_value(order)

    payload_json = json.dumps(
        sanitized_order,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        default=str,
    )

    payload_hash = hashlib.sha256(payload_json.encode("utf-8")).digest()

    return payload_json, payload_hash
