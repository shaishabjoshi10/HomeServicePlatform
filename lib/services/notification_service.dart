import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class AppNotification {
  final String id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      title: json['title'] as String,
      message: json['message'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

class NotificationService {
  static const String _baseUrl = '$apiBaseUrl/api/notifications';

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  /// The user's notification history, newest first.
  static Future<List<AppNotification>> getNotifications(String token) async {
    final response = await http.get(Uri.parse(_baseUrl), headers: _headers(token));
    if (response.statusCode != 200) {
      throw Exception('Could not load notifications.');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<int> getUnreadCount(String token) async {
    final response = await http.get(Uri.parse('$_baseUrl/unread-count'), headers: _headers(token));
    if (response.statusCode != 200) return 0;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['unread_count'] as num?)?.toInt() ?? 0;
  }

  static Future<void> markAllRead(String token) async {
    await http.post(Uri.parse('$_baseUrl/read-all'), headers: _headers(token));
  }
}
