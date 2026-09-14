import 'package:flutter/material.dart';

import '../main.dart';

/// A vertical 5-step progress tracker showing where a booking stands:
/// request sent -> accepted -> provider on the way -> arrived -> completed.
/// Driven entirely by [status], which reflects the provider's own actions
/// (accept, "on my way", "arrived", "mark completed") — so it advances
/// automatically the next time the booking is reloaded, with no separate
/// tracking needed here. Not meant to be shown for 'rejected' or
/// 'cancelled' bookings, where this happy-path sequence doesn't apply —
/// callers should check that before including it.
class BookingTimeline extends StatelessWidget {
  final String status;
  const BookingTimeline({super.key, required this.status});

  static const List<String> _order = ['pending', 'accepted', 'on_the_way', 'arrived', 'completed'];

  static const List<(String, String?)> _steps = [
    ('Booking Request Sent', null),
    ('Booking Accepted', null),
    ('Service Provider On the Way', 'Service provider will arrive soon'),
    ('Service Provider Arrived', null),
    ('Work Completed', null),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _order.indexOf(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_steps.length, (i) {
        final (label, subtitle) = _steps[i];
        final done = currentIndex >= 0 && i <= currentIndex;
        final isCurrent = i == currentIndex;
        final isLast = i == _steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 18,
                      color: done ? kPrimaryGreen : Colors.grey.shade300,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: i < currentIndex ? kPrimaryGreen : Colors.grey.shade300,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                          color: done ? kDarkText : Colors.grey.shade500,
                        ),
                      ),
                      if (isCurrent && subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
