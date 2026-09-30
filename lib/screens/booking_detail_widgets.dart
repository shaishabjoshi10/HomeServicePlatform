import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/booking.dart';

/// A titled, bordered card used to group related content on the booking
/// details pages (customer and provider) into clearly labeled sections —
/// "Booking Status", "Payment Summary", "Booking Information" — instead of
/// one long undifferentiated list of rows.
class BookingSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const BookingSectionCard({super.key, required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: kPrimaryGreen),
              const SizedBox(width: 7),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// A label/value line for the "Payment Summary" section, laid out like a
/// receipt row. [emphasize] is used once, for the total, so it stands out
/// clearly from the price and charge lines above it.
class PaymentSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final bool emphasize;
  final bool isLast;

  const PaymentSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.emphasize = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasize ? 15 : 13.5,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: emphasize ? kDarkText : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: emphasize ? 17 : 14,
                  fontWeight: FontWeight.w700,
                  color: emphasize ? kPrimaryGreen : kDarkText,
                ),
              ),
              if (note != null && note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    note!,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small colored badge showing whether payment has gone through —
/// "Paid" (with the reference, if any) in green, or "Awaiting Payment" in
/// orange — reused wherever the booking's payment status needs to be
/// unambiguous at a glance.
class PaymentStatusBadge extends StatelessWidget {
  final Booking booking;

  const PaymentStatusBadge({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final paid = booking.paymentStatus == 'paid';
    final color = paid ? Colors.green.shade700 : Colors.orange.shade800;
    final background = paid ? Colors.green.shade50 : Colors.orange.shade50;
    final border = paid ? Colors.green.shade200 : Colors.orange.shade200;
    final label = paid
        ? 'Paid${booking.paymentReference != null ? ' · Ref ${booking.paymentReference}' : ''}'
        : switch (booking.paymentStatus) {
            'failed' => 'Payment Failed',
            'cancelled' => 'Payment Cancelled',
            'pending' => 'Payment Pending',
            _ => 'Awaiting Payment',
          };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(paid ? Icons.verified_rounded : Icons.schedule_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}

/// A compact icon + label/value row used throughout the "Booking
/// Information" section (date & time, problem description, notes, etc).
class BookingDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const BookingDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
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

/// Address row for the "Booking Information" section. Some addresses here
/// run 4+ lines once wrapped (a full ward/municipality breakdown), which
/// used to dominate the page — this clips the text to two lines and adds
/// a "View Map" action underneath that opens [showBookingLocationMap]
/// instead, so the full address is a tap away rather than always on screen.
class AddressInfoRow extends StatelessWidget {
  final Booking booking;
  final bool isLast;

  const AddressInfoRow({super.key, required this.booking, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final hasCoordinates = booking.latitude != null && booking.longitude != null;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 18, color: kPrimaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Address', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(
                  booking.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (hasCoordinates) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => showBookingLocationMap(
                      context,
                      address: booking.address,
                      latitude: booking.latitude!,
                      longitude: booking.longitude!,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 14, color: kPrimaryGreen),
                        const SizedBox(width: 4),
                        Text(
                          'View Map',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPrimaryGreen),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a read-only preview of where the booking's address sits on the
/// map: a pin and the full address text, nothing more. This is separate
/// from the live-tracking maps ([CustomerNavigationMap] /
/// [ProviderNavigationMap]) shown elsewhere on these pages — it's just
/// enough to place the job, on demand, via the "View Map" action next to
/// the (possibly long) address.
void showBookingLocationMap(
  BuildContext context, {
  required String address,
  required double latitude,
  required double longitude,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Booking Location', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kDarkText)),
            const SizedBox(height: 4),
            Text(address, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 260,
                child: FlutterMap(
                  options: MapOptions(initialCenter: LatLng(latitude, longitude), initialZoom: 15),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.gharsewa.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(latitude, longitude),
                          width: 40,
                          height: 40,
                          child: Icon(Icons.location_on_rounded, color: kPrimaryGreen, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
