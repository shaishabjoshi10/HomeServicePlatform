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

  /// serviceCategory, address/latitude/longitude, preferredDate, and
  /// problemDescription are all mandatory — the booking form only calls
  /// this once every one of them is filled with valid, non-blank
  /// information. notes is the only field that stays optional.
  ///
  /// jobTitle is the specific job picked under the service (e.g. "Fan
  /// Installation" under "Electrical"). It's optional because a category
  /// with no jobs listed books straight through at category level.
  ///
  /// The job's price is deliberately *not* sent: the server looks it up in
  /// its own catalogue and snapshots it onto the booking, so what the
  /// customer is charged can't be altered from the client.
  ///
  /// There is no provider argument: customers book a service and the
  /// server assigns a suitable provider itself.
  static Future<Booking> createBooking({
    required String accessToken,
    required String serviceCategory,
    String? jobTitle,
    required String address,
    required double latitude,
    required double longitude,
    required DateTime preferredDate,
    required String problemDescription,
    String? notes,
  }) async {
    final body = jsonEncode({
      'service_category': serviceCategory,
      if (jobTitle != null && jobTitle.isNotEmpty) 'job_title': jobTitle,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'preferred_date': preferredDate.toIso8601String(),
      'problem_description': problemDescription,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
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

  /// Rates the overall service for a completed booking (1-5 stars,
  /// optional comment) — a rating of the service, not of a provider. The backend
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