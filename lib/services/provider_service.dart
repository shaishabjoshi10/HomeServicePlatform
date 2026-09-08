import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/provider_profile.dart';
import 'api_config.dart';

/// Dropdown option lists for the provider verification form, fetched from
/// GET /api/profile/form-options so the app and server stay in sync.
class ProfileFormOptions {
  final List<String> serviceCategories;
  final List<String> cities;
  final Map<String, List<String>> municipalitiesByCity;
  final List<String> experienceRanges;
  final List<String> maritalStatuses;

  const ProfileFormOptions({
    required this.serviceCategories,
    required this.cities,
    required this.municipalitiesByCity,
    required this.experienceRanges,
    required this.maritalStatuses,
  });

  /// Municipalities for the given city, or an empty list if none/unknown.
  List<String> municipalitiesFor(String? city) {
    if (city == null) return const [];
    return municipalitiesByCity[city] ?? const [];
  }

  factory ProfileFormOptions.fromJson(Map<String, dynamic> json) {
    List<String> asList(dynamic v) => (v as List<dynamic>).map((e) => e.toString()).toList();
    final rawMap = json['municipalities_by_city'] as Map<String, dynamic>;
    return ProfileFormOptions(
      serviceCategories: asList(json['service_categories']),
      cities: asList(json['cities']),
      municipalitiesByCity: rawMap.map((city, list) => MapEntry(city, asList(list))),
      experienceRanges: asList(json['experience_ranges']),
      maritalStatuses: asList(json['marital_statuses']),
    );
  }

  /// Used if the form-options endpoint can't be reached, so the form is
  /// still usable (categories in particular matter for validation).
  static const fallback = ProfileFormOptions(
    serviceCategories: [
      'Plumbing',
      'Electrical',
      'Cleaning',
      'Carpentry',
      'Painting',
      'Appliance Repair',
      'Pest Control',
      'Gardening',
      'Moving & Packing',
    ],
    cities: ['Kathmandu', 'Lalitpur', 'Bhaktapur', 'Kirtipur'],
    municipalitiesByCity: {
      'Kathmandu': ['Kathmandu Metropolitan City', 'Chandragiri Municipality', 'Tokha Municipality'],
      'Lalitpur': ['Lalitpur Metropolitan City', 'Godawari Municipality', 'Mahalaxmi Municipality'],
      'Bhaktapur': ['Bhaktapur Municipality', 'Madhyapur Thimi Municipality', 'Suryabinayak Municipality'],
      'Kirtipur': ['Kirtipur Municipality'],
    },
    experienceRanges: ['Less than 1 year', '1-3 years', '3-5 years', '5-10 years', '10+ years'],
    maritalStatuses: ['single', 'married'],
  );
}

class ProviderServiceException implements Exception {
  final String message;
  ProviderServiceException(this.message);

  @override
  String toString() => message;
}

class ProviderService {
  static const String _baseUrl = '$apiBaseUrl/api/providers';

