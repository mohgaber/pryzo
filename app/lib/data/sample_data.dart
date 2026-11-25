// SAMPLE DATA — clearly labelled, for offline/demo use only.
//
// These products and prices are BUNDLED EXAMPLES, not live prices.
// The UI shows a "أسعار تجريبية" (sample prices) note whenever this data is
// displayed, and the app always tries the FastAPI backend first
// (see [ApiService]); sample data is only a fallback when the backend
// cannot be reached. Never present these values as live prices.

import '../l10n/strings.dart';
import '../models/price_point.dart';
import '../models/product.dart';
import '../models/store_price.dart';

/// Egyptian stores covered by Pryzo (slugs must match the backend seed).
const List<String> sampleStoreNames = <String>[
  'أمازون مصر',
  'جوميا',
  'نون',
  'دريم 2000',
  'متجر فودافون',
  'كارفور',
];

const Map<String, String> sampleStoreSlugs = <String, String>{
  'أمازون مصر': 'amazon',
  'جوميا': 'jumia',
  'نون': 'noon',
  'دريم 2000': 'dream2000',
  'متجر فودافون': 'vodafone',
  'كارفور': 'carrefour',
};

/// The six bundled sample products (same theme as the backend seed data).
const List<Product> sampleProducts = <Product>[
  Product(
    id: 1,
    name: 'بلايستيشن 5 سليم — 1 تيرابايت',
    brand: 'سوني',
    category: 'ألعاب',
    lowestPrice: 26999,
    storesCount: 5,
  ),
  Product(
    id: 2,
    name: 'آيفون 15 — 128 جيجا',
    brand: 'أبل',
    category: 'موبايلات',
    lowestPrice: 41999,
    storesCount: 6,
  ),
  Product(
    id: 3,
    name: 'سامسونج جالاكسي S24 — 256 جيجا',
    brand: 'سامسونج',
    category: 'موبايلات',
    lowestPrice: 34999,
    storesCount: 5,
  ),
  Product(
    id: 4,
    name: 'قلاية هوائية فيليبس 4.1 لتر',
    brand: 'فيليبس',
    category: 'أجهزة منزلية',
    lowestPrice: 5999,
    storesCount: 4,
  ),
  Product(
    id: 5,
    name: 'تلفزيون سامسونج 55 بوصة 4K سمارت',
    brand: 'سامسونج',
    category: 'تلفزيونات',
    lowestPrice: 18999,
    storesCount: 5,
  ),
  Product(
    id: 6,
    name: 'سماعات بلوتوث سوني WH-1000XM5',
    brand: 'سوني',
    category: 'صوتيات',
    lowestPrice: 14999,
    storesCount: 4,
  ),
];

/// Store "find it on the store" search URLs for the sample products.
///
/// Amazon / Jumia use the same patterns as the backend seed (verified
/// stable public search URLs). Noon
/// (`noon.com/egypt-en/search/?q=…`), Dream 2000
/// (`dream2000.com/en/search?q=…&type=product`) and Vodafone eShop
/// (`eshop.vodafone.com.eg/en/list?search=…`) use their stores' own
/// search pages, verified from the stores' public search results.
/// Carrefour Egypt has no verifiable public search-URL pattern, so its
/// entries link to the store homepage instead of a guessed URL.
/// These are search-result pages, not product pages — they let the user
/// find the product on the store; they are NOT live-price sources.
String _storeSearchUrl(String storeSlug, String query) {
  final q = query.replaceAll(' ', '+');
  switch (storeSlug) {
    case 'amazon':
      return 'https://www.amazon.eg/s?k=$q';
    case 'jumia':
      return 'https://www.jumia.com.eg/catalog/?q=$q';
    case 'noon':
      return 'https://www.noon.com/egypt-en/search/?q=$q';
    case 'dream2000':
      return 'https://dream2000.com/en/search?q=$q&type=product';
    case 'vodafone':
      return 'https://eshop.vodafone.com.eg/en/list?search=$q';
    case 'carrefour':
      return 'https://www.carrefouregypt.com';
    default:
      return '';
  }
}

StorePrice _p(String store, double price, String query,
    {bool inStock = true}) {
  final slug = sampleStoreSlugs[store] ?? store;
  return StorePrice(
    store: store,
    storeSlug: slug,
    price: price,
    currency: 'EGP',
    inStock: inStock,
    url: _storeSearchUrl(slug, query),
    fetchedAt: '2026-11-25T08:00:00Z',
  );
}

