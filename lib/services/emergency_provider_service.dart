import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/emergency_provider.dart';
import 'api_config.dart';

class EmergencyProviderServiceException implements Exception {
  final String message;
  EmergencyProviderServiceException(this.message);

  @override
  String toString() => message;
}

class EmergencyProviderService {
  static const String _baseUrl = '$apiBaseUrl/api/providers';

  static Future<List<EmergencyProvider>> findNearby({
    required String accessToken,
    required String serviceCategory,
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    final uri = Uri.parse('$_baseUrl/emergency/available').replace(
      queryParameters: {
        'service_category': serviceCategory,
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'radius_km': radiusKm.toString(),
      },
    );

    try {
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        throw EmergencyProviderServiceException('Your session has expired. Please log in again.');
      }
      if (response.statusCode != 200) {
        throw EmergencyProviderServiceException(_extractDetail(response) ?? 'Could not find available providers.');
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => EmergencyProvider.fromJson(item as Map<String, dynamic>))
          .toList();
    } on EmergencyProviderServiceException {
      rethrow;
    } on TimeoutException {
      throw EmergencyProviderServiceException('Request timed out. Please try again.');
    } catch (_) {
      throw EmergencyProviderServiceException('Unable to reach the server. Please check your connection.');
    }
  }

  static String? _extractDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // Keep the generic message.
    }
    return null;
  }
}
