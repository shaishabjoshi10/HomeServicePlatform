import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/booking.dart';
import '../models/service_job.dart';
import '../services/booking_service.dart';
import '../services/payment_service.dart';
import 'esewa_payment_page.dart';
import 'booking_timeline.dart';
import 'booking_detail_widgets.dart';
import 'customer_navigation_map.dart';

/// Full detail view for one of the customer's own bookings, organized into
/// three clearly labeled sections — Booking Status (the status timeline and
/// live tracking map), Booking Information (address, date/time, problem
/// description, notes, and when the request was made), and Payment Summary
/// (price, charges, total and payment status) — with "Rate Service"
/// (or, while still pending, "Cancel Booking") pinned to the bottom as the
/// page's one primary action.
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

  Future<void> _payWithEsewa() async {
    if (_booking.totalAmount == null || _booking.paymentStatus == 'paid') return;
    try {
      final payment = await PaymentService.initiate(
        accessToken: widget.accessToken,
        bookingId: _booking.id,
      );
      if (!mounted) return;
      final updated = await Navigator.push<Booking>(
        context,
        MaterialPageRoute(
          builder: (_) => EsewaPaymentPage(
            accessToken: widget.accessToken,
            payment: payment,
          ),
        ),
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() => _booking = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment verified successfully.'), backgroundColor: kPrimaryGreen),
        );
      } else {
        final refreshed = await BookingService.getBooking(
          accessToken: widget.accessToken,
          bookingId: _booking.id,
        );
        if (mounted) setState(() => _booking = refreshed);
      }
    } on PaymentServiceException catch (e) {
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
    final showStatusSection = b.status != 'rejected' && b.status != 'cancelled';
    final showLiveMap =
        (b.status == 'on_the_way' || b.status == 'arrived') && b.latitude != null && b.longitude != null;
    final showPayButton =
        b.hasPrice && b.paymentStatus != 'paid' && b.status != 'rejected' && b.status != 'cancelled' && b.status != 'pending';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Booking Details'),
        backgroundColor: Colors.white,
        foregroundColor: kDarkText,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
            const SizedBox(height: 16),
            // The status timeline and, once the provider sets out, their
            // live location — grouped together since both are about where
            // this booking currently stands.
            if (showStatusSection) ...[
              BookingSectionCard(
                title: 'Booking Status',
                icon: Icons.checklist_rtl_rounded,
                child: Column(
                  children: [
                    BookingTimeline(status: b.status),
                    // The provider's live location: appears the moment they
                    // tap "I'm on my way" (status polling above is what
                    // notices that without the customer having to refresh)
                    // and disappears again — along with the route and the
                    // "waiting" placeholder it shows before the first GPS fix
                    // arrives — the instant the job is marked completed,
                    // since this block then simply stops being part of the
                    // tree.
                    if (showLiveMap) ...[
                      const SizedBox(height: 16),
                      CustomerNavigationMap(
                        key: ValueKey(b.id),
                        customerLatitude: b.latitude!,
                        customerLongitude: b.longitude!,
                        providerLatitude: b.providerLatitude,
                        providerLongitude: b.providerLongitude,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            BookingSectionCard(
              title: 'Booking Information',
              icon: Icons.info_outline_rounded,
              child: Column(
                children: [
                  AddressInfoRow(booking: b),
                  if (b.preferredDate != null)
                    BookingDetailRow(
                      icon: Icons.event_outlined,
                      label: 'Date & Time',
                      value: '${_formatDate(b.preferredDate!)}'
                          ' · ${TimeOfDay.fromDateTime(b.preferredDate!).format(context)}',
                    ),
                  if (b.problemDescription != null && b.problemDescription!.isNotEmpty)
                    BookingDetailRow(
                      icon: Icons.report_problem_outlined,
                      label: 'Problem Description',
                      value: b.problemDescription!,
                    ),
                  if (b.notes != null && b.notes!.isNotEmpty)
                    BookingDetailRow(icon: Icons.notes_rounded, label: 'Notes', value: b.notes!),
                  BookingDetailRow(
                    icon: Icons.access_time_rounded,
                    label: 'Requested On',
                    value: _formatDate(b.createdAt),
                    isLast: true,
                  ),
                ],
              ),
            ),
            // The price agreed when this booking was placed, any extra
            // charges, the resulting total, and whether it's been paid.
            // It's a snapshot taken server-side, so it keeps showing what
            // the customer actually booked at even if the job is repriced
            // later.
            if (b.hasPrice) ...[
              const SizedBox(height: 14),
              BookingSectionCard(
                title: 'Payment Summary',
                icon: Icons.receipt_long_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PaymentSummaryRow(
                      label: b.priceType == PriceType.startingFrom ? 'Price (starting from)' : 'Price',
                      value: b.priceLabel!,
                      note: b.priceType == PriceType.startingFrom ? 'Final price depends on the work needed' : null,
                    ),
                    PaymentSummaryRow(
                      label: 'Additional charges',
                      value: 'Rs. ${b.extraCharges.toStringAsFixed(2)}',
                      note: b.extraCharges > 0 ? b.extraChargeNote : null,
                    ),
                    const Divider(height: 22),
                    PaymentSummaryRow(
                      label: 'Total Amount',
                      value: 'Rs. ${(b.totalAmount ?? ((b.price ?? 0) + b.extraCharges)).toStringAsFixed(2)}',
                      emphasize: true,
                      isLast: true,
                    ),
                    const SizedBox(height: 14),
                    PaymentStatusBadge(booking: b),
                    if (showPayButton) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _payWithEsewa,
                          style: FilledButton.styleFrom(
                            backgroundColor: kPrimaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                          label: Text(
                            'Pay with eSewa · Rs. ${(b.totalAmount ?? ((b.price ?? 0) + b.extraCharges)).toStringAsFixed(2)}',
                          ),
                        ),
                      ),
                      if (b.paymentStatus == 'failed' || b.paymentStatus == 'cancelled')
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            b.paymentStatus == 'cancelled'
                                ? 'Payment was cancelled. You can try again.'
                                : 'Payment failed. You can try again.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
            if (b.ratingStars != null) ...[
              const SizedBox(height: 14),
              BookingSectionCard(
                title: 'Your Rating',
                icon: Icons.star_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        Text('${b.ratingStars}/5', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                      ],
                    ),
                    if (b.ratingComment != null && b.ratingComment!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('"${b.ratingComment}"',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      // The page's one primary action, pinned to the bottom rather than
      // buried at the end of the scroll: "Cancel Booking" while the request
      // is still pending, or "Rate Service" once it's completed and not yet
      // rated. Neither applies in between (accepted / on the way / arrived)
      // or once already rated, so the bar simply isn't shown then.
      bottomNavigationBar: b.status == 'pending'
          ? _BottomActionBar(
        child: OutlinedButton(
          onPressed: _cancelBooking,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade600,
            side: BorderSide(color: Colors.red.shade200),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Cancel Booking'),
        ),
      )
          : b.canBeRated
          ? _BottomActionBar(
        child: FilledButton.icon(
          onPressed: _rateBooking,
          style: FilledButton.styleFrom(
            backgroundColor: kPrimaryGreen,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.star_outline_rounded, size: 18),
          label: const Text('Rate Service'),
        ),
      )
          : null,
    );
  }
}

/// Thin white footer bar holding this page's one primary action, with a
/// hairline top border to separate it from the scrolling content above.
class _BottomActionBar extends StatelessWidget {
  final Widget child;
  const _BottomActionBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SizedBox(width: double.infinity, child: child),
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