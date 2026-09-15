import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import 'booking_timeline.dart';

/// Full detail view for one of the provider's own bookings — customer info,
/// address, notes, timestamps, the status timeline, and the accept/decline/
/// journey/complete actions. Mirrors [BookingDetailsPage] (the customer-side
/// equivalent) in layout, spacing, and button styling; only the information
/// shown and the available actions differ, since a provider needs to see who
/// booked them (and their phone number) and needs to move the booking through
/// its lifecycle rather than cancel or rate it.
///
/// This page keeps its own local copy of the booking so accept/decline/
/// journey/complete reflect immediately without waiting on the list to
/// reload; the list re-fetches from the server itself once the provider
/// navigates back, so it always ends up showing the current state regardless.
class ProviderBookingDetailsPage extends StatefulWidget {
  final String accessToken;
  final Booking booking;

  const ProviderBookingDetailsPage({super.key, required this.accessToken, required this.booking});

  @override
  State<ProviderBookingDetailsPage> createState() => _ProviderBookingDetailsPageState();
}

class _ProviderBookingDetailsPageState extends State<ProviderBookingDetailsPage> {
  late Booking _booking;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  Future<void> _respond(String status) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final updated = await BookingService.updateStatus(
        accessToken: widget.accessToken,
        bookingId: _booking.id,
        status: status,
      );
      if (!mounted) return;
      setState(() => _booking = updated);
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Details'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(b.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: kDarkText)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(b.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(b.status),
                    style: TextStyle(fontSize: 11, color: _statusColor(b.status), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (b.serviceCategory != null) ...[
              const SizedBox(height: 4),
              Text(b.serviceCategory!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
            if (b.status != 'rejected' && b.status != 'cancelled') ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: BookingTimeline(status: b.status),
              ),
            ],
            const SizedBox(height: 20),
            if (b.customerPhone != null && b.customerPhone!.isNotEmpty)
              _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: b.customerPhone!),
            _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: b.address),
            if (b.preferredDate != null)
              _DetailRow(
                icon: Icons.event_outlined,
                label: 'Date & Time',
                value: '${_formatDate(b.preferredDate!)}'
                    ' · ${TimeOfDay.fromDateTime(b.preferredDate!).format(context)}',
              ),
            if (b.problemDescription != null && b.problemDescription!.isNotEmpty)
              _DetailRow(
                icon: Icons.report_problem_outlined,
                label: 'Problem Description',
                value: b.problemDescription!,
              ),
            if (b.notes != null && b.notes!.isNotEmpty)
              _DetailRow(icon: Icons.notes_rounded, label: 'Notes', value: b.notes!),
            _DetailRow(icon: Icons.access_time_rounded, label: 'Requested On', value: _formatDate(b.createdAt)),
            if (b.status == 'pending') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _updating ? null : () => _respond('rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _updating ? null : () => _respond('accepted'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _updating
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Accept'),
                ),
              ),
            ],
            if (b.status == 'accepted') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _updating ? null : () => _respond('on_the_way'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.directions_car_filled_outlined, size: 18),
                  label: const Text("I'm on My Way"),
                ),
              ),
            ],
            if (b.status == 'on_the_way') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _updating ? null : () => _respond('arrived'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.location_on_outlined, size: 18),
                  label: const Text("I've Arrived"),
                ),
              ),
            ],
            if (b.status == 'arrived') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _updating ? null : () => _respond('completed'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Mark as Completed'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kPrimaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}