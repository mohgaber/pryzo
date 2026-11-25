import '../models/store_price.dart';

/// How the comparison screen's store rows are ordered.
enum CompareSortMode {
  /// By cash price, cheapest first (the default).
  cash,

  /// By monthly installment, cheapest first. Rows without installment
  /// data sort last.
  monthly,

  /// By total price (cash price + shipping), cheapest first. Rows with
  /// an unknown total sort last.
  total,
}

/// Returns a new list of [prices] sorted per [mode]. Within a mode,
/// ties (and rows with missing data) fall back to cash price so the
/// order is stable and predictable. The input list is not mutated.
List<StorePrice> sortStorePrices(
  List<StorePrice> prices,
  CompareSortMode mode,
) {
  final sorted = List<StorePrice>.from(prices);
  int byCash(StorePrice a, StorePrice b) => a.price.compareTo(b.price);
  switch (mode) {
    case CompareSortMode.cash:
      sorted.sort(byCash);
    case CompareSortMode.monthly:
      sorted.sort((a, b) {
        final ma = a.installmentMonthly;
        final mb = b.installmentMonthly;
        if (ma == null && mb == null) {
          return byCash(a, b);
        }
        if (ma == null) {
          return 1;
        }
        if (mb == null) {
          return -1;
        }
        final cmp = ma.compareTo(mb);
        return cmp != 0 ? cmp : byCash(a, b);
      });
    case CompareSortMode.total:
      sorted.sort((a, b) {
        final ta = a.effectiveTotal;
        final tb = b.effectiveTotal;
        if (ta == null && tb == null) {
          return byCash(a, b);
        }
        if (ta == null) {
          return 1;
        }
        if (tb == null) {
          return -1;
        }
        final cmp = ta.compareTo(tb);
        return cmp != 0 ? cmp : byCash(a, b);
      });
  }
  return sorted;
}
