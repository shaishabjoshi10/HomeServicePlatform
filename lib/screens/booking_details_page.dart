import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../models/service_job.dart';
import '../services/booking_service.dart';
import 'booking_timeline.dart';
import 'customer_navigation_map.dart';

/// Full detail view for one of the customer's own bookings — address,
/// notes, timestamps, the status timeline, and the cancel/rate actions.
/// The booking list only shows the basics and links here for everything
/// else. This page keeps its own local copy of the booking so cancel/rate
/// reflect immediately without waiting on the list to reload; the list
/// re-fetches from the server itself once the user navigates back, so it
/// always ends up showing the current state regardless.
///
/// It also polls the server for that same booking (see [_pollBooking])
/// from the moment it's accepted onward. There's no push channel from the
/// backend, so this is what makes the provider's live location — and the
/// status changes that turn it on and off — show up on this page in real
/// time without the customer having to leave and come back: the moment a
/// poll's status is no longer 'accepted' / 'on_the_way' / 'arrived',
/// [_shouldPoll] goes false and polling stops on its own.
class BookingDetailsPage extends StatefulWidget {
  final String accessToken;
  final Booking booking;

  const BookingDetailsPage({super.key, required this.accessToken, required this.booking});

  @override
  State<BookingDetailsPage> createState() => _BookingDetailsPageState();
}

class _BookingDetailsPageState extends State<BookingDetailsPage> {
  late Booking _booking;

  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 4);

  /// Whether the booking's status can still change on its own (via the
  /// provider's actions) in a way this page needs to reflect live — worth
  /// polling for. False for every terminal status (completed / rejected /
  /// cancelled) and for 'pending', where nothing to show here changes yet.
  bool get _shouldPoll =>
      _booking.status == 'accepted' || _booking.status == 'on_the_way' || _booking.status == 'arrived';

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
    if (_shouldPoll) _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollBooking());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollBooking() async {
    try {
      final updated = await BookingService.getBooking(accessToken: widget.accessToken, bookingId: _booking.id);
      if (!mounted) return;
      setState(() => _booking = updated);
      // Reached a terminal status since the last poll — nothing left that
      // can still change on its own, so stop asking the server.
      if (!_shouldPoll) _stopPolling();
    } catch (_) {
      // Best-effort: a missed poll just means we try again next tick.
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _cancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text('Cancel your ${_booking.serviceCategory ?? 'service'} booking request?'),
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
      builder: (dialogContext) => _RatingDialog(serviceName: _booking.serviceCategory),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.displayTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18, color: kDarkText)),
                      // The service category, once the headline is the
                      // specific job rather than the category itself.
                      if (b.jobTitle != null && b.serviceCategory != null) ...[
                        const SizedBox(height: 2),
                        Text(b.serviceCategory!,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
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
            // The provider's live location: appears the moment they tap
            // "I'm on my way" (status polling above is what notices that
            // without the customer having to refresh) and disappears again
            // — along with the route and the "waiting" placeholder it
            // shows before the first GPS fix arrives — the instant the job
            // is marked completed, since this block then simply stops
            // being part of the tree.
            if ((b.status == 'on_the_way' || b.status == 'arrived') && b.latitude != null && b.longitude != null) ...[
              const SizedBox(height: 20),
              CustomerNavigationMap(
                key: ValueKey(b.id),
                customerLatitude: b.latitude!,
                customerLongitude: b.longitude!,
                providerLatitude: b.providerLatitude,
                providerLongitude: b.providerLongitude,
              ),
            ],
            const SizedBox(height: 20),
            // The price agreed when this booking was placed. It's a snapshot
            // taken server-side, so it keeps showing what the customer
            // actually booked at even if the job is repriced later.
            if (b.hasPrice)
              _DetailRow(
                icon: Icons.payments_outlined,
                label: b.priceType == PriceType.startingFrom ? 'Price (starting from)' : 'Price',
                value: b.priceType == PriceType.startingFrom
                    ? '${b.priceLabel!} · final price depends on the work needed'
                    : b.priceLabel!,
              ),
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
                  Text('You rated this service ${b.ratingStars}/5',
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
  /// The service being rated (e.g. "Plumbing") — the rating is for the
  /// overall service, never for an individual provider.
  final String? serviceName;
  const _RatingDialog({required this.serviceName});

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
      title: Text(widget.serviceName != null ? 'Rate ${widget.serviceName} service' : 'Rate this service'),
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