/// SAMPLE per-store prices, cheapest first per product.
final Map<int, List<StorePrice>> samplePrices = <int, List<StorePrice>>{
  1: <StorePrice>[
    _p('جوميا', 26999, 'PlayStation 5 Slim 1TB'),
    _p('أمازون مصر', 27499, 'PlayStation 5 Slim 1TB'),
    _p('نون', 27999, 'PlayStation 5 Slim 1TB'),
    _p('دريم 2000', 28999, 'PlayStation 5 Slim 1TB'),
    _p('كارفور', 29499, 'PlayStation 5 Slim 1TB', inStock: false),
  ],
  2: <StorePrice>[
    _p('متجر فودافون', 41999, 'iPhone 15 128GB'),
    _p('أمازون مصر', 42499, 'iPhone 15 128GB'),
    _p('جوميا', 42999, 'iPhone 15 128GB'),
    _p('نون', 43499, 'iPhone 15 128GB'),
    _p('دريم 2000', 44499, 'iPhone 15 128GB'),
    _p('كارفور', 44999, 'iPhone 15 128GB'),
  ],
  3: <StorePrice>[
    _p('أمازون مصر', 34999, 'Samsung Galaxy S24 256GB'),
    _p('جوميا', 35499, 'Samsung Galaxy S24 256GB'),
    _p('نون', 35999, 'Samsung Galaxy S24 256GB'),
    _p('متجر فودافون', 36499, 'Samsung Galaxy S24 256GB'),
    _p('كارفور', 36999, 'Samsung Galaxy S24 256GB'),
  ],
  4: <StorePrice>[
    _p('نون', 5999, 'Philips Air Fryer 4.1L'),
    _p('أمازون مصر', 6299, 'Philips Air Fryer 4.1L'),
    _p('جوميا', 6499, 'Philips Air Fryer 4.1L'),
    _p('كارفور', 6799, 'Philips Air Fryer 4.1L'),
  ],
  5: <StorePrice>[
    _p('كارفور', 18999, 'Samsung 55 inch 4K TV'),
    _p('أمازون مصر', 19499, 'Samsung 55 inch 4K TV'),
    _p('جوميا', 19999, 'Samsung 55 inch 4K TV'),
    _p('نون', 20499, 'Samsung 55 inch 4K TV'),
    _p('دريم 2000', 21499, 'Samsung 55 inch 4K TV'),
  ],
  6: <StorePrice>[
    _p('أمازون مصر', 14999, 'Sony WH-1000XM5'),
    _p('جوميا', 15499, 'Sony WH-1000XM5'),
    _p('نون', 15999, 'Sony WH-1000XM5'),
    _p('دريم 2000', 16499, 'Sony WH-1000XM5'),
  ],
};

/// Builds a [CompareResult] from sample data, so the comparison screen can
/// share one code path for live and sample data.
CompareResult sampleCompare(int productId) {
  final product = sampleProducts.firstWhere(
    (p) => p.id == productId,
    orElse: () => sampleProducts.first,
  );
  final prices = List<StorePrice>.from(samplePrices[product.id] ?? <StorePrice>[]);
  prices.sort((a, b) => a.price.compareTo(b.price));
  final cheapest = prices.isEmpty ? null : prices.first;
  final max = prices.isEmpty
      ? 0.0
      : prices.map((p) => p.price).reduce((a, b) => a > b ? a : b);
  final savings = cheapest == null ? 0.0 : max - cheapest.price;
  return CompareResult(
    product: product,
    prices: prices,
    cheapest: cheapest,
    savingsVsMax: savings,
  );
}

/// SAMPLE search over the bundled products (name / brand / category).
/// [category] is an internal category key (see [categoryKey]); 'all'
/// matches every category.
List<Product> sampleSearch(String query, String category) {
  final q = query.trim();
  final wanted = categoryKey(category);
  return sampleProducts.where((p) {
    final matchesCategory =
        wanted == 'all' || categoryKey(p.category) == wanted;
    final matchesQuery = q.isEmpty ||
        p.name.contains(q) ||
        p.brand.contains(q) ||
        p.category.contains(q);
    return matchesCategory && matchesQuery;
  }).toList();
}

/// SAMPLE price history: a gentle downward drift over the last 30 days.
/// Dates are relative to "now" so the chart always looks current.
List<PricePoint> sampleHistory(int productId) {
  final compare = sampleCompare(productId);
  final base = compare.cheapest?.price ?? 10000;
  final store = compare.cheapest?.store ?? 'أمازون مصر';
  final now = DateTime.now();
  final points = <PricePoint>[];
  // 10 points, oldest first, price slowly falling towards today's price.
  for (var i = 9; i >= 0; i--) {
    final day = now.subtract(Duration(days: i * 3));
    final drift = base * (1 + 0.02 * i + (i.isEven ? 0.004 : -0.003));
    points.add(
      PricePoint(
        price: double.parse(drift.toStringAsFixed(0)),
        store: store,
        fetchedAt: day.toIso8601String(),
        // Bundled fallback data is SAMPLE by definition.
        isSample: true,
      ),
    );
  }
  return points;
}
