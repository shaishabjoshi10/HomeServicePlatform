/// The only service categories that offer emergency service. Mirrors
/// EMERGENCY_SERVICE_CATEGORIES on the server.
const kEmergencyCategories = <String>['Electrical', 'Plumbing'];

class EmergencyProvider {
  final String userId;
  final String name;
  final String serviceCategory;
  final String? experience;
  final String? bio;
  final String city;
  final String? profilePictureUrl;
  final double latitude;
  final double longitude;
  final double distanceKm;

  const EmergencyProvider({
    required this.userId,
    required this.name,
    required this.serviceCategory,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    this.experience,
    this.bio,
    this.profilePictureUrl,
  });

  factory EmergencyProvider.fromJson(Map<String, dynamic> json) {
    return EmergencyProvider(
      userId: json['user_id'].toString(),
      name: json['name'] as String,
      serviceCategory: json['service_category'] as String,
      experience: json['experience'] as String?,
      bio: json['bio'] as String?,
      city: json['city'] as String,
      profilePictureUrl: json['profile_picture_url'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceKm: (json['distance_km'] as num).toDouble(),
    );
  }
}