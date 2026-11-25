// Product comparison screen: product header (image or placeholder,
// name, brand, lowest price), buy-now-or-wait advice card, store table
// sorted by cash price / monthly installment / total price, cheapest
// row highlighted with a "cheapest" badge, savings line, per-store
// stock status, installment + shipping + delivery + total per row,
// per-store coupons, the price itself as a tappable link to the
// store's real product/search page (plus a "Go to store" button),
// add-to-watchlist button, WhatsApp share, a price-alert section and
// per-store back-in-stock alerts for out-of-stock rows.
//
// Advice and coupons come from the backend only: when the backend is
// unreachable the advice card shows "unavailable" (never a verdict
// computed from sample data) and the coupons section is hidden (never
// bundled fake coupons shown as live).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/sample_data.dart';
import '../l10n/strings.dart';
import '../models/advice.dart';
import '../models/coupon.dart';
import '../models/store_price.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../utils/format.dart';
import '../utils/share_text.dart';
import '../utils/store_sort.dart';
import '../widgets/product_image.dart';
import '../widgets/sample_banner.dart';

class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({
    super.key,
    required this.api,
    required this.productId,
  });

  final ApiService api;
  final int productId;

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  final TextEditingController _alertController = TextEditingController();

  CompareResult? _result;
  bool _loading = true;
  bool _isSample = true;
  bool _savingWatchlist = false;
  bool _savingAlert = false;

  /// Buy-now-or-wait advice from GET /advice. Null when the backend
  /// could not be reached (or returned nothing usable): the card then
  /// shows "unavailable" and no verdict is ever invented from sample
  /// data.
  PriceAdvice? _advice;

  /// Coupons from GET /coupons. Empty when the backend could not be
  /// reached: the section is hidden rather than showing fake coupons.
  List<Coupon> _coupons = <Coupon>[];

  CompareSortMode _sortMode = CompareSortMode.cash;

  /// Store slugs with a back-in-stock request currently in flight.
  final Set<String> _notifyingStores = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _alertController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    CompareResult result;
    var isSample = false;
    try {
      result = await widget.api.compareProduct(widget.productId);
    } catch (_) {
      // Backend unreachable: fall back to bundled sample data, never crash.
      result = sampleCompare(widget.productId);
      isSample = true;
    }
    // Advice and coupons are backend-only extras. Each is fetched
    // independently: one failing must not hide the other, and neither
    // failure may invent data from the sample fallback.
    PriceAdvice? advice;
    if (!isSample) {
      try {
        advice = await widget.api.getAdvice(widget.productId);
      } catch (_) {
        advice = null;
      }
    }
    List<Coupon> coupons = <Coupon>[];
    if (!isSample) {
      try {
        coupons = await widget.api.getCoupons(widget.productId);
      } catch (_) {
        coupons = <Coupon>[];
      }
    }
    if (!mounted) {
      return;
    }
    // Lowest price is taken as-is from the API (`cheapest`), which is
    // live-only on the backend. The app never recomputes a lowest over
    // bundled sample data and presents it as live.
    setState(() {
      _result = result;
      _isSample = isSample;
      _advice = advice;
      _coupons = coupons;
      _loading = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addToWatchlist() async {
    final result = _result;
    if (result == null || _savingWatchlist) {
      return;
    }
    // Capture the locale before any await: BuildContext must not be used
    // across async gaps.
    final lc = localeCode(context);
    setState(() {
      _savingWatchlist = true;
    });
    try {
      await widget.api.addToWatchlist(result.product.id);
      _showMessage(AppStrings.get(lc, 'addedToWatchlist'));
    } on ApiException catch (e) {
      if (e.message.contains('409')) {
        // Backend: product is already in the watchlist.
        _showMessage(AppStrings.get(lc, 'alreadyInWatchlist'));
      } else {
        // Offline fallback: keep it in memory for this session.
        LocalStore.instance.addToWatchlist(result.product.id);
        _showMessage(AppStrings.get(lc, 'addedLocallyWatchlist'));
      }
    } catch (_) {
      // Offline fallback: keep it in memory for this session.
      LocalStore.instance.addToWatchlist(result.product.id);
      _showMessage(AppStrings.get(lc, 'addedLocallyWatchlist'));
    } finally {
      if (mounted) {
        setState(() {
          _savingWatchlist = false;
        });
      }
    }
  }

  Future<void> _createAlert() async {
    final result = _result;
    if (result == null || _savingAlert) {
      return;
    }
    final target = double.tryParse(
      _alertController.text.trim().replaceAll(',', ''),
    );
    // Capture the locale before any await: BuildContext must not be used
    // across async gaps.
    final lc = localeCode(context);
    if (target == null || target <= 0) {
      _showMessage(AppStrings.get(lc, 'invalidAlertPrice'));
      return;
    }
    setState(() {
      _savingAlert = true;
    });
    try {
      await widget.api.createAlert(result.product.id, target);
      _alertController.clear();
      _showMessage(AppStrings.get(lc, 'alertCreated', <String, String>{
        'price': formatEgp(target, locale: lc),
      }));
    } catch (_) {
      // Offline fallback: keep the alert in memory for this session.
      LocalStore.instance.addAlert(result.product.id, target);
      _alertController.clear();
      _showMessage(AppStrings.get(lc, 'alertSavedLocally'));
    } finally {
      if (mounted) {
        setState(() {
          _savingAlert = false;
        });
      }
    }
  }

  /// Back-in-stock alert for one out-of-stock store row: POST /alerts
  /// with alert_type 'back_in_stock' + store_slug, no target price.
  /// Offline fallback keeps it in the local store like price alerts.
  Future<void> _createBackInStockAlert(StorePrice price) async {
    final result = _result;
    if (result == null || _notifyingStores.contains(price.storeSlug)) {
      return;
    }
    final lc = localeCode(context);
    setState(() {
      _notifyingStores.add(price.storeSlug);
    });
    try {
      await widget.api.createBackInStockAlert(
        result.product.id,
        price.storeSlug,
      );
      _showMessage(AppStrings.get(lc, 'backInStockCreated', <String, String>{
        'store': price.store,
      }));
    } catch (_) {
      LocalStore.instance.addBackInStockAlert(
        result.product.id,
        price.storeSlug,
      );
      _showMessage(AppStrings.get(lc, 'backInStockSavedLocally'));
    } finally {
      if (mounted) {
        setState(() {
          _notifyingStores.remove(price.storeSlug);
        });
      }
    }
  }

  /// Shares the comparison on WhatsApp: builds the text in the
  /// current language and opens wa.me with it, via url_launcher.
  Future<void> _shareOnWhatsApp() async {
    final result = _result;
    if (result == null) {
      return;
    }
    final lc = localeCode(context);
    final text = buildShareText(
      locale: lc,
      productName: result.product.name,
      pricesCheapestFirst:
          sortStorePrices(result.prices, CompareSortMode.cash),
      savingsVsMax: result.savingsVsMax,
      isSample: _isSample,
    );
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(text)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage(AppStrings.get(lc, 'shareCouldNotOpen'));
    }
  }

  /// Opens the store's real product/search page in the external browser.
  /// Empty or malformed URLs show a message instead of crashing.
  Future<void> _goToStore(StorePrice price) async {
    // Capture the locale before any await: BuildContext must not be used
    // across async gaps.
    final lc = localeCode(context);
    final url = price.url.trim();
    if (url.isEmpty) {
      _showMessage(AppStrings.get(lc, 'noStoreLink'));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showMessage(AppStrings.get(lc, 'couldNotOpenLink'));
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage(AppStrings.get(lc, 'couldNotOpenLink'));
    }
  }

  /// Coupons grouped by store slug, for the per-row coupon display.
  Map<String, List<Coupon>> get _couponsByStore {
    final map = <String, List<Coupon>>{};
    for (final coupon in _coupons) {
      (map[coupon.storeSlug] ??= <Coupon>[]).add(coupon);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final lc = localeCode(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'titleCompare')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : result == null
              ? Center(child: Text(tr(context, 'loadFailed')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (_isSample) ...<Widget>[
                        const SampleBanner(),
                        const SizedBox(height: 12),
                      ],
                      _productHeader(result, lc),
                      const SizedBox(height: 16),
                      _adviceCard(lc),
                      const SizedBox(height: 16),
                      if (result.savingsVsMax > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF86EFAC),
                            ),
                          ),
                          child: Text(
                            tr(context, 'saveVsMax', <String, String>{
                              'price': formatEgp(result.savingsVsMax,
                                  locale: lc),
                            }),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        tr(context, 'storePricesTitle'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _sortControl(lc),
                      const SizedBox(height: 8),
                      ...sortStorePrices(result.prices, _sortMode)
                          .map(
                            (price) => _storeRow(
                              price,
                              price.storeSlug ==
                                  result.cheapest?.storeSlug,
                              lc,
                            ),
                          ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _savingWatchlist ? null : _addToWatchlist,
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: Text(
                            _savingWatchlist
                                ? tr(context, 'saving')
                                : tr(context, 'addToWatchlist'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _shareOnWhatsApp,
                          icon: const Icon(Icons.share_outlined),
                          label: Text(tr(context, 'shareButton')),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _alertSection(result, lc),
                    ],
                  ),
                ),
    );
  }

  Widget _productHeader(CompareResult result, String lc) {
    final cheapest = result.cheapest;
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEAF0F6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ProductImage(imageUrl: result.product.imageUrl, size: 76),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ltr(result.product.name),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${result.product.brand} • ${result.product.category}',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        tr(context, 'lowestPriceLabel'),
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      Flexible(
                        child: Text(
                          cheapest == null
                              ? tr(context, 'priceUnavailable')
                              : formatEgp(cheapest.price, locale: lc),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (cheapest != null) ...<Widget>[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            tr(context, 'inStore', <String, String>{
                              'store': cheapest.store,
                            }),
                            style:
                                const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Buy-now-or-wait advice card (below the header). Shows the live
  /// current price, 30-day low and 30-day average plus a verdict badge
  /// with a one-line reason. When the backend was unreachable
  /// ([_advice] is null) it shows "unavailable" — a verdict is never
  /// computed from sample data.
  Widget _adviceCard(String lc) {
    final advice = _advice;
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEAF0F6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.lightbulb_outline,
                    color: Color(0xFF475569)),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'adviceTitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (advice == null)
              Text(
                tr(context, 'adviceUnavailable'),
                style: const TextStyle(color: Color(0xFF64748B)),
              )
            else ...<Widget>[
              _adviceLine(
                tr(context, 'adviceCurrent'),
                advice.current == null
                    ? tr(context, 'notAvailable')
                    : formatEgp(advice.current!, locale: lc),
              ),
              _adviceLine(
                tr(context, 'adviceLow30'),
                advice.low30d == null
                    ? tr(context, 'notAvailable')
                    : formatEgp(advice.low30d!, locale: lc),
              ),
              _adviceLine(
                tr(context, 'adviceAvg30'),
                advice.avg30d == null
                    ? tr(context, 'notAvailable')
                    : formatEgp(advice.avg30d!, locale: lc),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _verdictColor(advice.verdict),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  AppStrings.get(lc, verdictLabelKey(advice.verdict)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.get(lc, verdictReasonKey(advice.verdict)),
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _adviceLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _verdictColor(String verdict) {
    switch (verdict) {
      case 'buy_now':
        return const Color(0xFF15803D);
      case 'wait':
        return const Color(0xFFB45309);
      case 'fair':
        return const Color(0xFF475569);
      case 'unknown':
      default:
        return const Color(0xFF64748B);
    }
  }

  /// Sort toggle: cash price (default) / monthly installment / total.
  Widget _sortControl(String lc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          tr(context, 'sortBy'),
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        const SizedBox(height: 6),
        SegmentedButton<CompareSortMode>(
          segments: <ButtonSegment<CompareSortMode>>[
            ButtonSegment<CompareSortMode>(
              value: CompareSortMode.cash,
              label: Text(tr(context, 'sortCash')),
            ),
            ButtonSegment<CompareSortMode>(
              value: CompareSortMode.monthly,
              label: Text(tr(context, 'sortMonthly')),
            ),
            ButtonSegment<CompareSortMode>(
              value: CompareSortMode.total,
              label: Text(tr(context, 'sortTotal')),
            ),
          ],
          selected: <CompareSortMode>{_sortMode},
          onSelectionChanged: (selected) {
            setState(() {
              _sortMode = selected.first;
            });
          },
        ),
      ],
    );
  }

  /// Small amber "sample" badge, as used for sample price points.
  Widget _sampleBadge(String lc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Text(
        AppStrings.get(lc, 'sampleBadge'),
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _storeRow(StorePrice price, bool isCheapest, String lc) {
    final coupons = _couponsByStore[price.storeSlug] ?? <Coupon>[];
    final delivery = _deliveryText(price, lc);
    final total = price.effectiveTotal;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isCheapest ? const Color(0xFFF0FDF4) : Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCheapest
              ? const Color(0xFF86EFAC)
              : const Color(0xFFEAF0F6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              price.store,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (isCheapest) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF15803D),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tr(context, 'cheapestBadge'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        price.inStock
                            ? tr(context, 'inStock')
                            : tr(context, 'outOfStock'),
                        style: TextStyle(
                          fontSize: 12,
                          color: price.inStock
                              ? const Color(0xFF15803D)
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    // The price itself is the link: tapping it opens the
                    // store's product/search page in the external browser
                    // (same as the "Go to store" button below it). Underlined
                    // and in the theme's primary colour so it reads as
                    // tappable. Applies to live and sample rows alike;
                    // _goToStore shows a message for an empty/malformed URL
                    // instead of crashing.
                    InkWell(
                      onTap: () => _goToStore(price),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Text(
                          formatEgp(price.price, locale: lc),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => _goToStore(price),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(tr(context, 'goToStore')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Monthly installment (sample installments get the badge).
            Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    price.installmentMonthly == null
                        ? '${tr(context, 'installmentLabel')}: '
                            '${tr(context, 'notAvailable')}'
                        : AppStrings.get(
                            lc,
                            'installmentLine',
                            <String, String>{
                              'monthly': formatEgp(
                                price.installmentMonthly!,
                                locale: lc,
                              ),
                              'months': (price.installmentMonths ?? 0)
                                  .toString(),
                            },
                          ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (price.installmentMonthly != null &&
                    price.installmentIsSample) ...<Widget>[
                  const SizedBox(width: 6),
                  _sampleBadge(lc),
                ],
              ],
            ),
            const SizedBox(height: 4),
            // Shipping fee + delivery estimate + total price.
            Row(
              children: <Widget>[
                Text(
                  '${tr(context, 'shippingLabel')}: ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                Flexible(
                  child: Text(
                    price.shippingFee == null
                        ? tr(context, 'notAvailable')
                        : price.shippingFee == 0
                            ? tr(context, 'freeShipping')
                            : formatEgp(price.shippingFee!, locale: lc),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (price.shippingFee != null &&
                    price.shippingIsSample) ...<Widget>[
                  const SizedBox(width: 6),
                  _sampleBadge(lc),
                ],
                if (delivery != null) ...<Widget>[
                  const SizedBox(width: 12),
                  Text(
                    '${tr(context, 'deliveryLabel')}: $delivery',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Text(
                  '${tr(context, 'totalPriceLabel')}: ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  total == null
                      ? tr(context, 'notAvailable')
                      : formatEgp(total, locale: lc),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            // Per-store coupons (with price after discount).
            for (final coupon in coupons) ...<Widget>[
              const SizedBox(height: 6),
              _couponChip(coupon, price, lc),
            ],
            // Back-in-stock alert for out-of-stock rows.
            if (!price.inStock) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _notifyingStores.contains(price.storeSlug)
                    ? null
                    : () => _createBackInStockAlert(price),
                icon: const Icon(Icons.notifications_outlined, size: 18),
                label: Text(tr(context, 'backInStockNotify')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Delivery estimate text, e.g. "2-4 أيام" / "2-4 days", or null
  /// when the backend reported no delivery window.
  String? _deliveryText(StorePrice price, String lc) {
    final min = price.deliveryDaysMin;
    final max = price.deliveryDaysMax;
    if (min == null && max == null) {
      return null;
    }
    if (min != null && max != null && min != max) {
      return AppStrings.get(lc, 'deliveryDays', <String, String>{
        'min': min.toString(),
        'max': max.toString(),
      });
    }
    final days = (min ?? max)!;
    return AppStrings.get(lc, 'deliveryDaysOne', <String, String>{
      'days': days.toString(),
    });
  }

  /// One coupon for this store row: code + discount + price after
  /// applying it (only when the order meets the coupon's minimum).
  /// Sample coupons are labelled clearly and never presented as a
  /// confirmed working code.
  Widget _couponChip(Coupon coupon, StorePrice price, String lc) {
    final discountText = coupon.discountType == 'percent'
        ? AppStrings.get(lc, 'couponDiscountPercent', <String, String>{
            'value': coupon.discountValue % 1 == 0
                ? coupon.discountValue.toInt().toString()
                : coupon.discountValue.toString(),
          })
        : AppStrings.get(lc, 'couponDiscountFixed', <String, String>{
            'value': formatEgp(coupon.discountValue, locale: lc),
          });
    final applies = coupon.appliesTo(price.price);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_offer_outlined, size: 16),
              const SizedBox(width: 6),
              Text(
                coupon.code,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  discountText,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (coupon.isSample) ...<Widget>[
                const SizedBox(width: 6),
                _sampleBadge(lc),
              ],
            ],
          ),
          if (coupon.isSample) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              tr(context, 'couponSampleNote'),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF92400E),
              ),
            ),
          ],
          if (applies) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              tr(context, 'couponAfterDiscount', <String, String>{
                'price': formatEgp(
                  coupon.priceAfterDiscount(price.price),
                  locale: lc,
                ),
              }),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF15803D),
              ),
            ),
          ],
          if (coupon.minOrder != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              tr(context, 'couponMinOrder', <String, String>{
                'price': formatEgp(coupon.minOrder!, locale: lc),
              }),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
          if (coupon.expiresAt != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              tr(context, 'couponExpires', <String, String>{
                'date': coupon.expiresAt!,
              }),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alertSection(CompareResult result, String lc) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFEAF0F6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.notifications_outlined,
                    color: Color(0xFF475569)),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'alertTitle'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(context, 'alertDesc'),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _alertController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: tr(context, 'alertHint', <String, String>{
                        'price': (result.cheapest == null
                                ? 25000
                                : result.cheapest!.price.round() - 1000)
                            .toString(),
                      }),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _savingAlert ? null : _createAlert,
                  child: Text(_savingAlert
                      ? tr(context, 'saving')
                      : tr(context, 'createAlert')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
