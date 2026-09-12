class Booking {
  final String id;
  final String customerId;
  final String customerName;
  final String providerId;
  final String providerName;
  final String? serviceCategory;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final DateTime? preferredDate;
  final String status; // pending | accepted | rejected | completed | cancelled
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? ratingStars; // 1-5 once the customer has rated this booking, else null
  final String? ratingComment;
  final DateTime? ratedAt;

  Booking({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.providerId,
    required this.providerName,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.serviceCategory,
    this.latitude,
    this.longitude,
    this.notes,
    this.preferredDate,
    this.ratingStars,
    this.ratingComment,
    this.ratedAt,
  });

  /// True once this booking has been marked completed and the customer
  /// hasn't rated it yet — i.e. the "Rate" button should show.
  bool get canBeRated => status == 'completed' && ratingStars == null;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name'] as String,
      providerId: json['provider_id'].toString(),
      providerName: json['provider_name'] as String,
      serviceCategory: json['service_category'] as String?,
      address: json['address'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      preferredDate: json['preferred_date'] != null ? DateTime.parse(json['preferred_date'] as String) : null,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      ratingStars: json['rating_stars'] as int?,
      ratingComment: json['rating_comment'] as String?,
      ratedAt: json['rated_at'] != null ? DateTime.parse(json['rated_at'] as String) : null,
    );
  }
}