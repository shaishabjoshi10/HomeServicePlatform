import 'package:flutter/material.dart';

import '../main.dart';
import '../models/booking.dart';

/// Shows a bottom sheet with the full details of [booking]. Pass whichever
/// action callbacks make sense for its current status — e.g. only
/// [onAccept]/[onDecline] for a pending booking, only [onComplete] for an
/// accepted one. Any callback left null simply hides that button.
Future<void> showBookingDetailSheet(
  BuildContext context, {
  required Booking booking,
  VoidCallback? onAccept,
  VoidCallback? onDecline,
  VoidCallback? onComplete,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Booking Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kDarkText)),
                    _StatusBadge(status: booking.status),
                  ],
                ),
                const SizedBox(height: 20),
                _DetailRow(icon: Icons.person_outline_rounded, label: 'Customer', value: booking.customerName),
                if (booking.serviceCategory != null)
                  _DetailRow(icon: Icons.build_outlined, label: 'Service', value: booking.serviceCategory!),
                _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: booking.address),
                if (booking.preferredDate != null)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: 'Date & Time',
                    value: '${_formatDate(booking.preferredDate!)}'
                        ' · ${TimeOfDay.fromDateTime(booking.preferredDate!).format(sheetContext)}',
                  ),
                if (booking.notes != null && booking.notes!.isNotEmpty)
                  _DetailRow(icon: Icons.notes_rounded, label: 'Notes', value: booking.notes!),
                _DetailRow(icon: Icons.access_time_rounded, label: 'Requested On', value: _formatDate(booking.createdAt)),
                const SizedBox(height: 12),
                if (onAccept != null || onDecline != null)
                  Row(
                    children: [
                      if (onDecline != null)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              onDecline();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              side: BorderSide(color: Colors.red.shade200),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Decline'),
                          ),
                        ),
                      if (onDecline != null && onAccept != null) const SizedBox(width: 10),
                      if (onAccept != null)
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              onAccept();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: kPrimaryGreen,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Accept'),
                          ),
                        ),
                    ],
                  ),
                if (onComplete != null)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        onComplete();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimaryGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Mark as Completed'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  Color get _color {
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

  String get _label {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(_label, style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w600)),
    );
  }
}
