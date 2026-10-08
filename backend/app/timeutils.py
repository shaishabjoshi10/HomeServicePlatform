"""Single place that defines how booking date/times are interpreted.

Rule used across the stack:
  * The app serves Kathmandu only, so a booking time the customer picks is a
    Nepal wall-clock time (Asia/Kathmandu, UTC+05:45).
  * It is stored in PostgreSQL as an unambiguous instant (UTC, timestamptz).
  * It is always sent back to clients with an explicit +05:45 offset, so every
    client shows the same date and time no matter the phone's or the database
    session's timezone.

Nepal has had no daylight-saving time since 1986, so a fixed offset is exact.
(A fixed offset is used instead of zoneinfo so no tzdata package is needed,
which is not installed by default on Windows.)
"""
from datetime import datetime, timedelta, timezone

NEPAL_TZ = timezone(timedelta(hours=5, minutes=45), name="Asia/Kathmandu")


def to_utc(value: datetime) -> datetime:
    """Convert to UTC. A naive value is taken to be Nepal local time."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=NEPAL_TZ)
    return value.astimezone(timezone.utc)


def to_nepal(value: datetime) -> datetime:
    """Convert to Nepal time. A naive value is taken to be UTC (legacy rows)."""
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(NEPAL_TZ)
