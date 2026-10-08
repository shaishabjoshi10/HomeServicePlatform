import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/booking.dart';
import 'api_config.dart';

class PaymentServiceException implements Exception {
  final String message;
  PaymentServiceException(this.message);
  @override
  String toString() => message;
}

class EsewaPaymentInit {
  final String bookingId;
  final String transactionUuid;
  final double amount;
  final double extraCharges;
  final double totalAmount;
  final String formUrl;
  final Map<String, String> fields;

  EsewaPaymentInit({
    required this.bookingId,
    required this.transactionUuid,
    required this.amount,
    required this.extraCharges,
    required this.totalAmount,
    required this.formUrl,
    required this.fields,
  });

  factory EsewaPaymentInit.fromJson(Map<String, dynamic> json) => EsewaPaymentInit(
    bookingId: json['booking_id'].toString(),
    transactionUuid: json['transaction_uuid'] as String,
    amount: (json['amount'] as num).toDouble(),
    extraCharges: (json['extra_charges'] as num).toDouble(),
    totalAmount: (json['total_amount'] as num).toDouble(),
    formUrl: json['form_url'] as String,
    fields: (json['fields'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, value.toString()),
    ),
  );
}

class PaymentService {
  static String _base(String bookingId) => '$apiBaseUrl/api/bookings/$bookingId/payment/esewa';

  static Map<String, String> _headers(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  static Future<EsewaPaymentInit> initiate({
    required String accessToken,
    required String bookingId,
  }) async {
    final response = await _send(() => http.post(
      Uri.parse('${_base(bookingId)}/initiate'),
      headers: _headers(accessToken),
    ));
    _check(response, 200);
    return EsewaPaymentInit.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<Booking> verify({
    required String accessToken,
    required String bookingId,
    required String data,
  }) async {
    // Verification asks eSewa's server to confirm the payment, which can take
    // longer than an ordinary API call, so give it more time before the app
    // gives up (the server still finishes the check either way).
    final response = await _send(
          () => http.post(
        Uri.parse('${_base(bookingId)}/verify'),
        headers: _headers(accessToken),
        body: jsonEncode({'data': data}),
      ),
      timeout: const Duration(seconds: 40),
    );
    _check(response, 200);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<Booking> cancel({
    required String accessToken,
    required String bookingId,
  }) async {
    final response = await _send(() => http.post(
      Uri.parse('${_base(bookingId)}/cancel'),
      headers: _headers(accessToken),
    ));
    _check(response, 200);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<Booking> updateCharges({
    required String accessToken,
    required String bookingId,
    required double extraCharges,
    String? note,
  }) async {
    final response = await _send(() => http.patch(
      Uri.parse('$apiBaseUrl/api/bookings/$bookingId/charges'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'extra_charges': extraCharges,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    ));
    _check(response, 200);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Provider confirms the customer paid them in cash. The booking comes back
  /// marked paid, so it can then be completed.
  static Future<Booking> markCashReceived({
    required String accessToken,
    required String bookingId,
  }) async {
    final response = await _send(() => http.post(
      Uri.parse('$apiBaseUrl/api/bookings/$bookingId/payment/cash/received'),
      headers: _headers(accessToken),
    ));
    _check(response, 200);
    return Booking.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _send(
      Future<http.Response> Function() request, {
        Duration timeout = const Duration(seconds: 20),
      }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw PaymentServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw PaymentServiceException('Unable to reach the server. Please check your connection.');
    }
  }

  static void _check(http.Response response, int expected) {
    if (response.statusCode == expected) return;
    String message = 'Something went wrong with the payment.';
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['detail'] is String) message = data['detail'] as String;
    } catch (_) {}
    throw PaymentServiceException(message);
  }
}