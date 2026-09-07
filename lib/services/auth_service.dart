import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Thrown for any login/signup failure with a message safe to show the user.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthUser {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;

  AuthUser({
    required this.id,
    required this.fullName,
    required this.role,
    this.email,
    this.phone,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'].toString(),
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String,
    );
  }
}

class AuthResult {
  final String accessToken;
  final AuthUser user;
  AuthResult({required this.accessToken, required this.user});
}

class AuthService {
  static const String _baseUrl = '$apiBaseUrl/api/auth';

  static Future<AuthResult> login({
    required String identifier,
    required String password,
    required String role,
  }) {
    return _post('/login', {
      'identifier': identifier.trim(),
      'password': password,
      'role': role,
    });
  }

  static Future<AuthResult> signup({
    required String fullName,
    required String identifier,
    required String password,
    required String role,
  }) {
    return _post('/signup', {
      'full_name': fullName.trim(),
      'identifier': identifier.trim(),
      'password': password,
      'role': role,
    });
  }

  static Future<AuthResult> _post(String path, Map<String, dynamic> body) async {
    late final http.Response response;

    try {
      response = await http
          .post(
        Uri.parse('$_baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw AuthException('Request timed out. Please check your connection.');
    } catch (_) {
      throw AuthException('Unable to reach the server. Please check your connection.');
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AuthException('Unexpected response from server.');
    }

    if (response.statusCode == 200 || response.statusCode == 201) {
      return AuthResult(
        accessToken: data['access_token'] as String,
        user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
    }

    throw AuthException(_extractErrorMessage(data));
  }

  /// FastAPI returns {"detail": "message"} for normal errors and
  /// {"detail": [{"msg": "...", ...}, ...]} for 422 validation errors.
  static String _extractErrorMessage(Map<String, dynamic> data) {
    final detail = data['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) {
        var msg = first['msg'].toString();
        // Pydantic prefixes custom validator errors with "Value error, "
        const prefix = 'Value error, ';
        if (msg.startsWith(prefix)) msg = msg.substring(prefix.length);
        return msg;
      }
    }
    return 'Something went wrong. Please try again.';
  }
}