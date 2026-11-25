/// Buy-now-or-wait advice, as returned by `GET /products/{id}/advice`.
///
/// ```json
/// {"product_id": 1, "current": 49999, "low_30d": 48999,
///  "avg_30d": 52000, "points_used": 12, "verdict": "buy_now"}
/// ```
///
/// Any of the price fields may be null when there is not enough live
/// data; `verdict` is then expected to be `"unknown"`. The app never
/// computes a verdict from sample data — when the backend is
/// unreachable the advice card shows an "unavailable" state instead.
class PriceAdvice {
  const PriceAdvice({
    required this.productId,
    this.current,
    this.low30d,
    this.avg30d,
    required this.pointsUsed,
    required this.verdict,
  });

  factory PriceAdvice.fromJson(Map<String, dynamic> json) {
    return PriceAdvice(
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      current: (json['current'] as num?)?.toDouble(),
      low30d: (json['low_30d'] as num?)?.toDouble(),
      avg30d: (json['avg_30d'] as num?)?.toDouble(),
      pointsUsed: (json['points_used'] as num?)?.toInt() ?? 0,
      verdict: json['verdict'] as String? ?? 'unknown',
    );
  }

  final int productId;

  /// Current live price (EGP), null when unknown.
  final double? current;

  /// Lowest live price in the last 30 days, null when unknown.
  final double? low30d;

  /// Average live price in the last 30 days, null when unknown.
  final double? avg30d;

  /// How many live history points the verdict was computed from.
  final int pointsUsed;

  /// One of 'buy_now' | 'wait' | 'fair' | 'unknown'. Unknown values
  /// from the backend are treated as 'unknown' by [verdictLabelKey].
  final String verdict;

  /// True when the backend actually had live data behind this advice.
  bool get hasData => verdict != 'unknown' && current != null;
}

/// Translation key for the verdict badge. Unknown verdict codes fall
/// back to the 'unknown' label so a new backend value never crashes
/// the UI or shows a raw code.
String verdictLabelKey(String verdict) {
  switch (verdict) {
    case 'buy_now':
      return 'adviceVerdictBuyNow';
    case 'wait':
      return 'adviceVerdictWait';
    case 'fair':
      return 'adviceVerdictFair';
    case 'unknown':
    default:
      return 'adviceVerdictUnknown';
  }
}

/// Translation key for the one-line reason under the verdict badge.
String verdictReasonKey(String verdict) {
  switch (verdict) {
    case 'buy_now':
      return 'adviceReasonBuyNow';
    case 'wait':
      return 'adviceReasonWait';
    case 'fair':
      return 'adviceReasonFair';
    case 'unknown':
    default:
      return 'adviceReasonUnknown';
  }
}
