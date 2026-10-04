import 'package:flutter/material.dart';

import '../screens/notifications_page.dart';
import '../services/notification_service.dart';

/// Bell button for the home-screen header with an unread badge.
/// The count is loaded when the screen opens and again after the user
/// comes back from the notifications page.
class NotificationBell extends StatefulWidget {
  final String accessToken;
  final double size;
  final double iconSize;

  const NotificationBell({
    super.key,
    required this.accessToken,
    this.size = 40,
    this.iconSize = 22,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final count = await NotificationService.getUnreadCount(widget.accessToken);
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      // The badge is optional; ignore network errors.
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsPage(accessToken: widget.accessToken),
      ),
    );
    _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      customBorder: const CircleBorder(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.notifications_none_rounded, size: widget.iconSize, color: Colors.white),
            if (_unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text(
                    _unread > 9 ? '9+' : '$_unread',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
