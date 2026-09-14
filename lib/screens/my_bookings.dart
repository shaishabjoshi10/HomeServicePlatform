import 'package:flutter/material.dart';
import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import 'booking_details_page.dart';

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
          : RefreshIndicator(
        onRefresh: _load,
        color: kPrimaryGreen,
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: _bookings.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final b = _bookings[index];
            // Kept intentionally minimal — just enough to identify and
            // triage a booking at a glance. Everything else (address,
            // notes, timeline, cancel/rate actions) lives on the details
            // page now, one tap on the card away.
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openDetails(b),
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
                          child: Text(b.providerName,
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
                    if (b.serviceCategory != null) ...[
                      const SizedBox(height: 2),
                      Text(b.serviceCategory!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
    );
  }
}