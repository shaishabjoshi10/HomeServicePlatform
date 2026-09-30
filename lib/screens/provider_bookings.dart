import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../models/provider_profile.dart';
import '../services/booking_service.dart';
import '../services/provider_service.dart';
import 'provider_booking_details_page.dart';

enum _ProviderFilter { all, pending, active, completed, declined }

class ProviderBookingsPage extends StatefulWidget {
  final String accessToken;

  const ProviderBookingsPage({super.key, required this.accessToken});

  @override
  State<ProviderBookingsPage> createState() => _ProviderBookingsPageState();
}

class _ProviderBookingsPageState extends State<ProviderBookingsPage> {
  List<Booking> _bookings = [];
  bool _loading = true;
  String? _error;
  _ProviderFilter _filter = _ProviderFilter.all;

  // This page can be opened independently of the home page (e.g. from the
  // bottom nav), so it fetches the provider's own verification status
  // itself rather than assuming a caller already has it — it's needed
  // both for the banner below and for what ProviderBookingDetailsPage is
  // allowed to let the provider do once they tap into a booking.
  ProviderProfile? _profile;

  bool get _isVerified => _profile?.isVerified ?? false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProviderService.getMyProfile(widget.accessToken);
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {
      // Informational only (drives the banner below and the Accept gate);
      // if it fails to load, _isVerified just stays false — the safer,
      // fail-closed default — rather than surfacing a separate error UI.
    }
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

  Future<void> _openDetails(Booking booking) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderBookingDetailsPage(
          accessToken: widget.accessToken,
          booking: booking,
          isVerified: _isVerified,
        ),
      ),
    );
    if (mounted) _load();
  }

  // ── Filtering ─────────────────────────────────────────────────────────

  /// "Active" = accepted jobs that are underway or about to be (Accepted,
  /// On the Way, Arrived). Pending requests get their own chip because a
  /// provider needs to find them quickly to accept or decline.
  bool _matches(Booking b, _ProviderFilter filter) {
    switch (filter) {
      case _ProviderFilter.all:
        return true;
      case _ProviderFilter.pending:
        return b.status == 'pending';
      case _ProviderFilter.active:
        return b.status == 'accepted' || b.status == 'on_the_way' || b.status == 'arrived';
      case _ProviderFilter.completed:
        return b.status == 'completed';
      case _ProviderFilter.declined:
        return b.status == 'rejected' || b.status == 'cancelled';
    }
  }

  int _count(_ProviderFilter filter) => _bookings.where((b) => _matches(b, filter)).length;

  String _filterLabel(_ProviderFilter filter) {
    switch (filter) {
      case _ProviderFilter.all:
        return 'All';
      case _ProviderFilter.pending:
        return 'Pending';
      case _ProviderFilter.active:
        return 'Active';
      case _ProviderFilter.completed:
        return 'Completed';
      case _ProviderFilter.declined:
        return 'Declined';
    }
  }

  String _emptyMessage(_ProviderFilter filter) {
    switch (filter) {
      case _ProviderFilter.all:
        return 'No bookings yet.';
      case _ProviderFilter.pending:
        return 'No pending requests.';
      case _ProviderFilter.active:
        return 'No active bookings.';
      case _ProviderFilter.completed:
        return 'No completed bookings.';
      case _ProviderFilter.declined:
        return 'No declined or cancelled bookings.';
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────

  Widget _buildVerificationBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Pending Verification — you can decline requests, but can\'t accept them until an admin verifies your account.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: _ProviderFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _ProviderFilter.values[index];
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

  Widget _buildCard(Booking b) {
    final hasDescription = b.problemDescription != null && b.problemDescription!.isNotEmpty;
    // Job plus its category ("Fan Installation · Electrical"), falling
    // back to whichever one exists.
    final serviceText = b.jobTitle != null && b.serviceCategory != null
        ? '${b.jobTitle} · ${b.serviceCategory}'
        : (b.jobTitle != null || b.serviceCategory != null ? b.displayTitle : null);

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
              // Primary: customer name (left), status badge (top-right).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      b.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: kDarkText),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: b.status),
                ],
              ),
              // Primary: price the job was booked at, so jobs can be
              // triaged by value, with the job/service alongside.
              if (b.hasPrice || serviceText != null) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (b.hasPrice)
                      Text(
                        b.priceLabel!,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kPrimaryGreen),
                      ),
                    if (b.hasPrice && serviceText != null)
                      Text('  ·  ', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400)),
                    if (serviceText != null)
                      Flexible(
                        child: Text(
                          serviceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ],
              // Secondary: problem description.
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
              if (b.preferredDate != null) ...[
                SizedBox(height: hasDescription ? 4 : 6),
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12.5, color: Colors.grey.shade500),
                    const SizedBox(width: 5),
                    Text(
                      '${b.preferredDate!.year}-${b.preferredDate!.month.toString().padLeft(2, '0')}-${b.preferredDate!.day.toString().padLeft(2, '0')}'
                          ' · ${TimeOfDay.fromDateTime(b.preferredDate!).format(context)}',
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
        title: const Text('Bookings'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_profile != null && !_isVerified) _buildVerificationBanner(),
          if (!_loading && _error == null && _bookings.isNotEmpty) _buildFilters(),
          Expanded(
            child: _loading
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
                : _buildList(),
          ),
        ],
      ),
    );
  }
}

/// Status badge for a booking card: tinted pill with an icon and label.
/// Private to this screen on purpose, so changing it here can't affect
/// any other booking list.
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  static String _label(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'on_the_way':
        return 'On the Way';
      case 'arrived':
        return 'Arrived';
      case 'completed':
        return 'Completed';
      default:
        return 'Pending';
    }
  }

  static Color _color(String status) {
    switch (status) {
      case 'accepted':
        return kPrimaryGreen;
      case 'rejected':
      case 'cancelled':
        return Colors.red.shade700;
      case 'on_the_way':
        return Colors.blue.shade700;
      case 'arrived':
        return Colors.purple.shade700;
      case 'completed':
        return Colors.teal.shade700;
      default:
        return Colors.orange.shade800;
    }
  }

  static IconData _icon(String status) {
    switch (status) {
      case 'accepted':
        return Icons.check_circle_outline_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'cancelled':
        return Icons.block_rounded;
      case 'on_the_way':
        return Icons.directions_run_rounded;
      case 'arrived':
        return Icons.place_rounded;
      case 'completed':
        return Icons.task_alt_rounded;
      default:
        return Icons.schedule_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(status), size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            _label(status),
            style: TextStyle(fontSize: 11.5, height: 1.1, color: c, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}