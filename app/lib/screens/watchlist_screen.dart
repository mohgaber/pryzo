// Watchlist screen: saved products with their current lowest price.
// Swipe a row (or tap the delete icon) to remove it. When the backend is
// unreachable, items saved locally in this session are shown instead.

import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../l10n/strings.dart';
import '../models/product.dart';
import '../models/watchlist_item.dart';
import '../services/api_service.dart';
import '../services/local_store.dart';
import '../utils/format.dart';
import '../widgets/product_image.dart';
import '../widgets/sample_banner.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    required this.api,
    required this.refreshNonce,
    required this.onProductSelected,
  });

  final ApiService api;

  /// Incremented by the parent whenever this tab is opened, so the list
  /// reloads (items may have been added from the comparison screen).
  final int refreshNonce;

  final ValueChanged<int> onProductSelected;

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<WatchlistItem> _items = <WatchlistItem>[];
  bool _loading = true;
  bool _isSample = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WatchlistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshNonce != widget.refreshNonce) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final items = await widget.api.getWatchlist();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _isSample = false;
        _loading = false;
      });
    } catch (_) {
      // Backend unreachable: show items saved locally in this session.
      if (!mounted) {
        return;
      }
      final local = LocalStore.instance.watchlistProductIds.map((id) {
        final product = sampleProducts.firstWhere(
          (p) => p.id == id,
          orElse: () => sampleProducts.first,
        );
        return WatchlistItem(
          id: -id,
          productId: id,
          product: product,
          lowestPrice: product.lowestPrice,
          createdAt: null,
        );
      }).toList();
      setState(() {
        _items = local;
        _isSample = true;
        _loading = false;
      });
    }
  }

  Future<void> _remove(WatchlistItem item) async {
    final removed = item;
    setState(() {
      _items.remove(item);
    });
    try {
      if (item.id > 0) {
        await widget.api.removeFromWatchlist(item.id);
      } else {
        LocalStore.instance.removeFromWatchlist(item.productId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'removedFromWatchlist'))),
        );
      }
    } catch (_) {
      // Removal failed server-side: put the row back and say so.
      if (!mounted) {
        return;
      }
      setState(() {
        _items.add(removed);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'removeFailed')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_isSample && _items.isNotEmpty) ...<Widget>[
            const SampleBanner(),
            const SizedBox(height: 12),
          ],
          Text(
            tr(context, 'titleWatchlist'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            tr(context, 'watchlistHint'),
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr(context, 'watchlistEmpty'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ..._items.map(_watchlistCard),
        ],
      ),
    );
  }

  Widget _watchlistCard(WatchlistItem item) {
    final lc = localeCode(context);
    final Product? product = item.product ??
        sampleProducts
            .where((p) => p.id == item.productId)
            .firstOrNull;
    final name = product?.name ??
        tr(context, 'productFallback',
            <String, String>{'id': item.productId.toString()});
    final brand = product == null
        ? ''
        : '${product.brand} • ${product.category}';
    final lowest = item.lowestPrice ?? product?.lowestPrice;
    return Dismissible(
      key: ValueKey<int>(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _remove(item);
        return false;
      },
      child: Card(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onProductSelected(item.productId),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                ProductImage(imageUrl: product?.imageUrl, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      if (brand.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          brand,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        lowest == null
                            ? tr(context, 'priceUnavailable')
                            : tr(context, 'lowestPricePrefix',
                                <String, String>{
                                  'price': formatEgp(lowest, locale: lc),
                                }),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                      ),
                      if (item.id < 0)
                        Text(
                          tr(context, 'savedLocally'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF92400E),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFF94A3B8),
                  onPressed: () => _remove(item),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
