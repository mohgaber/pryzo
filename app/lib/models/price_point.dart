/// One historical price observation, as returned by
/// `GET /products/{id}/history?days=30`.
///
/// A point is a SAMPLE point when the backend flags it `is_sample: true`
/// (a seeded/demo price stored alongside live ones). A missing flag on
/// live API data means live (`is_sample` defaults to false); bundled
/// fallback data sets [isSample] to true explicitly (see
/// `sampleHistory` in lib/data/sample_data.dart). Sample points must
/// never be presented as the live lowest price.
class PricePoint {
  const PricePoint({
    required this.price,
    required this.store,
    required this.fetchedAt,
    this.isSample = false,
  });

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      price: (json['price'] as num).toDouble(),
      store: json['store'] as String? ?? '',
      fetchedAt: json['fetched_at'] as String? ?? '',
      // Missing flag on API data = live price (false). Only an explicit
      // `is_sample: true` from the backend marks a point as sample.
      isSample: json['is_sample'] as bool? ?? false,
    );
  }

  final double price;
  final String store;

  /// ISO-8601 timestamp of when this price was observed.
  final String fetchedAt;

  /// True when this price is a sample/demo price, not a live fetched one.
  final bool isSample;
}
