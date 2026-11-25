/// A discount coupon for one store, as returned by
/// `GET /products/{id}/coupons`.
///
/// ```json
/// [{"id": 1, "store": "Jumia", "store_slug": "jumia", "code": "SAVE10",
///   "discount_type": "percent", "discount_value": 10,
///   "min_order": 1000, "expires_at": "2026-12-31", "is_sample": false,
///   "active": true}]
/// ```
///
/// A coupon with `is_sample: true` is demo data from the backend seed:
/// the UI must label it clearly as a sample and never present it as a
/// confirmed working code.
class Coupon {
  const Coupon({
    required this.id,
    required this.store,
    required this.storeSlug,
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.minOrder,
    this.expiresAt,
    this.isSample = false,
    this.active = true,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: (json['id'] as num?)?.toInt() ?? 0,
      store: json['store'] as String? ?? '',
      storeSlug: json['store_slug'] as String? ?? '',
      code: json['code'] as String? ?? '',
      discountType: json['discount_type'] as String? ?? 'percent',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      minOrder: (json['min_order'] as num?)?.toDouble(),
      expiresAt: json['expires_at'] as String?,
      isSample: json['is_sample'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
    );
  }

  final int id;
  final String store;
  final String storeSlug;

  /// The code the user types at checkout.
  final String code;

  /// 'percent' or 'fixed'. Any other value is treated as no discount.
  final String discountType;

  /// Percent (e.g. 10 = 10%) or fixed EGP amount, per [discountType].
  final double discountValue;

  /// Minimum order value (EGP) for the coupon to apply, if any.
  final double? minOrder;

  /// Expiry as returned by the backend (date string), if any.
  final String? expiresAt;

  /// True for demo/seed coupons — show the sample badge, never present
  /// the code as confirmed working.
  final bool isSample;

  final bool active;

  /// Whether this coupon can apply to a cash price of [price].
  bool appliesTo(double price) =>
      active && (minOrder == null || price >= minOrder!);

  /// Cash price after applying this coupon to [price]. Never below 0.
  /// Returns [price] unchanged for an unknown discount type.
  double priceAfterDiscount(double price) {
    if (!appliesTo(price)) {
      return price;
    }
    switch (discountType) {
      case 'percent':
        final discounted = price * (1 - discountValue / 100);
        return discounted < 0 ? 0 : discounted;
      case 'fixed':
        final discounted = price - discountValue;
        return discounted < 0 ? 0 : discounted;
      default:
        return price;
    }
  }
}
