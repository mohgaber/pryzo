// In-memory fallback storage used when the backend cannot be reached.
//
// Phase 1 only: watchlist additions and price alerts created while offline
// are kept here for the current app session and shown with a "محفوظ محليًا"
// note. They are NOT synced to the backend yet — that is a later phase.

import '../models/watchlist_item.dart';

class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  /// Product ids the user saved while offline (or when the API failed).
  final Set<int> watchlistProductIds = <int>{};

  /// Alerts created while offline. Ids are negative so they never collide
  /// with server-side alert ids.
  final List<PriceAlert> localAlerts = <PriceAlert>[];

  int _nextLocalAlertId = -1;

  void addToWatchlist(int productId) {
    watchlistProductIds.add(productId);
  }

  void removeFromWatchlist(int productId) {
    watchlistProductIds.remove(productId);
  }

  bool isWatched(int productId) => watchlistProductIds.contains(productId);

  PriceAlert addAlert(int productId, double targetPrice) {
    final alert = PriceAlert(
      id: _nextLocalAlertId--,
      productId: productId,
      targetPrice: targetPrice,
      active: true,
      createdAt: DateTime.now().toIso8601String(),
    );
    localAlerts.add(alert);
    return alert;
  }

  /// Back-in-stock alert created while offline: no target price, just
  /// the store to watch. Kept in memory like price alerts.
  PriceAlert addBackInStockAlert(int productId, String storeSlug) {
    final alert = PriceAlert(
      id: _nextLocalAlertId--,
      productId: productId,
      active: true,
      createdAt: DateTime.now().toIso8601String(),
      alertType: 'back_in_stock',
      storeSlug: storeSlug,
    );
    localAlerts.add(alert);
    return alert;
  }
}
