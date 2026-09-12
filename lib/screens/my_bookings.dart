import 'package:flutter/material.dart';
import '../main.dart';
import '../models/booking.dart';
import '../services/booking_service.dart';

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

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: Text('Cancel your booking request with ${booking.providerName}?'),
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
      await BookingService.updateStatus(
        accessToken: widget.accessToken,
        bookingId: booking.id,
        status: 'cancelled',
      );
      _load();
    } on BookingServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    }
  }

  Future<void> _rateBooking(Booking booking) async {
    final result = await showDialog<_RatingResult>(
      context: context,
      builder: (dialogContext) => _RatingDialog(providerName: booking.providerName),
    );

    if (result == null) return;

    try {
      final updated = await BookingService.rateBooking(
        accessToken: widget.accessToken,
        bookingId: booking.id,
        stars: result.stars,
        comment: result.comment,
      );
      if (!mounted) return;
      setState(() {
        final index = _bookings.indexWhere((b) => b.id == updated.id);
        if (index != -1) _bookings[index] = updated;
      });
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
      case 'completed':
        return Colors.blue.shade600;
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
            return Container(
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
                    ],
                  ),
                  if (b.serviceCategory != null) ...[
                    const SizedBox(height: 2),
                    Text(b.serviceCategory!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(b.address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ),
                    ],
                  ),
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
                  if (b.status == 'pending') ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _cancelBooking(b),
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                  if (b.canBeRated) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _rateBooking(b),
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: const Text('Rate Service'),
                      ),
                    ),
                  ] else if (b.ratingStars != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ...List.generate(
                          5,
                              (i) => Icon(
                            i < b.ratingStars! ? Icons.star_rounded : Icons.star_border_rounded,
                            size: 16,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('You rated this ${b.ratingStars}/5',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
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