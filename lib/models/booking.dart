import 'service_job.dart';

class Booking {
  final String id;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String? serviceCategory;

  /// The specific job booked under that category, e.g. "Fan Installation"
  /// under "Electrical". Null for a booking made at category level (a
  /// category with no jobs listed), or one made before jobs had prices.
  final String? jobTitle;

  /// What the job was priced at *when it was booked*, in NPR — a snapshot
  /// taken server-side, so it stays correct even if that job is repriced
  /// later. Null whenever [jobTitle] is null.
  final double? price;
  final PriceType? priceType;

  /// Server-formatted display string for [price], e.g. "Rs. 600" or
  /// "From Rs. 2,500".
  final String? priceLabel;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? problemDescription;
  final String? notes;
  final DateTime? preferredDate;
  final String status; // pending | accepted | rejected | on_the_way | arrived | completed | cancelled
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The provider's own live position while navigating to the customer.
  /// Both null before the provider taps "I'm on my way" and again once
  /// the job is marked completed — see [isProviderLocationLive].
  final double? providerLatitude;
  final double? providerLongitude;
  final DateTime? providerLocationUpdatedAt;

  final int? ratingStars; // 1-5 once the customer has rated the service for this booking, else null
  final String? ratingComment;
  final DateTime? ratedAt;

  Booking({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.customerPhone,
    this.serviceCategory,
    this.jobTitle,
    this.price,
    this.priceType,
    this.priceLabel,
    this.latitude,
    this.longitude,
    this.problemDescription,
    this.notes,
    this.preferredDate,
    this.providerLatitude,
    this.providerLongitude,
    this.providerLocationUpdatedAt,
    this.ratingStars,
    this.ratingComment,
    this.ratedAt,
  });

  /// True when this booking has a price to display.
  bool get hasPrice => priceLabel != null;

  /// What to headline the booking with: the specific job where there is
  /// one, otherwise the service category.
  String get displayTitle => jobTitle ?? serviceCategory ?? 'Service';

  /// True once this booking has been marked completed and the customer
  /// hasn't rated it yet — i.e. the "Rate" button should show.
  bool get canBeRated => status == 'completed' && ratingStars == null;

  /// True while the provider is actively sharing their live position for
  /// this booking (they've set out and haven't marked the job completed).
  bool get isProviderLocationLive => providerLatitude != null && providerLongitude != null;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String?,
      serviceCategory: json['service_category'] as String?,
      jobTitle: json['job_title'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      priceType: json['price_type'] != null
          ? PriceType.fromJson(json['price_type'] as String)
          : null,
      priceLabel: json['price_label'] as String?,
      address: json['address'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      problemDescription: json['problem_description'] as String?,
      notes: json['notes'] as String?,
      preferredDate: json['preferred_date'] != null ? DateTime.parse(json['preferred_date'] as String) : null,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      providerLatitude: (json['provider_latitude'] as num?)?.toDouble(),
      providerLongitude: (json['provider_longitude'] as num?)?.toDouble(),
      providerLocationUpdatedAt: json['provider_location_updated_at'] != null
          ? DateTime.parse(json['provider_location_updated_at'] as String)
          : null,
      ratingStars: json['rating_stars'] as int?,
      ratingComment: json['rating_comment'] as String?,
      ratedAt: json['rated_at'] != null ? DateTime.parse(json['rated_at'] as String) : null,
    );
  }
}