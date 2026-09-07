import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/customer_profile.dart';
import 'api_config.dart';

class ProfileServiceException implements Exception {
  final String message;
  ProfileServiceException(this.message);

  @override
  String toString() => message;
}

class ProfileService {
  static const String _baseUrl = '$apiBaseUrl/api/profile';

  static Map<String, String> _authHeaders(String accessToken) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

  static Future<CustomerProfile> getMyProfile(String accessToken) async {
    final response = await _send(() => http.get(
          Uri.parse('$_baseUrl/me'),
          headers: _authHeaders(accessToken),
        ));
    _checkStatus(response, expected: 200);
    return CustomerProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Saves the customer's default address + coordinates, used to pre-fill
  /// the location field whenever they start a new booking.
  static Future<CustomerProfile> updateDefaultLocation({
    required String accessToken,
    required String address,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _send(() => http.put(
          Uri.parse('$_baseUrl/me'),
          headers: _authHeaders(accessToken),
          body: jsonEncode({
            'address': address,
            'latitude': latitude,
            'longitude': longitude,
          }),
        ));
    _checkStatus(response, expected: 200);
    return CustomerProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ProfileServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ProfileServiceException('Unable to reach the server. Please check your connection.');
    }
  }

  static void _checkStatus(http.Response response, {required int expected}) {
    if (response.statusCode == expected) return;
    String message = 'Something went wrong. Please try again.';
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is String) message = detail;
    } catch (_) {
      // keep default message
    }
    throw ProfileServiceException(message);
  }
}
