/// Data models for the Admin Dashboard. Kept in one file since they're all
/// small, read-only "rows from an admin endpoint" shapes with no shared
/// behavior beyond parsing — unlike Booking, none of these need methods or
/// derived getters of their own.

class AdminAccount {
  final String id;
  final String email;
  final DateTime createdAt;

  AdminAccount({required this.id, required this.email, required this.createdAt});

  factory AdminAccount.fromJson(Map<String, dynamic> json) {
    return AdminAccount(
      id: json['id'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// The counts behind the dashboard's overview cards.
class AdminStats {
  final int totalCustomers;
  final int totalProviders;
  final int pendingVerifications;
  final int verifiedProviders;
  final int rejectedProviders;
  final int totalBookings;

  AdminStats({
    required this.totalCustomers,
    required this.totalProviders,
    required this.pendingVerifications,
    required this.verifiedProviders,
    required this.rejectedProviders,
    required this.totalBookings,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    return AdminStats(
      totalCustomers: json['total_customers'] as int,
      totalProviders: json['total_providers'] as int,
      pendingVerifications: json['pending_verifications'] as int,
      verifiedProviders: json['verified_providers'] as int,
      rejectedProviders: json['rejected_providers'] as int,
      totalBookings: json['total_bookings'] as int,
    );
  }
}

/// One row in the admin's customer list.
class AdminCustomer {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final String? address;
  final String? profilePictureUrl;
  final int totalBookings;

  AdminCustomer({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.address,
    required this.profilePictureUrl,
    required this.totalBookings,
  });

  factory AdminCustomer.fromJson(Map<String, dynamic> json) {
    return AdminCustomer(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      address: json['address'] as String?,
      profilePictureUrl: json['profile_picture_url'] as String?,
      totalBookings: json['total_bookings'] as int,
    );
  }
}

/// One row in the admin's provider list — enough to render the card and
/// decide which verification-status chip to show, without the full
/// documents/bio payload that only the detail page needs.
class AdminProvider {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final String? serviceCategory;
  final String? experience;
  final String city;
  final String verificationStatus; // 'pending' | 'verified' | 'rejected'
  final bool availability;
  final String? profilePictureUrl;
  final int totalBookings;

  AdminProvider({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.serviceCategory,
    required this.experience,
    required this.city,
    required this.verificationStatus,
    required this.availability,
    required this.profilePictureUrl,
    required this.totalBookings,
  });

  bool get isPending => verificationStatus == 'pending';
  bool get isVerified => verificationStatus == 'verified';
  bool get isRejected => verificationStatus == 'rejected';

  factory AdminProvider.fromJson(Map<String, dynamic> json) {
    return AdminProvider(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      serviceCategory: json['service_category'] as String?,
      experience: json['experience'] as String?,
      city: json['city'] as String,
      verificationStatus: json['verification_status'] as String,
      availability: json['availability'] as bool,
      profilePictureUrl: json['profile_picture_url'] as String?,
      totalBookings: json['total_bookings'] as int,
    );
  }
}

/// The full profile shown on the admin's provider review page — everything
/// [AdminProvider] has, plus the personal/contact details and the
/// verification documents an admin actually reviews before deciding.
class AdminProviderDetail {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final DateTime createdAt;
  final String? serviceCategory;
  final String? experience;
  final String? bio;
  final DateTime? dateOfBirth;
  final String city;
  final String? citizenshipNumber;
  final String? citizenshipFrontUrl;
  final String? citizenshipBackUrl;
  final String? alternativeEmail;
  final String? alternativePhone;
  final String? profilePictureUrl;
  final String verificationStatus;
  final bool availability;
  final int totalBookings;
  final int completedBookings;

  AdminProviderDetail({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.serviceCategory,
    required this.experience,
    required this.bio,
    required this.dateOfBirth,
    required this.city,
    required this.citizenshipNumber,
    required this.citizenshipFrontUrl,
    required this.citizenshipBackUrl,
    required this.alternativeEmail,
    required this.alternativePhone,
    required this.profilePictureUrl,
    required this.verificationStatus,
    required this.availability,
    required this.totalBookings,
    required this.completedBookings,
  });

  bool get isPending => verificationStatus == 'pending';
  bool get isVerified => verificationStatus == 'verified';
  bool get isRejected => verificationStatus == 'rejected';

  factory AdminProviderDetail.fromJson(Map<String, dynamic> json) {
    return AdminProviderDetail(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      serviceCategory: json['service_category'] as String?,
      experience: json['experience'] as String?,
      bio: json['bio'] as String?,
      dateOfBirth: json['date_of_birth'] != null ? DateTime.parse(json['date_of_birth'] as String) : null,
      city: json['city'] as String,
      citizenshipNumber: json['citizenship_number'] as String?,
      citizenshipFrontUrl: json['citizenship_front_url'] as String?,
      citizenshipBackUrl: json['citizenship_back_url'] as String?,
      alternativeEmail: json['alternative_email'] as String?,
      alternativePhone: json['alternative_phone'] as String?,
      profilePictureUrl: json['profile_picture_url'] as String?,
      verificationStatus: json['verification_status'] as String,
      availability: json['availability'] as bool,
      totalBookings: json['total_bookings'] as int,
      completedBookings: json['completed_bookings'] as int,
    );
  }
}
