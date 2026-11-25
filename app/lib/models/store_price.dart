import 'product.dart';

/// One store's price for a product, as returned by
/// `GET /products/{id}/compare` (prices sorted cheapest first).
class StorePrice {
  const StorePrice({
    required this.store,
    required this.storeSlug,
    required this.price,
    required this.currency,
    required this.inStock,
    required this.url,
    this.fetchedAt,
    this.installmentMonthly,
    this.installmentMonths,
    this.installmentIsSample = false,
    this.shippingFee,
    this.shippingIsSample = false,
    this.deliveryDaysMin,
    this.deliveryDaysMax,
    this.totalPrice,
  });

  factory StorePrice.fromJson(Map<String, dynamic> json) {
    return StorePrice(
      store: json['store'] as String? ?? '',
      storeSlug: json['store_slug'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'EGP',
      inStock: json['in_stock'] as bool? ?? true,
      url: json['url'] as String? ?? '',
      fetchedAt: json['fetched_at'] as String?,
      // Phase 3 fields: all optional — older backends omit them and the
      // app shows "not available" instead of crashing.
      installmentMonthly:
          (json['installment_monthly'] as num?)?.toDouble(),
      installmentMonths: (json['installment_months'] as num?)?.toInt(),
      installmentIsSample: json['installment_is_sample'] as bool? ?? false,
      shippingFee: (json['shipping_fee'] as num?)?.toDouble(),
      shippingIsSample: json['shipping_is_sample'] as bool? ?? false,
      deliveryDaysMin: (json['delivery_days_min'] as num?)?.toInt(),
      deliveryDaysMax: (json['delivery_days_max'] as num?)?.toInt(),
      totalPrice: (json['total_price'] as num?)?.toDouble(),
    );
  }

  final String store;
  final String storeSlug;
  final double price;

  /// Currency code, normally "EGP".
  final String currency;

  final bool inStock;

  /// Deep link to the product page on the store, opened in the external
  /// browser when the user taps the price (or the "Go to store" button).
  /// Sample rows link to the store's search page for the product.
  final String url;

  /// ISO-8601 timestamp of when this price was fetched.
  final String? fetchedAt;

  /// Monthly installment amount (EGP), null when the store offers no
  /// installment plan for this product.
  final double? installmentMonthly;

  /// Installment plan length in months, null when unknown.
  final int? installmentMonths;

  /// True when the installment figures are sample/demo data.
  final bool installmentIsSample;

  /// Shipping fee (EGP). Null when unknown; 0 means free shipping.
  final double? shippingFee;

  /// True when the shipping fee is sample/demo data.
  final bool shippingIsSample;

  /// Delivery estimate in days (min/max), null when unknown.
  final int? deliveryDaysMin;
  final int? deliveryDaysMax;

  /// Total price (cash price + shipping) as reported by the backend,
  /// null when the backend does not report it.
  final double? totalPrice;

  /// Total price to sort/display: the backend's [totalPrice] when
  /// present, otherwise cash price + shipping fee when the fee is
  /// known, otherwise null (unknown total — sorts last in total mode).
  double? get effectiveTotal =>
      totalPrice ?? (shippingFee == null ? null : price + shippingFee!);
}

/// Full payload of `GET /products/{id}/compare`.
class CompareResult {
  const CompareResult({
    required this.product,
    required this.prices,
    this.cheapest,
    required this.savingsVsMax,
  });

  factory CompareResult.fromJson(Map<String, dynamic> json) {
    final prices = (json['prices'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => StorePrice.fromJson(e as Map<String, dynamic>))
        .toList();
    return CompareResult(
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      prices: prices,
      cheapest: json['cheapest'] == null
          ? null
          : StorePrice.fromJson(json['cheapest'] as Map<String, dynamic>),
      savingsVsMax: (json['savings_vs_max'] as num?)?.toDouble() ?? 0,
    );
  }

  final Product product;

  /// Store prices, cheapest first.
  final List<StorePrice> prices;

  /// The cheapest entry (same as prices.first when non-empty).
  final StorePrice? cheapest;

  /// How much (EGP) the cheapest price saves vs the most expensive price.
  final double savingsVsMax;
}
