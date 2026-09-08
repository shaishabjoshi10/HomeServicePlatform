class ProviderProfile {
  final String id;
  final String userId;
  final String name;
  final String? serviceCategory;
  final String? experience;
  final String? bio;
  final String? maritalStatus;
  final String? permanentAddress;
  final String? currentAddress;
  final String? city;
  final String? municipality;
  final String? tole;
  final int? wardNo;
  final String? citizenshipNumber;
  final String? citizenshipFrontUrl;
  final String? citizenshipBackUrl;
  final String? alternativeEmail;
  final String? alternativePhone;
  final String verificationStatus;
  final bool availability;
  final double rating;
  final int reviewsCount;

  ProviderProfile({
    required this.id,
    required this.userId,
    required this.name,
    required this.verificationStatus,
    required this.availability,
    required this.rating,
    required this.reviewsCount,
    this.serviceCategory,
    this.experience,
    this.bio,
    this.maritalStatus,
    this.permanentAddress,
    this.currentAddress,
    this.city,
    this.municipality,
    this.tole,
    this.wardNo,
    this.citizenshipNumber,
    this.citizenshipFrontUrl,
    this.citizenshipBackUrl,
    this.alternativeEmail,
    this.alternativePhone,
  });

  /// A friendly fallback for display when the provider hasn't set a
  /// service category yet (e.g. right after signup).
  String get displayRole => serviceCategory?.isNotEmpty == true ? serviceCategory! : 'Service Provider';

  /// True once personal info, professional info, and documents have all
  /// been filled in — used to prompt providers to complete their profile.
  bool get isComplete =>
      permanentAddress?.isNotEmpty == true &&
          city?.isNotEmpty == true &&
          municipality?.isNotEmpty == true &&
          wardNo != null &&
          serviceCategory?.isNotEmpty == true &&
          citizenshipNumber?.isNotEmpty == true &&
          citizenshipFrontUrl != null &&
          citizenshipBackUrl != null &&
          alternativeEmail?.isNotEmpty == true;

  factory ProviderProfile.fromJson(Map<String, dynamic> json) {
    return ProviderProfile(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      name: json['name'] as String,
      serviceCategory: json['service_category'] as String?,
      experience: json['experience'] as String?,
      bio: json['bio'] as String?,
      maritalStatus: json['marital_status'] as String?,
      permanentAddress: json['permanent_address'] as String?,
      currentAddress: json['current_address'] as String?,
      city: json['city'] as String?,
      municipality: json['municipality'] as String?,
      tole: json['tole'] as String?,
      wardNo: json['ward_no'] as int?,
      citizenshipNumber: json['citizenship_number'] as String?,
      citizenshipFrontUrl: json['citizenship_front_url'] as String?,
      citizenshipBackUrl: json['citizenship_back_url'] as String?,
      alternativeEmail: json['alternative_email'] as String?,
      alternativePhone: json['alternative_phone'] as String?,
      verificationStatus: json['verification_status'] as String,
      availability: json['availability'] as bool,
      rating: (json['rating'] as num).toDouble(),
      reviewsCount: json['reviews_count'] as int,
    );
  }
}