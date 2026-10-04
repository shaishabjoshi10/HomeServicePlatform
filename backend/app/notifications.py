"""
Notifications for important booking events.

These helpers only add rows to the caller's session; the caller commits, so a
notification is stored together with the event that caused it.

  event                    customer                   provider
  -----------------------  -------------------------  ---------------------
  booking request sent     "Booking request sent"     "New booking request"
  accepted / rejected      yes                        -
  customer cancels         -                          "Booking cancelled"
  on the way / arrived     yes                        -
  payment successful       "Payment successful"       "Payment received"
  booking completed        "Booking completed"        -

Customer text never names the provider (customers aren't shown who was
assigned).
"""

from app.models import Booking, BookingStatus, Notification


def _add(db, user_id, booking, title, message):
    db.add(Notification(user_id=user_id, booking_id=booking.id, title=title, message=message))


def _job(booking: Booking) -> str:
    return booking.job_title or booking.service_category or "service"


def notify_booking_created(db, booking: Booking, customer_name: str) -> None:
    """Call after db.flush() so booking.id exists."""
    job = _job(booking)
    _add(db, booking.customer_id, booking, "Booking request sent",
         f"Your request for {job} has been sent.")
    _add(db, booking.provider_id, booking, "New booking request",
         f"{customer_name} requested {job}.")


def notify_status_change(db, booking: Booking, status: BookingStatus, customer_name: str) -> None:
    job = _job(booking)
    customer, provider = booking.customer_id, booking.provider_id

    if status == BookingStatus.accepted:
        _add(db, customer, booking, "Booking accepted", f"Your {job} booking was accepted.")
    elif status == BookingStatus.rejected:
        _add(db, customer, booking, "Booking rejected", f"Your {job} request was not accepted.")
    elif status == BookingStatus.cancelled:
        _add(db, provider, booking, "Booking cancelled", f"{customer_name} cancelled their {job} request.")
    elif status == BookingStatus.on_the_way:
        _add(db, customer, booking, "Provider on the way", f"Your provider is on the way for {job}.")
    elif status == BookingStatus.arrived:
        _add(db, customer, booking, "Provider arrived", f"Your provider has arrived for {job}.")
    elif status == BookingStatus.completed:
        _add(db, customer, booking, "Booking completed", f"Your {job} booking is completed.")


def notify_payment_successful(db, booking: Booking, customer_name: str) -> None:
    """Call once, when a payment first becomes 'paid'."""
    job = _job(booking)
    _add(db, booking.customer_id, booking, "Payment successful", f"Your payment for {job} was successful.")
    _add(db, booking.provider_id, booking, "Payment received", f"{customer_name} paid for {job}.")