  /// Predefined service categories shown in the provider signup dropdown.
  /// Falls back to a local list if the server call fails, so signup still
  /// works even if this one endpoint is briefly unreachable.
  static Future<List<String>> getCategories() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/categories')).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // fall through to local fallback
    }
    return const [
      'Plumbing',
      'Electrical',
      'Cleaning',
      'Carpentry',
      'Painting',
      'Appliance Repair',
      'Pest Control',
      'Gardening',
      'Moving & Packing',
    ];
  }

  /// Dropdown option lists for the "Complete Your Profile" verification
  /// form. Falls back to a local copy if the server call fails.
  static Future<ProfileFormOptions> getFormOptions() async {
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/api/profile/form-options'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return ProfileFormOptions.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {
      // fall through to local fallback
    }
    return ProfileFormOptions.fallback;
  }

  static Future<List<ProviderProfile>> listProviders({
    String? serviceCategory,
    bool availableOnly = false,
    bool verifiedOnly = false,
    int limit = 50,
  }) async {
    final queryParams = <String, String>{
      if (serviceCategory != null && serviceCategory.isNotEmpty) 'service_category': serviceCategory,
      if (availableOnly) 'available_only': 'true',
      if (verifiedOnly) 'verified_only': 'true',
      'limit': limit.toString(),
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ProviderServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ProviderServiceException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode != 200) {
      throw ProviderServiceException('Failed to load service providers.');
    }

    try {
      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      return data
          .map((item) => ProviderProfile.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw ProviderServiceException('Unexpected response from server.');
    }
  }

  /// Fetches the logged-in provider's own profile via GET /api/profile/me.
  /// Requires the bearer token returned from login/signup.
  static Future<ProviderProfile> getMyProfile(String accessToken) async {
    final uri = Uri.parse('$apiBaseUrl/api/profile/me');

    http.Response response;
    try {
      response = await http
          .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ProviderServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ProviderServiceException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode == 401) {
      throw ProviderServiceException('Your session has expired. Please log in again.');
    }
    if (response.statusCode != 200) {
      throw ProviderServiceException('Failed to load your profile.');
    }

    try {
      return ProviderProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      throw ProviderServiceException('Unexpected response from server.');
    }
  }

  /// Updates personal + professional info via PUT /api/profile/me. Pass
  /// only the fields that changed — omitted (null) fields are left as-is
  /// server-side.
  static Future<ProviderProfile> updateMyProfile({
    required String accessToken,
    String? name,
    String? serviceCategory,
    String? experience,
    String? bio,
    bool? availability,
    String? maritalStatus,
    String? permanentAddress,
    String? currentAddress,
    String? city,
    String? municipality,
    String? tole,
    int? wardNo,
    String? citizenshipNumber,
    String? alternativeEmail,
    String? alternativePhone,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'service_category': ?serviceCategory,
      'experience': ?experience,
      'bio': ?bio,
      'availability': ?availability,
      'marital_status': ?maritalStatus,
      'permanent_address': ?permanentAddress,
      'current_address': ?currentAddress,
      'city': ?city,
      'municipality': ?municipality,
      'tole': ?tole,
      'ward_no': ?wardNo,
      'citizenship_number': ?citizenshipNumber,
      'alternative_email': ?alternativeEmail,
      'alternative_phone': ?alternativePhone,
    };

    http.Response response;
    try {
      response = await http
          .put(
        Uri.parse('$apiBaseUrl/api/profile/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ProviderServiceException('Request timed out. Please check your connection.');
    } catch (_) {
      throw ProviderServiceException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode == 401) {
      throw ProviderServiceException('Your session has expired. Please log in again.');
    }
    if (response.statusCode != 200) {
      throw ProviderServiceException(_extractDetail(response) ?? 'Failed to update your profile.');
    }

    try {
      return ProviderProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      throw ProviderServiceException('Unexpected response from server.');
    }
  }

  /// Uploads the front and/or back citizenship photo via
  /// POST /api/profile/me/documents/citizenship (multipart). Pass either
  /// or both files — whichever side changed.
  static Future<ProviderProfile> uploadCitizenshipDocuments({
    required String accessToken,
    File? front,
    File? back,
  }) async {
    if (front == null && back == null) {
      throw ProviderServiceException('Select at least one image to upload.');
    }

    final uri = Uri.parse('$apiBaseUrl/api/profile/me/documents/citizenship');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken';

    if (front != null) {
      request.files.add(await http.MultipartFile.fromPath('front', front.path));
    }
    if (back != null) {
      request.files.add(await http.MultipartFile.fromPath('back', back.path));
    }

    http.Response response;
    try {
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ProviderServiceException('Upload timed out. Please check your connection.');
    } catch (_) {
      throw ProviderServiceException('Unable to reach the server. Please check your connection.');
    }

    if (response.statusCode == 401) {
      throw ProviderServiceException('Your session has expired. Please log in again.');
    }
    if (response.statusCode != 200) {
      throw ProviderServiceException(_extractDetail(response) ?? 'Failed to upload documents.');
    }

    try {
      return ProviderProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      throw ProviderServiceException('Unexpected response from server.');
    }
  }

  static String? _extractDetail(http.Response response) {
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is String) return detail;
    } catch (_) {
      // keep default message
    }
    return null;
  }
}