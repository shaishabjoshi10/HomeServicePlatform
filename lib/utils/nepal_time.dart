/// Booking times are always Nepal time (Asia/Kathmandu, UTC+05:45), whatever
/// timezone the phone or the server is set to. Nepal has no daylight saving,
/// so a fixed offset is exact.
const Duration kNepalUtcOffset = Duration(hours: 5, minutes: 45);

/// Converts a moment in time (what the server sends) into Nepal wall-clock
/// fields. Read `.year/.month/.day/.hour/.minute` from the result as Nepal
/// time. It is only a carrier for those fields; do not treat it as an instant.
DateTime toNepalTime(DateTime instant) => instant.toUtc().add(kNepalUtcOffset);

/// The current Nepal wall-clock time, for "today" / "tomorrow" comparisons.
DateTime nepalNow() => toNepalTime(DateTime.now());

/// Formats Nepal wall-clock fields (e.g. the date and time the customer
/// picked) as an ISO-8601 string with an explicit +05:45 offset, so the
/// server stores the right moment regardless of the phone's timezone.
String nepalWallClockToIso8601(DateTime wallClock) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${wallClock.year.toString().padLeft(4, '0')}-${two(wallClock.month)}-${two(wallClock.day)}'
      'T${two(wallClock.hour)}:${two(wallClock.minute)}:${two(wallClock.second)}+05:45';
}
