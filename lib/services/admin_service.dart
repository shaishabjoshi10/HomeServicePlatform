import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/admin_models.dart';
import 'api_config.dart';

class AdminServiceException implements Exception {
  final String message;
  AdminServiceException(this.message);

  @override
  String toString() => message;
}

class AdminLoginResult {
  final String accessToken;
  final AdminAccount admin;
  AdminLoginResult({required this.accessToken, required this.admin});
}

/// All calls to the `/api/admin/...` backend. Mirrors the shape of
/// BookingService/AuthService (same `_send`/error-extraction pattern), kept
/// as its own class — rather than folded into AuthService — since an admin
/// session is a completely separate credential/token from a customer or
/// provider one; nothing here is ever called with a customer/provider
/// access token, or vice versa.
class AdminService {
  static const String _baseUrl = '$apiBaseUrl/api/admin';

  static Map<String, String> _authHeaders(String accessToken) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $accessToken',
  };

  static Future<AdminLoginResult> login({required String email, required String password}) async {
    final response = await _send(() => http.post(
      Uri.parse('$_baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    ));

    _checkStatus(response, expected: 200);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AdminLoginResult(
      accessToken: data['access_token'] as String,
      admin: AdminAccount.fromJson(data['admin'] as Map<String, dynamic>),
    );
  }

  static Future<AdminStats> getStats({required String accessToken}) async {
    final response = await _send(() => http.get(
      Uri.parse('$_baseUrl/stats'),
      headers: _authHeaders(accessToken),
    ));

    _checkStatus(response, expected: 200);
    return AdminStats.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<List<AdminCustomer>> getCustomers({required String accessToken, String? query}) async {
    final uri = Uri.parse('$_baseUrl/customers').replace(
      queryParameters: (query != null && query.trim().isNotEmpty) ? {'q': query.trim()} : null,
    );

    final response = await _send(() => http.get(uri, headers: _authHeaders(accessToken)));

    _checkStatus(response, expected: 200);
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => AdminCustomer.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// [verificationStatus], if given, must be 'pending' | 'verified' | 'rejected'.
  static Future<List<AdminProvider>> getProviders({
    required String accessToken,
    String? query,
    String? verificationStatus,
  }) async {
    final uri = Uri.parse('$_baseUrl/providers').replace(
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (verificationStatus != null) 'verification_status': verificationStatus,
      },
    );

    final response = await _send(() => http.get(uri, headers: _authHeaders(accessToken)));

    _checkStatus(response, expected: 200);
    final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => AdminProvider.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<AdminProviderDetail> getProviderDetail({
    required String accessToken,
    required String providerId,
  }) async {
    final response = await _send(() => http.get(
      Uri.parse('$_baseUrl/providers/$providerId'),
      headers: _authHeaders(accessToken),
    ));

    _checkStatus(response, expected: 200);
    return AdminProviderDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// [status] must be 'verified' or 'rejected' — the server rejects
  /// anything else (there's no admin action that sets a provider back to
  /// 'pending'; that only happens naturally when they re-upload a document).
  static Future<AdminProviderDetail> updateProviderVerification({
    required String accessToken,
    required String providerId,
    required String status,
  }) async {
    final response = await _send(() => http.patch(
      Uri.parse('$_baseUrl/providers/$providerId/verification'),
      headers: _authHeaders(accessToken),
      body: jsonEncode({'status': status}),
    ));

    _checkStatus(response, expected: 200);
    return AdminProviderDetail.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw AdminServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw AdminServiceException('Unable to reach the server. Please check your connection.');
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
    throw AdminServiceException(message);
  }
}
