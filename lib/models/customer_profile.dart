class CustomerProfile {
  final String id;
  final String userId;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? profilePictureUrl;

  CustomerProfile({
    required this.id,
    required this.userId,
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.profilePictureUrl,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) {
    return CustomerProfile(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      name: json['name'] as String,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      profilePictureUrl: json['profile_picture_url'] as String?,
    );
  }
}