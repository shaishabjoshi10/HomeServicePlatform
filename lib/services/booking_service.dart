import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/booking.dart';
import 'api_config.dart';

class BookingServiceException implements Exception {
  final String message;
  BookingServiceException(this.message);

  @override
  String toString() => message;
}

class BookingService {
  static const String _baseUrl = '$apiBaseUrl/api/bookings';

  static Map<String, String> _authHeaders(String accessToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
  };

  static Future<Booking> createBooking({
    required String accessToken,
    required String providerId,
    required String address,
    double? latitude,
    double? longitude,
    String? serviceCategory,
    String? notes,
    DateTime? preferredDate,
  }) async {
    final body = jsonEncode({
      'provider_id': providerId,
      'address': address,
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (serviceCategory != null && serviceCategory.isNotEmpty) 'service_category': serviceCategory,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (preferredDate != null) 'preferred_date': preferredDate.toIso8601String(),
    });

    final response = await _send(() => http.post(
      Uri.parse(_baseUrl),
      headers: _authHeaders(accessToken),
      body: body,
    ));

    _checkStatus(response, expected: 201);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<Booking>> getMyBookings({
    required String accessToken,
    String? status,
  }) async {
    final uri = Uri.parse('$_baseUrl/me').replace(
      queryParameters: status != null ? {'status': status} : null,
    );

    final response = await _send(() => http.get(uri, headers: _authHeaders(accessToken)));

    _checkStatus(response, expected: 200);
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => Booking.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Booking> updateStatus({
    required String accessToken,
    required String bookingId,
    required String status,
  }) async {
    final response = await _send(() => http.patch(
      Uri.parse('$_baseUrl/$bookingId/status'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'status': status}),
    ));

    _checkStatus(response, expected: 200);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Rates a completed booking (1-5 stars, optional comment). The backend
  /// rejects this if the booking isn't completed, isn't the caller's own,
  /// or has already been rated — surfaced as a [BookingServiceException].
  static Future<Booking> rateBooking({
    required String accessToken,
    required String bookingId,
    required int stars,
    String? comment,
  }) async {
    final response = await _send(() => http.post(
      Uri.parse('$_baseUrl/$bookingId/rating'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      }),
    ));

    _checkStatus(response, expected: 201);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw BookingServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw BookingServiceException('Unable to reach the server. Please check your connection.');
    }
  }

  static void _checkStatus(http.Response response, {required int expected}) {
    if (response.statusCode == expected) return;

    String message = 'Something went wrong. Please try again.';
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final messages = detail
            .map((e) => e is Map && e['msg'] is String ? e['msg'] as String : null)
            .whereType<String>()
            .toList();
        if (messages.isNotEmpty) message = messages.join(' ');
      }
    } catch (_) {
      // keep default message
    }
    throw BookingServiceException(message);
  }
}