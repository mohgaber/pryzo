import 'product.dart';

/// One saved watchlist entry, as returned by `GET /watchlist`.
class WatchlistItem {
  const WatchlistItem({
    required this.id,
    required this.productId,
    this.product,
    this.lowestPrice,
    this.createdAt,
  });

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      id: (json['id'] as num).toInt(),
      productId: (json['product_id'] as num).toInt(),
      product: json['product'] == null
          ? null
          : Product.fromJson(json['product'] as Map<String, dynamic>),
      lowestPrice: json['lowest_price'] == null
          ? null
          : (json['lowest_price'] as num).toDouble(),
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final int productId;

  /// Embedded product summary (null for locally-created fallback items).
  final Product? product;

  /// Current cheapest price across stores, in EGP.
  final double? lowestPrice;

  final String? createdAt;
}

/// A price alert created via `POST /alerts` and listed by `GET /alerts`.
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.productId,
    this.targetPrice,
    required this.active,
    this.triggered,
    this.productName,
    this.createdAt,
    this.alertType = 'price',
    this.storeSlug,
  });

  factory PriceAlert.fromJson(Map<String, dynamic> json) {
    return PriceAlert(
      id: (json['id'] as num).toInt(),
      productId: (json['product_id'] as num).toInt(),
      // Back-in-stock alerts carry no target price (null on the
      // backend); price alerts always carry one.
      targetPrice: (json['target_price'] as num?)?.toDouble(),
      active: json['active'] as bool? ?? true,
      // `triggered` is sent by newer backends; older ones omit it and the
      // app evaluates it locally instead (see HistoryScreen._isTriggered).
      triggered: json['triggered'] as bool?,
      productName: json['product_name'] as String?,
      createdAt: json['created_at'] as String?,
      alertType: json['alert_type'] as String? ?? 'price',
      storeSlug: json['store_slug'] as String?,
    );
  }

  final int id;
  final int productId;

  /// Notify the user when the price drops to this value (EGP) or below.
  /// Null for back-in-stock alerts, which have no price target.
  final double? targetPrice;

  final bool active;

  /// True when the current lowest price has already reached [targetPrice].
  /// Null when the backend did not report it — the app then evaluates it
  /// locally from the compare data.
  final bool? triggered;

  /// Product name as returned by GET /alerts (null on older backends).
  final String? productName;

  final String? createdAt;

  /// 'price' (default) or 'back_in_stock'. Unknown values are shown
  /// as price alerts by the history screen's fallback.
  final String alertType;

  /// Store this alert watches, for back-in-stock alerts
  /// (e.g. 'jumia'). Null for plain price alerts.
  final String? storeSlug;

  /// True for back-in-stock alerts.
  bool get isBackInStock => alertType == 'back_in_stock';
}
