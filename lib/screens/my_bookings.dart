import 'package:flutter/material.dart';
import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import 'booking_details_page.dart';

enum _BookingFilter { all, active, completed }

/// Colour, icon and label for a booking status. Kept in one place so the
/// badge looks identical on every card.
class _StatusStyle {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusStyle(this.label, this.color, this.icon);
}

class MyBookingsPage extends StatefulWidget {
  final String accessToken;

  const MyBookingsPage({super.key, required this.accessToken});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  List<Booking> _bookings = [];
  bool _loading = true;
  String? _error;
  _BookingFilter _filter = _BookingFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await BookingService.getMyBookings(accessToken: widget.accessToken);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
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
        _error = 'Something went wrong loading your bookings.';
        _loading = false;
      });
    }
  }

  // Always reload from the server after returning from the details page,
  // rather than trying to merge back whatever may have changed there
  // (cancelled, rated, or just moved along the provider's timeline) —
  // simpler, and it can't drift out of sync with the backend.
  Future<void> _openDetails(Booking booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailsPage(accessToken: widget.accessToken, booking: booking),
      ),
    );
    if (mounted) _load();
  }

  // ── Status styling ────────────────────────────────────────────────────

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'accepted':
        return _StatusStyle('Accepted', kPrimaryGreen, Icons.check_circle_outline_rounded);
      case 'rejected':
        return _StatusStyle('Declined', Colors.red.shade700, Icons.cancel_outlined);
      case 'cancelled':
        return _StatusStyle('Cancelled', Colors.red.shade700, Icons.block_rounded);
      case 'on_the_way':
        return _StatusStyle('On the Way', Colors.blue.shade700, Icons.directions_run_rounded);
      case 'arrived':
        return _StatusStyle('Arrived', Colors.purple.shade700, Icons.place_rounded);
      case 'completed':
        return _StatusStyle('Completed', Colors.teal.shade700, Icons.task_alt_rounded);
      default:
        return _StatusStyle('Pending', Colors.orange.shade800, Icons.schedule_rounded);
    }
  }

  // ── Filtering ─────────────────────────────────────────────────────────

  /// "Active" = anything still in progress. Declined and cancelled
  /// bookings are neither active nor completed, so they only appear
  /// under "All".
  bool _isActive(String status) =>
      status == 'pending' || status == 'accepted' || status == 'on_the_way' || status == 'arrived';

  bool _matches(Booking b, _BookingFilter filter) {
    switch (filter) {
      case _BookingFilter.all:
        return true;
      case _BookingFilter.active:
        return _isActive(b.status);
      case _BookingFilter.completed:
        return b.status == 'completed';
    }
  }

  int _count(_BookingFilter filter) => _bookings.where((b) => _matches(b, filter)).length;

  String _filterLabel(_BookingFilter filter) {
    switch (filter) {
      case _BookingFilter.all:
        return 'All';
      case _BookingFilter.active:
        return 'Active';
      case _BookingFilter.completed:
        return 'Completed';
    }
  }

  String _emptyMessage(_BookingFilter filter) {
    switch (filter) {
      case _BookingFilter.all:
        return 'No bookings yet.';
      case _BookingFilter.active:
        return 'No active bookings.';
      case _BookingFilter.completed:
        return 'No completed bookings.';
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────

  Widget _buildFilters() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: _BookingFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _BookingFilter.values[index];
          final selected = _filter == filter;
          return ChoiceChip(
            label: Text('${_filterLabel(filter)} (${_count(filter)})'),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = filter),
            selectedColor: kPrimaryGreen,
            backgroundColor: Colors.white,
            side: BorderSide(color: selected ? kPrimaryGreen : Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            visualDensity: VisualDensity.compact,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final style = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.color),
          const SizedBox(width: 4),
          Text(
            style.label,
            style: TextStyle(fontSize: 11.5, height: 1.1, color: style.color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Booking b) {
    final hasDescription = b.problemDescription != null && b.problemDescription!.isNotEmpty;
    final showPriceLine = b.jobTitle != null || b.hasPrice;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetails(b),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary: service name (left) and status badge (top-right).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    // The specific job where there is one ("Fan
                    // Installation"), falling back to the service
                    // category for older or category-level bookings.
                    child: Text(
                      b.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: kDarkText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(b.status),
                ],
              ),
              // Primary: agreed price (snapshotted at booking time), with
              // the service category alongside as context.
              if (showPriceLine) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (b.hasPrice)
                      Text(
                        b.priceLabel!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kPrimaryGreen),
                      ),
                    if (b.serviceCategory != null && b.hasPrice)
                      Text('  ·  ', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400)),
                    if (b.serviceCategory != null)
                      Flexible(
                        child: Text(
                          b.serviceCategory!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ],
              // Secondary: problem description — the identifying detail
              // when two bookings share the same title.
              if (hasDescription) ...[
                const SizedBox(height: 6),
                Text(
                  b.problemDescription!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
              // Secondary: date & time.
              if (b.preferredDateNepal != null) ...[
                SizedBox(height: hasDescription ? 4 : 6),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12.5, color: Colors.grey.shade500),
                    const SizedBox(width: 5),
                    Text(
                      '${b.preferredDateNepal!.year}-${b.preferredDateNepal!.month.toString().padLeft(2, '0')}-${b.preferredDateNepal!.day.toString().padLeft(2, '0')}'
                          ' · ${TimeOfDay.fromDateTime(b.preferredDateNepal!).format(context)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final visible = _bookings.where((b) => _matches(b, _filter)).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: kPrimaryGreen,
      child: visible.isEmpty
      // Still scrollable so pull-to-refresh works on an empty filter.
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 200,
            child: Center(
              child: Text(
                _emptyMessage(_filter),
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      )
          : ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _buildCard(visible[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryGreen))
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      )
          : _bookings.isEmpty
          ? Center(
        child: Text(
          'No bookings yet.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      )
          : Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}