/// How a job's price should be read.
///
/// - [fixed]: the quoted amount is the whole price for a standard job of
///   this kind (e.g. installing one fan).
/// - [startingFrom]: the real cost depends on scope (area, severity,
///   materials), so the quoted amount is the minimum and the final figure is
///   agreed once the professional has seen the work.
enum PriceType {
  fixed,
  startingFrom;

  /// Parses the server's value ("fixed" / "starting_from"). Anything
  /// unrecognised falls back to [fixed] rather than throwing, so one odd
  /// value from a newer backend can't break the whole services list.
  static PriceType fromJson(String? value) =>
      value == 'starting_from' ? PriceType.startingFrom : PriceType.fixed;
}

/// One specific, bookable job under a service category — e.g. "Fan
/// Installation" under "Electrical" — with its own price.
///
/// A category on its own has no price; the price always belongs to the job.
class ServiceJob {
  final String name;
  final String description;
  final double price; // NPR
  final PriceType priceType;

  /// The display string as the server formatted it, e.g. "Rs. 500" or
  /// "From Rs. 2,500". Preferred over formatting [price] locally so the app
  /// and the server never word the same price differently.
  final String priceLabel;

  const ServiceJob({
    required this.name,
    required this.description,
    required this.price,
    required this.priceLabel,
    this.priceType = PriceType.fixed,
  });

  bool get isStartingFrom => priceType == PriceType.startingFrom;

  /// One-line explanation of what the price covers, shown under the price on
  /// the job card and in the booking form.
  String get priceNote => isStartingFrom
      ? 'Final price depends on the work needed'
      : 'Fixed price for this job';

  factory ServiceJob.fromJson(Map<String, dynamic> json) {
    final price = (json['price'] as num).toDouble();
    final priceType = PriceType.fromJson(json['price_type'] as String?);
    return ServiceJob(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      price: price,
      priceType: priceType,
      priceLabel: json['price_label'] as String? ?? _fallbackLabel(price, priceType),
    );
  }

  /// Used only when the server didn't send a label (an older backend, or the
  /// offline fallback catalogue) — otherwise [priceLabel] comes from the API.
  static String _fallbackLabel(double price, PriceType priceType) {
    final amount = price.round().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
    );
    return priceType == PriceType.startingFrom ? 'From Rs. $amount' : 'Rs. $amount';
  }
}

/// A service category with its priced jobs and its overall rating, as
/// returned by GET /api/services/catalog.
class ServiceCatalogEntry {
  final String serviceCategory;
  final double rating; // average stars, 0.0 when nobody has rated it yet
  final int reviewsCount;
  final List<ServiceJob> jobs;

  const ServiceCatalogEntry({
    required this.serviceCategory,
    required this.jobs,
    this.rating = 0.0,
    this.reviewsCount = 0,
  });

  factory ServiceCatalogEntry.fromJson(Map<String, dynamic> json) {
    return ServiceCatalogEntry(
      serviceCategory: json['service_category'] as String,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviewsCount: json['reviews_count'] as int? ?? 0,
      jobs: ((json['jobs'] as List<dynamic>?) ?? const [])
          .map((e) => ServiceJob.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}