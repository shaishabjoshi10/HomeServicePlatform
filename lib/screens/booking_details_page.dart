import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';
import 'booking_timeline.dart';

/// Full detail view for one of the customer's own bookings — address,
/// notes, timestamps, the status timeline, and the cancel/rate actions.
/// The booking list only shows the basics and links here for everything
/// else. This page keeps its own local copy of the booking so cancel/rate
/// reflect immediately without waiting on the list to reload; the list
/// re-fetches from the server itself once the user navigates back, so it
/// always ends up showing the current state regardless.
class BookingDetailsPage extends StatefulWidget {
  final String accessToken;
  final Booking booking;

  const BookingDetailsPage({super.key, required this.accessToken, required this.booking});

  @override
  State<BookingDetailsPage> createState() => _BookingDetailsPageState();
}

class _BookingDetailsPageState extends State<BookingDetailsPage> {
  late Booking _booking;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text('Cancel your booking request with ${_booking.providerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final updated = await BookingService.updateStatus(
        accessToken: widget.accessToken,
        bookingId: _booking.id,
        status: 'cancelled',
      );
      if (!mounted) return;
      setState(() => _booking = updated);
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    }
  }

  Future<void> _rateBooking() async {
    final result = await showDialog<_RatingResult>(
      context: context,
      builder: (dialogContext) => _RatingDialog(providerName: _booking.providerName),
    );

    if (result == null) return;

    try {
      final updated = await BookingService.rateBooking(
        accessToken: widget.accessToken,
        bookingId: _booking.id,
        stars: result.stars,
        comment: result.comment,
      );
      if (!mounted) return;
      setState(() => _booking = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for your rating!'), backgroundColor: kPrimaryGreen),
      );
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
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
                  child: Text(b.providerName,
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
            _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: b.address),
            if (b.preferredDate != null)
              _DetailRow(
                icon: Icons.event_outlined,
                label: 'Date & Time',
                value: '${_formatDate(b.preferredDate!)}'
                    ' · ${TimeOfDay.fromDateTime(b.preferredDate!).format(context)}',
              ),
            if (b.notes != null && b.notes!.isNotEmpty)
              _DetailRow(icon: Icons.notes_rounded, label: 'Notes', value: b.notes!),
            _DetailRow(icon: Icons.access_time_rounded, label: 'Requested On', value: _formatDate(b.createdAt)),
            if (b.status == 'pending') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _cancelBooking,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel Booking'),
                ),
              ),
            ],
            if (b.canBeRated) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _rateBooking,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('Rate Service'),
                ),
              ),
            ] else if (b.ratingStars != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < b.ratingStars! ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('You rated this ${b.ratingStars}/5',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
              if (b.ratingComment != null && b.ratingComment!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('"${b.ratingComment}"',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
              ],
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

class _RatingResult {
  final int stars;
  final String? comment;
  _RatingResult(this.stars, this.comment);
}

class _RatingDialog extends StatefulWidget {
  final String providerName;
  const _RatingDialog({required this.providerName});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  int _stars = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.providerName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _stars;
              return IconButton(
                onPressed: () => setState(() => _stars = i + 1),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Add a comment (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _stars == 0
              ? null
              : () => Navigator.pop(
                    context,
                    _RatingResult(
                      _stars,
                      _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
                    ),
                  ),
          style: FilledButton.styleFrom(backgroundColor: kPrimaryGreen),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
