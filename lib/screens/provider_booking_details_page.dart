import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';
import '../models/service_job.dart';
import '../services/booking_service.dart';
import '../services/payment_service.dart';
import 'booking_timeline.dart';
import 'provider_navigation_map.dart';

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

  /// Whether an admin has verified the *current provider's own* account —
  /// not anything about this booking. Passed in by the caller (which
  /// already has the provider's profile loaded) rather than fetched here,
  /// so this page doesn't need its own extra network round-trip just to
  /// know whether to let the Accept button through. See
  /// ProviderProfile.isVerified for where that value comes from.
  final bool isVerified;

  const ProviderBookingDetailsPage({
    super.key,
    required this.accessToken,
    required this.booking,
    required this.isVerified,
  });

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

  Future<void> _editCharges() async {
    final amountController = TextEditingController(
      text: _booking.extraCharges > 0 ? _booking.extraCharges.toStringAsFixed(2) : '',
    );
    final noteController = TextEditingController(text: _booking.extraChargeNote ?? '');
    final result = await showDialog<(double, String?)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Additional charges'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Extra charge (Rs.)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Reason / note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a valid non-negative amount.')),
                );
                return;
              }
              Navigator.pop(dialogContext, (amount, noteController.text.trim().isEmpty ? null : noteController.text.trim()));
            },
            style: FilledButton.styleFrom(backgroundColor: kPrimaryGreen),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's closing animation has finished; disposing
    // immediately leaves the dialog's TextFields listening to dead controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      amountController.dispose();
      noteController.dispose();
    });
    if (result == null) return;

    setState(() => _updating = true);
    try {
      final updated = await PaymentService.updateCharges(
        accessToken: widget.accessToken,
        bookingId: _booking.id,
        extraCharges: result.$1,
        note: result.$2,
      );
      if (mounted) setState(() => _booking = updated);
    } on PaymentServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade600),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
            // The job, then the service it sits under — so the provider sees
            // what the work actually is ("Fan Installation") before the
            // broader category.
            if (b.jobTitle != null || b.serviceCategory != null) ...[
              const SizedBox(height: 4),
              Text(
                b.jobTitle != null && b.serviceCategory != null
                    ? '${b.jobTitle} · ${b.serviceCategory}'
                    : b.displayTitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
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
            // The navigation map: the customer's pin shows as soon as the
            // job is accepted; the provider's own live position and the
            // route between the two join it once they're on the way, and
            // both disappear again the moment the job is marked completed
            // (this whole block simply stops being included in the tree,
            // which is what tears the map's State — and its GPS stream —
            // down; see ProviderNavigationMap).
            if ((b.status == 'accepted' || b.status == 'on_the_way' || b.status == 'arrived') &&
                b.latitude != null &&
                b.longitude != null) ...[
              const SizedBox(height: 20),
              ProviderNavigationMap(
                key: ValueKey(b.id),
                accessToken: widget.accessToken,
                bookingId: b.id,
                status: b.status,
                customerLatitude: b.latitude!,
                customerLongitude: b.longitude!,
                customerAddress: b.address,
              ),
            ],
            const SizedBox(height: 20),
            if (b.customerPhone != null && b.customerPhone!.isNotEmpty)
              _DetailRow(icon: Icons.phone_outlined, label: 'Phone', value: b.customerPhone!),
            // What this job was booked at. The provider sees the same
            // figure the customer agreed to, so there's no discrepancy to
            // argue about on the doorstep.
            if (b.hasPrice)
              _DetailRow(
                icon: Icons.payments_outlined,
                label: b.priceType == PriceType.startingFrom ? 'Price (starting from)' : 'Price',
                value: b.priceType == PriceType.startingFrom
                    ? '${b.priceLabel!} · final price depends on the work needed'
                    : b.priceLabel!,
              ),
            if (b.hasPrice) ...[
              _DetailRow(
                icon: Icons.add_card_outlined,
                label: 'Additional charges',
                value: b.extraCharges > 0
                    ? 'Rs. ${b.extraCharges.toStringAsFixed(2)}${b.extraChargeNote != null ? ' · ${b.extraChargeNote}' : ''}'
                    : 'None',
              ),
              _DetailRow(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Customer total',
                value: 'Rs. ${(b.totalAmount ?? ((b.price ?? 0) + b.extraCharges)).toStringAsFixed(2)}',
              ),
            ],
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
              // An unverified provider can still decline a request (that
              // just gives it up, no harm done) but can't accept one — an
              // admin has to verify their account first. This mirrors the
              // 403 the backend itself would return if this button were
              // somehow bypassed (see update_booking_status).
              if (!widget.isVerified) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pending Verification',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange.shade900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "You can't accept bookings until an admin verifies your account.",
                              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                  onPressed: (_updating || !widget.isVerified) ? null : () => _respond('accepted'),
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
            if ((b.status == 'accepted' || b.status == 'on_the_way' || b.status == 'arrived') &&
                b.paymentStatus != 'paid') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _updating ? null : _editCharges,
                  icon: const Icon(Icons.add_card_outlined, size: 18),
                  label: Text(b.extraCharges > 0 ? 'Update Additional Charges' : 'Add Additional Charges'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPrimaryGreen,
                    side: BorderSide(color: kPrimaryGreen.withValues(alpha: 0.45)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
                  onPressed: (b.paymentStatus == 'paid' && !_updating) ? () => _respond('completed') : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(b.paymentStatus == 'paid' ? 'Mark as Completed' : 'Waiting for Customer Payment'),
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