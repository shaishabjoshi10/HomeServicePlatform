"""eSewa ePay v2 helpers.

The merchant secret never leaves FastAPI.  Flutter receives only the signed
form fields needed to start a transaction and sends the base64 response back
to the backend for verification.
"""

import base64
import hashlib
import hmac
import json
import logging
from decimal import Decimal
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.config import settings

logger = logging.getLogger("uvicorn.error")


def money(value: Decimal | float | str) -> str:
    return f"{Decimal(str(value)).quantize(Decimal('0.01')):.2f}"


def sign_fields(fields: dict[str, str], signed_field_names: str | None = None) -> str:
    names = signed_field_names or settings.esewa_signed_field_names
    message = ",".join(f"{name}={fields[name]}" for name in names.split(","))
    digest = hmac.new(
        settings.esewa_secret_key.encode("utf-8"),
        message.encode("utf-8"),
        hashlib.sha256,
    ).digest()
    return base64.b64encode(digest).decode("ascii")


def verify_response_signature(data: dict) -> bool:
    signed_field_names = data.get("signed_field_names")
    signature = data.get("signature")
    if not signed_field_names or not signature:
        return False
    try:
        expected = sign_fields(
            {name: str(data[name]) for name in signed_field_names.split(",")},
            signed_field_names,
        )
    except (KeyError, TypeError):
        return False
    return hmac.compare_digest(expected, str(signature))


def decode_response(encoded_data: str) -> dict:
    # '+' in base64 becomes a space when it passes through a query string.
    encoded_data = encoded_data.strip().replace(" ", "+")
    raw = base64.b64decode(encoded_data, validate=True)
    value = json.loads(raw.decode("utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Invalid eSewa response")
    return value


# eSewa's status API normally answers in well under a second. Keep each host's
# timeout short so the worst case (every host down) stays inside the app's
# request timeout instead of leaving the customer staring at a spinner.
STATUS_CHECK_TIMEOUT_SECONDS = 6


class PaymentGatewayError(Exception):
    """eSewa could not be reached or gave an unusable answer."""


def status_check(transaction_uuid: str, total_amount: Decimal) -> dict:
    query = urlencode(
        {
            "product_code": settings.esewa_product_code,
            "total_amount": money(total_amount),
            "transaction_uuid": transaction_uuid,
        }
    )
    errors: list[str] = []
    for base in settings.esewa_status_urls:
        url = f"{base.rstrip('/')}/?{query}"
        try:
            with urlopen(Request(url, method="GET"), timeout=STATUS_CHECK_TIMEOUT_SECONDS) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:  # network, HTTP error, bad JSON...
            logger.warning("eSewa status check failed at %s: %r", base, exc)
            errors.append(f"{base}: {exc!r}")
    raise PaymentGatewayError("; ".join(errors))