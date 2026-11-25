// HTTP client for the Pryzo FastAPI backend.
//
// Contract (JSON):
//   GET    /health                      -> {"status": "ok"}
//   GET    /search?q=...&category=...&limit=20&offset=0
//                                            -> {"items": [{id, name, brand,
//                                            category, image_url,
//                                            lowest_price, stores_count}],
//                                            "total": N, "limit": 20,
//                                            "offset": 0} (paginated)
//   GET    /products/{id}              -> product detail
//   GET    /products/{id}/compare      -> {"product": {...},
//                                            "prices": [{store, store_slug,
//                                            price, currency: "EGP",
//                                            in_stock, url, fetched_at}],
//                                            "cheapest": {...},
//                                            "savings_vs_max": number}
//                                          `cheapest` / `lowest_price` are
//                                          LIVE-only on the backend: the app
//                                          never recomputes a lowest price
//                                          over sample data and never
//                                          substitutes a sample price for
//                                          them (see HistoryScreen._load).
//   GET    /products/{id}/history?days=30 -> [{"price", "store",
//                                                "fetched_at",
//                                                "is_sample": bool}]
//                                          Each point carries `is_sample`
//                                          (missing = live, false); bundled
//                                          fallback points are sample.
//   GET    /watchlist                  -> [{id, product_id, product: {...},
//                                            lowest_price, created_at}]
//   POST   /watchlist {"product_id": int}
//   DELETE /watchlist/{id}
//   POST   /alerts {"product_id": int, "target_price": double,
//                     "alert_type": "price"|"back_in_stock",
//                     "store_slug": string?}
//   GET    /alerts                     -> [{id, product_id, target_price,
//                                            active, created_at,
//                                            alert_type, store_slug,
//                                            triggered}]
//   GET    /products/{id}/advice      -> {product_id, current, low_30d,
//                                            avg_30d, points_used,
//                                            verdict: "buy_now"|"wait"|
//                                            "fair"|"unknown"}
//   GET    /products/{id}/coupons     -> [{id, store, store_slug, code,
//                                            discount_type, discount_value,
//                                            min_order, expires_at,
//                                            is_sample, active}]
//   Compare price rows also carry (all optional): installment_monthly,
//   installment_months, installment_is_sample, shipping_fee,
//   shipping_is_sample, delivery_days_min/max, total_price.
//
// Every call uses a 20s timeout and throws on network error,
// timeout or non-2xx status. GETs get one automatic retry (see
// _getJson); callers catch the throw and fall back to the
// bundled sample data (see lib/data/sample_data.dart) — the app must never
// crash just because the backend is unreachable.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/advice.dart';
import '../models/coupon.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/store_price.dart';
import '../models/watchlist_item.dart';

class ApiService {
  ApiService({this.baseUrl = defaultBaseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Default backend address.
  ///
  /// >>> AFTER RENDER DEPLOY, CHANGE THIS ONE CONSTANT to the live
  /// Render service URL, e.g. 'https://pryzo-api.onrender.com', then
  /// rebuild the APK. Every API call in the app goes through this
  /// constant (see backend/DEPLOY.md step 7). Do not scatter other
  /// base URLs through the code.
  ///
  /// - Desktop / iOS simulator / same-machine browser: http://127.0.0.1:8000
  /// - Android emulator: use http://10.0.2.2:8000 instead
  ///   (the emulator's alias for the host machine's localhost).
  /// - Physical Android phone: use the PC's LAN IP, e.g.
  ///   http://192.168.1.10:8000 (phone and PC on the same Wi-Fi).
  static const String defaultBaseUrl = 'https://pryzo-api-production.up.railway.app';

  final String baseUrl;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  /// GET with one automatic retry on network/timeout errors: a slow
  /// mobile network or a brief server restart (e.g. a Railway
  /// redeploy) must not drop the app straight into its bundled sample
  /// data. Non-2xx statuses and bad JSON are not retried (the server
  /// answered; retrying will not help). Only GETs are retried —
  /// POST/DELETE are user actions and must never run twice.
  Future<dynamic> _getJson(String path) async {
    try {
      return await _getJsonOnce(path);
    } on TimeoutException catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return _getJsonOnce(path);
    } on http.ClientException catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return _getJsonOnce(path);
    }
  }

