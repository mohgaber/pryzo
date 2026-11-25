// Price history + alerts screen: a CustomPainter line chart of the
// product's price over the last 30 days, a list of recent price points,
// and the user's price alerts (live from the API, plus any alerts saved
// locally while offline).
//
// Triggered state: an alert is shown as triggered when the backend
// reports `triggered: true` in GET /alerts, OR when the product's
// current LIVE lowest price (from the compare data fetched here) is at
// or below the alert's target price. The local evaluation never uses a
// sample price: when /compare fails the live lowest is unknown (null)
// and only the backend flag can trigger the alert. Push delivery is
// out of scope.

import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../l10n/strings.dart';
import '../models/price_point.dart';
import '../models/store_price.dart';
import '../models/watchlist_item.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../utils/format.dart';
import '../widgets/price_chart.dart';
import '../widgets/sample_banner.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.api,
    required this.productId,
    required this.onProductChanged,
  });

  final ApiService api;
  final int productId;

  /// Keeps the Comparison tab in sync when the user picks another product.
  final ValueChanged<int> onProductChanged;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PricePoint> _points = <PricePoint>[];
  List<PriceAlert> _alerts = <PriceAlert>[];
  bool _loading = true;
  bool _isSample = true;

  /// Current LIVE lowest price for this product, used to evaluate alerts
  /// locally. Null when it could not be determined (e.g. /compare failed)
  /// — a sample price is never substituted here.
  double? _lowestPrice;

  /// Current LIVE per-store rows from /compare, used to evaluate
  /// back-in-stock alerts locally (a watched store row back in stock).
  /// Empty when /compare failed.
  List<StorePrice> _comparePrices = <StorePrice>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    var isSample = false;
    List<PricePoint> points;
    try {
      points = await widget.api.getHistory(widget.productId);
    } catch (_) {
      // Backend unreachable: fall back to bundled sample data, never crash.
      points = sampleHistory(widget.productId);
      isSample = true;
    }
    List<PriceAlert> alerts;
    try {
      alerts = await widget.api.getAlerts();
    } catch (_) {
      alerts = <PriceAlert>[];
      isSample = true;
    }
    // Current lowest price, for the local triggered evaluation.
    // LIVE-ONLY: it comes from /compare, whose cheapest is live-only on
    // the backend. If /compare fails, the lowest price stays unknown
    // (null) — the bundled SAMPLE lowest must never be used here, or a
    // sample price could falsely show an alert as triggered. A failed
    // compare also marks the screen as (partly) sample data.
    double? lowestPrice;
    List<StorePrice> comparePrices = <StorePrice>[];
    try {
      final compare = await widget.api.compareProduct(widget.productId);
      lowestPrice = compare.cheapest?.price;
      comparePrices = compare.prices;
    } catch (_) {
      lowestPrice = null;
      comparePrices = <StorePrice>[];
      isSample = true;
    }
    // Alerts saved locally while offline always show up too.
    final localAlerts = LocalStore.instance.localAlerts
        .where((a) => a.productId == widget.productId)
        .toList();
    final merged = <PriceAlert>[...alerts, ...localAlerts];
    if (!mounted) {
      return;
    }
    setState(() {
      _points = points;
      _alerts = merged;
      _lowestPrice = lowestPrice;
      _comparePrices = comparePrices;
      _isSample = isSample;
      _loading = false;
    });
  }

  /// An alert is triggered when the backend says so, or — for price
  /// alerts — when the product's current lowest price has reached the
  /// target price, and — for back-in-stock alerts — when the watched
  /// store's row in the live /compare data is back in stock. The local
  /// evaluation never uses sample data.
  bool _isTriggered(PriceAlert alert) {
    if (alert.triggered == true) {
      return true;
    }
    if (alert.isBackInStock) {
      final slug = alert.storeSlug;
      if (slug == null) {
        return false;
      }
      return _comparePrices.any(
        (p) => p.storeSlug == slug && p.inStock,
      );
    }
    final target = alert.targetPrice;
    final lowest = _lowestPrice;
    return target != null && lowest != null && lowest <= target;
  }

  String _productName(PriceAlert alert) {
    if (alert.productName != null && alert.productName!.isNotEmpty) {
      return alert.productName!;
    }
    return sampleProducts
        .firstWhere(
          (p) => p.id == alert.productId,
          orElse: () => sampleProducts.first,
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    final lc = localeCode(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_isSample) ...<Widget>[
            const SampleBanner(),
            const SizedBox(height: 12),
          ],
          Text(
            tr(context, 'historyTitle'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: widget.productId,
            decoration: InputDecoration(
              labelText: tr(context, 'productLabel'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            items: sampleProducts
                .map(
                  (p) => DropdownMenuItem<int>(
                    value: p.id,
                    child: Text(
                      p.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                widget.onProductChanged(value);
              }
            },
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFEAF0F6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : PriceChart(points: _points),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'latestPrices'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_points.isEmpty)
            Text(tr(context, 'noHistory'))
          else
            ..._points.reversed.take(6).map(
              (point) => Card(
                color: Colors.white,
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFEAF0F6)),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.history,
                    color: Color(0xFF475569),
                  ),
                  title: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(formatEgp(point.price, locale: lc)),
                      ),
                      if (point.isSample) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                          child: Text(
                            tr(context, 'sampleBadge'),
                            style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(point.store),
                  trailing: Text(
                    shortDate(point.fetchedAt),
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'yourAlerts'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_alerts.isEmpty)
            Text(
              tr(context, 'noAlerts'),
              style: const TextStyle(color: Color(0xFF64748B)),
            )
          else
            ..._alerts.map(_alertCard),
        ],
      ),
    );
  }

  Widget _alertCard(PriceAlert alert) {
    final lc = localeCode(context);
    final triggered = _isTriggered(alert);
    final subtitle = StringBuffer(_productName(alert));
    if (alert.id < 0) {
      subtitle.write(' • ${tr(context, 'savedLocally')}');
    }
    if (triggered) {
      if (alert.isBackInStock) {
        subtitle.write(
          ' • ${tr(context, 'backInStockNow', <String, String>{
            'store': _storeDisplayName(alert),
          })}',
        );
      } else if (_lowestPrice != null) {
        subtitle.write(
          ' • ${tr(context, 'alertTriggeredDetail', <String, String>{
            'price': formatEgp(_lowestPrice!, locale: lc),
          })}',
        );
      }
    }
    final title = alert.isBackInStock
        ? tr(context, 'backInStockAlertTitle', <String, String>{
            'store': _storeDisplayName(alert),
          })
        : tr(context, 'notifyAt', <String, String>{
            'price': alert.targetPrice == null
                ? tr(context, 'notAvailable')
                : formatEgp(alert.targetPrice!, locale: lc),
          });
    return Card(
      color: triggered ? const Color(0xFFF0FDF4) : Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: triggered
              ? const Color(0xFF86EFAC)
              : const Color(0xFFEAF0F6),
        ),
      ),
      child: ListTile(
        leading: Icon(
          triggered
              ? Icons.notifications_active
              : alert.active
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
          color: triggered
              ? const Color(0xFF15803D)
              : const Color(0xFF475569),
        ),
        title: Text(title),
        subtitle: Text(subtitle.toString()),
        trailing: Text(
          triggered
              ? tr(context, 'alertTriggeredShort')
              : alert.active
                  ? tr(context, 'alertActive')
                  : tr(context, 'alertInactive'),
          style: TextStyle(
            color: triggered
                ? const Color(0xFF15803D)
                : alert.active
                    ? const Color(0xFF15803D)
                    : const Color(0xFF64748B),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Display name for an alert's store: the live store name from the
  /// /compare rows when available, otherwise the raw store slug.
  String _storeDisplayName(PriceAlert alert) {
    final slug = alert.storeSlug;
    if (slug == null) {
      return '';
    }
    for (final price in _comparePrices) {
      if (price.storeSlug == slug) {
        return price.store;
      }
    }
    return slug;
  }
}
