import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../models/provider_profile.dart';
import '../services/booking_service.dart';
import '../services/provider_service.dart';
import 'provider_booking_details_page.dart';

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
  String _filter = 'All';

  // This page can be opened independently of the home page (e.g. from the
  // bottom nav), so it fetches the provider's own verification status
  // itself rather than assuming a caller already has it — it's needed
  // both for the banner below and for what ProviderBookingDetailsPage is
  // allowed to let the provider do once they tap into a booking.
  ProviderProfile? _profile;

  bool get _isVerified => _profile?.isVerified ?? false;

  static const _filters = ['All', 'Pending', 'Accepted', 'On the Way', 'Arrived', 'Completed', 'Declined'];

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

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return kPrimaryGreen;
      case 'rejected':
      case 'cancelled':
        return Colors.red.shade600;
      case 'on_the_way':
        return Colors.blue.shade600;
      case 'arrived':
        return Colors.purple.shade600;
      case 'completed':
        return Colors.teal.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  String _statusLabel(String status) {
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

  List<Booking> get _filtered {
    switch (_filter) {
      case 'Pending':
        return _bookings.where((b) => b.status == 'pending').toList();
      case 'Accepted':
        return _bookings.where((b) => b.status == 'accepted').toList();
      case 'On the Way':
        return _bookings.where((b) => b.status == 'on_the_way').toList();
      case 'Arrived':
        return _bookings.where((b) => b.status == 'arrived').toList();
      case 'Completed':
        return _bookings.where((b) => b.status == 'completed').toList();
      case 'Declined':
        return _bookings.where((b) => b.status == 'rejected' || b.status == 'cancelled').toList();
      default:
        return _bookings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_profile != null && !_isVerified)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = filter == _filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _filter = filter),
                  selectedColor: kLightGreenBg,
                  labelStyle: TextStyle(
                    color: isSelected ? kPrimaryGreen : Colors.grey.shade700,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: isSelected ? kPrimaryGreen : Colors.grey.shade300),
                  ),
                  backgroundColor: Colors.white,
                );
              },
            ),
          ),
          const SizedBox(height: 4),
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
                : filtered.isEmpty
                ? Center(
              child: Text('No bookings here yet.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            )
                : RefreshIndicator(
              onRefresh: _load,
              color: kPrimaryGreen,
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final b = filtered[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProviderBookingDetailsPage(
                            accessToken: widget.accessToken,
                            booking: b,
                            isVerified: _isVerified,
                          ),
                        ),
                      );
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(b.customerName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(b.status).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _statusLabel(b.status),
                                  style: TextStyle(
                                      fontSize: 11, color: _statusColor(b.status), fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
                            ],
                          ),
                          // Job (or service) plus the price it was booked
                          // at, so a provider can triage jobs by value as
                          // well as by type.
                          if (b.jobTitle != null || b.serviceCategory != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    b.jobTitle != null && b.serviceCategory != null
                                        ? '${b.jobTitle} · ${b.serviceCategory}'
                                        : b.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                ),
                                if (b.hasPrice) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    b.priceLabel!,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: kPrimaryGreen),
                                  ),
                                ],
                              ],
                            ),
                          ],
                          if (b.preferredDate != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
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
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}