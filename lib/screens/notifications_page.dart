import 'package:flutter/material.dart';

import '../main.dart';
import '../services/notification_service.dart';

/// Notification history for both customers and providers (the backend
/// returns only the signed-in user's notifications).
class NotificationsPage extends StatefulWidget {
  final String accessToken;

  const NotificationsPage({super.key, required this.accessToken});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification> _items = [];
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
      final items = await NotificationService.getNotifications(widget.accessToken);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      // Everything on screen counts as seen. The list keeps its unread
      // highlighting for this visit because _items was loaded before this.
      if (items.any((n) => !n.isRead)) {
        NotificationService.markAllRead(widget.accessToken);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load notifications.';
        _loading = false;
      });
    }
  }

  String _formatTime(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.hour >= 12 ? 'PM' : 'AM';
    return '${t.day} ${months[t.month - 1]}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryGreen,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimaryGreen));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(child: Text('No notifications yet'));
    }

    return RefreshIndicator(
      color: kPrimaryGreen,
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final n = _items[index];
          return Container(
            color: n.isRead ? null : kLightGreenBg,
            child: ListTile(
              leading: Icon(
                n.isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                color: kPrimaryGreen,
              ),
              title: Text(
                n.title,
                style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${n.message}\n${_formatTime(n.createdAt)}'),
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
