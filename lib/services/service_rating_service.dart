import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/service_rating.dart';
import 'api_config.dart';

class ServiceRatingException implements Exception {
  final String message;
  ServiceRatingException(this.message);

  @override
  String toString() => message;
}

class ServiceRatingService {
  /// Overall rating of every service, via GET /api/services/ratings. Every
  /// service is listed, including ones nobody has rated yet.
  static Future<List<ServiceRating>> getServiceRatings(String accessToken) async {
    http.Response response;
    try {
      response = await http
          .get(
        Uri.parse('$apiBaseUrl/api/services/ratings'),
        headers: {'Authorization': 'Bearer $accessToken'},
      )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ServiceRatingException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ServiceRatingException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode == 401) {
      throw ServiceRatingException('Your session has expired. Please log in again.');
    }
    if (response.statusCode != 200) {
      throw ServiceRatingException('Failed to load service ratings.');
    }

    try {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data.map((e) => ServiceRating.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      throw ServiceRatingException('Unexpected response from server.');
    }
  }
}
