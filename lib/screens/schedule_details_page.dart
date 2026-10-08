import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import '../utils/nepal_time.dart';
import 'provider_booking_details_page.dart';

enum _ScheduleFilter { all, upcoming, completed }

/// Every job on the provider's schedule, grouped by day. Opened from
/// Schedule → "View All" on the provider home. This is deliberately its own
/// page: it is not the Bookings list (that one also holds pending, declined
/// and cancelled requests).
class ScheduleDetailsPage extends StatefulWidget {
  final String accessToken;
  final bool isVerified;

  const ScheduleDetailsPage({
    super.key,
    required this.accessToken,
    required this.isVerified,
  });

  @override
  State<ScheduleDetailsPage> createState() => _ScheduleDetailsPageState();
}

class _ScheduleDetailsPageState extends State<ScheduleDetailsPage> {
  static const _cardBorder = Color(0xFFE9EFEB);
  static const _pageBg = Color(0xFFF7F9F8);
  static const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  // A booking is "on the schedule" once the provider has accepted it, through
  // to completion.
  static const _upcomingStatuses = {'accepted', 'on_the_way', 'arrived'};

  List<Booking> _bookings = [];
  bool _loading = true;
  String? _error;
  _ScheduleFilter _filter = _ScheduleFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bookings = await BookingService.getMyBookings(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _bookings = bookings.where(_isScheduled).toList();
        _loading = false;
        _error = null;
      });
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong loading your schedule.';
        _loading = false;
      });
    }
  }

  bool _isScheduled(Booking b) => _upcomingStatuses.contains(b.status) || b.status == 'completed';

  bool _matches(Booking b, _ScheduleFilter f) {
    switch (f) {
      case _ScheduleFilter.all:
        return true;
      case _ScheduleFilter.upcoming:
        return _upcomingStatuses.contains(b.status);
      case _ScheduleFilter.completed:
        return b.status == 'completed';
    }
  }

  int _count(_ScheduleFilter f) => _bookings.where((b) => _matches(b, f)).length;

  String _filterLabel(_ScheduleFilter f) {
    switch (f) {
      case _ScheduleFilter.all:
        return 'All';
      case _ScheduleFilter.upcoming:
        return 'Upcoming';
      case _ScheduleFilter.completed:
        return 'Completed';
    }
  }

  // ── Dates ──────────────────────────────────────────────────────────

  /// The booking's own scheduled date/time as a Nepal wall-clock value
  /// (same reading the home Schedule uses).
  DateTime? _scheduledAt(Booking b) {
    final d = b.preferredDateNepal;
    if (d == null) return null;
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
  }

  int _daysFromToday(DateTime day) {
    final now = nepalNow();
    final today = DateTime.utc(now.year, now.month, now.day);
    return DateTime.utc(day.year, day.month, day.day).difference(today).inDays;
  }

  String _dayLabel(DateTime day) {
    switch (_daysFromToday(day)) {
      case 0:
        return 'Today';
      case 1:
        return 'Tomorrow';
      case -1:
        return 'Yesterday';
    }
    return '${_weekdayNames[day.weekday - 1]}, ${day.day} ${_monthNames[day.month - 1]} ${day.year}';
  }

  /// Visible bookings in date/time order. Upcoming work reads soonest-first;
  /// finished work sorts after it, most recent first.
  List<Booking> get _visible {
    final list = _bookings.where((b) => _matches(b, _filter)).toList();
    int cmp(Booking a, Booking b) {
      final x = _scheduledAt(a);
      final y = _scheduledAt(b);
      if (x == null && y == null) return a.id.compareTo(b.id);
      if (x == null) return 1;
      if (y == null) return -1;
      final t = x.compareTo(y);
      return t != 0 ? t : a.id.compareTo(b.id);
    }

    final upcoming = list.where((b) => _upcomingStatuses.contains(b.status)).toList()..sort(cmp);
    final done = list.where((b) => b.status == 'completed').toList()..sort((a, b) => cmp(b, a));
    return [...upcoming, ...done];
  }

  Future<void> _openDetails(Booking b) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderBookingDetailsPage(
          accessToken: widget.accessToken,
          booking: b,
          isVerified: widget.isVerified,
        ),
      ),
    );
    if (mounted) _load(silent: true);
  }

  // ── UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w700, color: kDarkText)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: kDarkText),
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in _ScheduleFilter.values)
            ChoiceChip(
              label: Text('${_filterLabel(f)} (${_count(f)})'),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: kLightGreenBg,
              labelStyle: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _filter == f ? kPrimaryGreen : kDarkText,
              ),
              side: BorderSide(color: _filter == f ? kPrimaryGreen : _cardBorder),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimaryGreen));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final items = _visible;
    if (items.isEmpty) {
      return RefreshIndicator(
        color: kPrimaryGreen,
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 80),
            Icon(Icons.event_available_outlined, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _filter == _ScheduleFilter.completed ? 'No completed jobs yet.' : 'No appointments scheduled.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      );
    }

    // Group under each booking's own day; the list is already ordered.
    final groups = <DateTime?, List<Booking>>{};
    for (final b in items) {
      final at = _scheduledAt(b);
      final day = at == null ? null : DateTime.utc(at.year, at.month, at.day);
      groups.putIfAbsent(day, () => []).add(b);
    }

    return RefreshIndicator(
      color: kPrimaryGreen,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          for (final entry in groups.entries) ...[
            _buildDayHeader(entry.key, entry.value.length),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _cardBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < entry.value.length; i++) ...[
                    _buildRow(entry.value[i]),
                    if (i != entry.value.length - 1) const Divider(height: 1, color: _cardBorder),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayHeader(DateTime? day, int count) {
    final overdue = day != null && _daysFromToday(day) < 0 && entryHasUpcoming(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(
            day == null ? 'Date not set' : _dayLabel(day),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kDarkText),
          ),
          const SizedBox(width: 8),
          Text('$count ${count == 1 ? 'job' : 'jobs'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (overdue) ...[
            const SizedBox(width: 8),
            Text('Overdue',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
          ],
        ],
      ),
    );
  }

  /// True when [day] still holds a job that has not been completed.
  bool entryHasUpcoming(DateTime day) {
    for (final b in _bookings) {
      if (!_upcomingStatuses.contains(b.status)) continue;
      final at = _scheduledAt(b);
      if (at != null && at.year == day.year && at.month == day.month && at.day == day.day) return true;
    }
    return false;
  }

  (String, Color, Color) _statusStyle(String status) {
    switch (status) {
      case 'on_the_way':
        return ('On the way', Colors.blue.shade700, Colors.blue.shade50);
      case 'arrived':
        return ('Arrived', Colors.indigo.shade700, Colors.indigo.shade50);
      case 'completed':
        return ('Completed', Colors.grey.shade700, Colors.grey.shade200);
      default:
        return ('Confirmed', kPrimaryGreen, kLightGreenBg);
    }
  }

  Widget _buildRow(Booking b) {
    final at = _scheduledAt(b);
    final (label, fg, bg) = _statusStyle(b.status);
    final hasJob = b.jobTitle != null || b.serviceCategory != null;
    return InkWell(
      onTap: () => _openDetails(b),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: kLightGreenBg, borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.handyman_outlined, size: 20, color: kPrimaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(b.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      if (b.isEmergency) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.emergency_rounded, size: 14, color: Colors.red.shade700),
                      ],
                    ],
                  ),
                  if (hasJob)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.jobTitle != null && b.serviceCategory != null
                                  ? '${b.jobTitle} · ${b.serviceCategory}'
                                  : b.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                          if (b.hasPrice) ...[
                            const SizedBox(width: 8),
                            Text(b.priceLabel!,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: kPrimaryGreen)),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(b.address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (at != null) ...[
                  Text(
                    TimeOfDay(hour: at.hour, minute: at.minute).format(context),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kDarkText),
                  ),
                  const SizedBox(height: 5),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                  child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
