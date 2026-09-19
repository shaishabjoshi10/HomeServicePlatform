/// The overall rating of one service (e.g. "Plumbing"): the average of every
/// customer rating left on completed bookings of that service. This is a
/// rating of the service as a whole — never of an individual provider.
class ServiceRating {
  final String serviceCategory;
  final double rating; // average stars, 0.0 when nobody has rated it yet
  final int reviewsCount;

  const ServiceRating({
    required this.serviceCategory,
    required this.rating,
    required this.reviewsCount,
  });

  bool get hasReviews => reviewsCount > 0;

  /// "4.6 (23 reviews)", or "No ratings yet" for an unrated service.
  String get label {
    if (!hasReviews) return 'No ratings yet';
    return '${rating.toStringAsFixed(1)} ($reviewsCount ${reviewsCount == 1 ? 'review' : 'reviews'})';
  }

  factory ServiceRating.fromJson(Map<String, dynamic> json) {
    return ServiceRating(
      serviceCategory: json['service_category'] as String,
      rating: (json['rating'] as num).toDouble(),
      reviewsCount: json['reviews_count'] as int,
    );
  }
}
