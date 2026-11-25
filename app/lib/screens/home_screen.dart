// Home / search screen: search field, category chips, product cards
// (image or placeholder, name, brand, lowest price, store count).
// Tapping a product opens the comparison screen.
//
// Categories are internal keys (see lib/l10n/strings.dart `categoryKey`)
// so the same chips filter both the Arabic sample data and the backend's
// English category names.

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../l10n/strings.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../utils/format.dart';
import '../widgets/product_image.dart';
import '../widgets/sample_banner.dart';
import 'comparison_screen.dart';

/// Internal category keys; displayed via `cat_<key>` translations.
const List<String> categoryKeys = <String>[
  'all',
  'mobiles',
  'home',
  'tvs',
  'gaming',
  'audio',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.onProductSelected,
  });

  final ApiService api;

  /// Called with the tapped product id so the Comparison tab stays in sync.
  final ValueChanged<int> onProductSelected;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  String _category = 'all';
  List<Product> _products = sampleProducts;
  bool _loading = false;
  bool _isSample = true;
  String? _error;

  /// One page of products from the server.
  static const int _pageSize = 20;

  /// Pagination state for the server-side search (see _load).
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Loads products from the server, one page at a time. [reset]
  /// starts from the first page (new search / new category); otherwise
  /// the next page is appended (the "load more" button). The category
  /// filter runs on the server now, so the app never fetches the whole
  /// catalogue just to filter it.
  Future<void> _load({bool reset = true}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _offset = 0;
      });
    } else {
      if (_loadingMore || !_hasMore) {
        return;
      }
      setState(() {
        _loadingMore = true;
      });
    }
    try {
      final page = await widget.api.searchProducts(
        _searchController.text,
        category: _category,
        limit: _pageSize,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _products =
            reset ? page.items : <Product>[..._products, ...page.items];
        _offset = _products.length;
        _hasMore = _products.length < page.total;
        _isSample = false;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      // Backend unreachable: fall back to bundled sample data, never crash.
      if (!mounted) {
        return;
      }
      setState(() {
        if (reset) {
          _products = sampleSearch(_searchController.text, _category);
          _offset = _products.length;
          _hasMore = false;
          _isSample = true;
        }
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  void _onCategorySelected(String category) {
    setState(() {
      _category = category;
    });
    _load();
  }

  void _openProduct(Product product) {
    widget.onProductSelected(product.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ComparisonScreen(api: widget.api, productId: product.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_isSample) ...<Widget>[
                    const SampleBanner(),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _load(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: tr(context, 'searchHint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _load();
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categoryKeys.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = categoryKeys[index];
                        final selected = category == _category;
                        return ChoiceChip(
                          label: Text(tr(context, 'cat_$category')),
                          selected: selected,
                          onSelected: (_) => _onCategorySelected(category),
                          selectedColor: const Color(0xFF475569),
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF334155),
                          ),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(child: Center(child: Text(_error!)))
          else if (_products.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(context, 'noResults')),
                ),
              ),
            )
          else
            // Lazy: only the product cards on screen are built (and
            // their images decoded), not the whole catalogue at once.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _products.length,
                itemBuilder: (context, index) =>
                    _productCard(_products[index]),
              ),
            ),
          if (_hasMore && !_loading && _products.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Center(
                  child: _loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        )
                      : OutlinedButton(
                          onPressed: () => _load(reset: false),
                          child: Text(tr(context, 'loadMore')),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Translated category label; unknown categories show as-is (data).
  String _categoryLabel(String rawCategory) {
    final key = categoryKey(rawCategory);
    if (!categoryKeys.contains(key)) {
      return rawCategory;
    }
    return tr(context, 'cat_$key');
  }

  Widget _productCard(Product product) {
    final lc = localeCode(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openProduct(product),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              ProductImage(imageUrl: product.imageUrl, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.brand} • ${_categoryLabel(product.category)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          product.lowestPrice == null
                              ? tr(context, 'priceUnavailable')
                              : formatEgp(product.lowestPrice!, locale: lc),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            tr(context, 'storesCount', <String, String>{
                              'n': product.storesCount.toString(),
                            }),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // arrow_forward auto-mirrors with text direction (RTL/LTR).
              const Icon(Icons.arrow_forward, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