  Future<dynamic> _getJsonOnce(String path) async {
    final response = await _client
        .get(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'GET $path failed with status ${response.statusCode}',
      );
    }
    return jsonDecode(response.body);
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'POST $path failed with status ${response.statusCode}',
      );
    }
    return jsonDecode(response.body);
  }

  Future<void> _delete(String path) async {
    final response = await _client
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'DELETE $path failed with status ${response.statusCode}',
      );
    }
  }

  /// GET /health — quick liveness check.
  Future<bool> checkHealth() async {
    try {
      final data = await _getJson('/health');
      return data is Map<String, dynamic> && data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// GET /search?q=...&category=...&limit=...&offset=...
  ///
  /// Paginated (default 20 per page): pass [offset] to fetch the next
  /// page; [total] is the number of matching products on the server.
  /// [category] is an app category key ('mobiles', 'home', ...) or
  /// 'all'/null for no category filter (filtered server-side).
  Future<SearchPage> searchProducts(
    String q, {
    String? category,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = StringBuffer(
      '/search?q=${Uri.encodeQueryComponent(q)}'
      '&limit=$limit&offset=$offset',
    );
    if (category != null && category != 'all') {
      params.write('&category=${Uri.encodeQueryComponent(category)}');
    }
    final data = await _getJson(params.toString());
    final map = data as Map<String, dynamic>;
    final list = map['items'] as List<dynamic>;
    return SearchPage(
      items: list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (map['total'] as num).toInt(),
    );
  }

  /// GET /products/{id}
  Future<Product> getProduct(int id) async {
    final data = await _getJson('/products/$id');
    return Product.fromJson(data as Map<String, dynamic>);
  }

  /// GET /products/{id}/compare
  Future<CompareResult> compareProduct(int id) async {
    final data = await _getJson('/products/$id/compare');
    return CompareResult.fromJson(data as Map<String, dynamic>);
  }

  /// GET /products/{id}/history?days=30
  ///
  /// The backend returns newest first; the list is re-sorted oldest first
  /// so the price chart reads left-to-right in time order.
  Future<List<PricePoint>> getHistory(int id, {int days = 30}) async {
    final data = await _getJson('/products/$id/history?days=$days');
    final list = data as List<dynamic>;
    final points = list
        .map((e) => PricePoint.fromJson(e as Map<String, dynamic>))
        .toList();
    points.sort((a, b) => a.fetchedAt.compareTo(b.fetchedAt));
    return points;
  }

  /// GET /watchlist
  Future<List<WatchlistItem>> getWatchlist() async {
    final data = await _getJson('/watchlist');
    final list = data as List<dynamic>;
    return list
        .map((e) => WatchlistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /watchlist {"product_id": int}
  Future<WatchlistItem> addToWatchlist(int productId) async {
    final data = await _postJson('/watchlist', <String, dynamic>{
      'product_id': productId,
    });
    return WatchlistItem.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /watchlist/{id}
  Future<void> removeFromWatchlist(int id) async {
    await _delete('/watchlist/$id');
  }

  /// POST /alerts — price alert, or back-in-stock alert when
  /// [alertType] is 'back_in_stock' (then [targetPrice] must be null
  /// and [storeSlug] names the store to watch). The body carries
  /// exactly the contract fields; `target_price` is omitted for
  /// back-in-stock alerts.
  Future<PriceAlert> createAlert(
    int productId,
    double? targetPrice, {
    String alertType = 'price',
    String? storeSlug,
  }) async {
    final body = <String, dynamic>{
      'product_id': productId,
      'alert_type': alertType,
    };
    if (targetPrice != null) {
      body['target_price'] = targetPrice;
    }
    if (storeSlug != null) {
      body['store_slug'] = storeSlug;
    }
    final data = await _postJson('/alerts', body);
    return PriceAlert.fromJson(data as Map<String, dynamic>);
  }

  /// POST /alerts — back-in-stock alert for one store.
  Future<PriceAlert> createBackInStockAlert(
    int productId,
    String storeSlug,
  ) =>
      createAlert(productId, null,
          alertType: 'back_in_stock', storeSlug: storeSlug);

  /// GET /products/{id}/advice — buy-now-or-wait verdict, computed by
  /// the backend from live prices only. Throws when unreachable; the
  /// caller shows an "unavailable" card and never invents a verdict
  /// from sample data.
  Future<PriceAdvice> getAdvice(int id) async {
    final data = await _getJson('/products/$id/advice');
    return PriceAdvice.fromJson(data as Map<String, dynamic>);
  }

  /// GET /products/{id}/coupons — discount coupons per store. Throws
  /// when unreachable; the caller hides the coupons section (it never
  /// shows bundled fake coupons as live).
  Future<List<Coupon>> getCoupons(int id) async {
    final data = await _getJson('/products/$id/coupons');
    final list = data as List<dynamic>;
    return list
        .map((e) => Coupon.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /alerts
  Future<List<PriceAlert>> getAlerts() async {
    final data = await _getJson('/alerts');
    final list = data as List<dynamic>;
    return list
        .map((e) => PriceAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void dispose() {
    _client.close();
  }
}

/// A page of search results: the products on this page plus the total
/// number of matching products on the server (for "load more").
class SearchPage {
  const SearchPage({required this.items, required this.total});

  final List<Product> items;
  final int total;
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => 'ApiException: $message';
}
