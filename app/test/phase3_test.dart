// Pryzo Phase 3 tests.
//
// Unit tests: verdict label/reason keys for every verdict code,
// sort modes (cash / monthly / total, missing data sorts last),
// coupon price-after-discount math, the WhatsApp share-text builder
// (Arabic + English), and the back-in-stock alert creation payload.
// Widget tests: the comparison screen renders advice, installments,
// shipping/total and coupons from the mock backend, offers a
// back-in-stock alert on out-of-stock rows, and hides coupons / shows
// the advice card as unavailable when the backend is unreachable;
// the history screen shows back-in-stock alerts distinctly.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pryzo/l10n/strings.dart';
import 'package:pryzo/models/advice.dart';
import 'package:pryzo/models/coupon.dart';
import 'package:pryzo/models/store_price.dart';
import 'package:pryzo/screens/comparison_screen.dart';
import 'package:pryzo/screens/history_screen.dart';
import 'package:pryzo/services/api_service.dart';
import 'package:pryzo/utils/share_text.dart';
import 'package:pryzo/utils/store_sort.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Builds a mock HTTP 200 response with a UTF-8 JSON body.
/// Plain `jsonResponse(...))` rejects non-Latin-1 bodies,
/// which breaks every mock payload carrying Arabic product/store names.
http.Response jsonResponse(Object data) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

StorePrice row(
  String store,
  double price, {
  String slug = 'store',
  bool inStock = true,
  double? monthly,
  int? months,
  bool monthlySample = false,
  double? shipping,
  bool shippingSample = false,
  int? dMin,
  int? dMax,
  double? total,
}) =>
    StorePrice(
      store: store,
      storeSlug: slug,
      price: price,
      currency: 'EGP',
      inStock: inStock,
      url: 'https://example.com/$slug',
      installmentMonthly: monthly,
      installmentMonths: months,
      installmentIsSample: monthlySample,
      shippingFee: shipping,
      shippingIsSample: shippingSample,
      deliveryDaysMin: dMin,
      deliveryDaysMax: dMax,
      totalPrice: total,
    );

void main() {
  group('Advice verdict rendering', () {
    test('every verdict code maps to a label + reason in both languages',
        () {
      for (final verdict in <String>[
        'buy_now',
        'wait',
        'fair',
        'unknown',
        'something_new',
      ]) {
        final labelKey = verdictLabelKey(verdict);
        final reasonKey = verdictReasonKey(verdict);
        expect(AppStrings.get('ar', labelKey), isNot(labelKey));
        expect(AppStrings.get('en', labelKey), isNot(labelKey));
        expect(AppStrings.get('ar', reasonKey), isNot(reasonKey));
        expect(AppStrings.get('en', reasonKey), isNot(reasonKey));
      }
      expect(AppStrings.get('ar', verdictLabelKey('buy_now')),
          'اشتري دلوقتي');
      expect(AppStrings.get('en', verdictLabelKey('buy_now')), 'Buy now');
      expect(AppStrings.get('ar', verdictLabelKey('wait')), 'استنى شوية');
      expect(AppStrings.get('en', verdictLabelKey('wait')), 'Wait a bit');
      expect(AppStrings.get('ar', verdictLabelKey('fair')), 'السعر عادي');
      expect(AppStrings.get('en', verdictLabelKey('fair')), 'Fair price');
      expect(AppStrings.get('ar', verdictLabelKey('unknown')),
          'لا توجد بيانات كافية');
      // An unknown backend verdict falls back to the unknown label.
      expect(verdictLabelKey('something_new'), 'adviceVerdictUnknown');
    });

    test('PriceAdvice parses nulls gracefully', () {
      final advice = PriceAdvice.fromJson(<String, dynamic>{
        'product_id': 1,
        'current': null,
        'low_30d': null,
        'avg_30d': null,
        'points_used': 0,
        'verdict': 'unknown',
      });
      expect(advice.current, isNull);
      expect(advice.hasData, isFalse);
      final live = PriceAdvice.fromJson(<String, dynamic>{
        'product_id': 1,
        'current': 50000,
        'low_30d': 49000,
        'avg_30d': 52000,
        'points_used': 12,
        'verdict': 'buy_now',
      });
      expect(live.hasData, isTrue);
    });
  });

  group('Store sorting', () {
    final prices = <StorePrice>[
      row('A', 50000, slug: 'a', monthly: 4500, months: 12, shipping: 100),
      row('B', 48000, slug: 'b', monthly: null, shipping: 0),
      row('C', 52000, slug: 'c', monthly: 4200, months: 12, shipping: 500),
      row('D', 47000, slug: 'd', monthly: 5000, months: 10, shipping: null),
    ];

    test('cash mode: cheapest cash price first', () {
      final sorted = sortStorePrices(prices, CompareSortMode.cash);
      expect(sorted.map((p) => p.store).toList(), <String>['D', 'B', 'A', 'C']);
    });

    test('monthly mode: cheapest installment first, no-installment last',
        () {
      final sorted = sortStorePrices(prices, CompareSortMode.monthly);
      expect(sorted.map((p) => p.store).toList(), <String>['C', 'A', 'D', 'B']);
    });

    test('total mode: cheapest total first, unknown total last', () {
      // Totals: A 50100, B 48000 (free shipping), C 52500, D unknown.
      final sorted = sortStorePrices(prices, CompareSortMode.total);
      expect(sorted.map((p) => p.store).toList(), <String>['B', 'A', 'C', 'D']);
    });

    test('explicit total_price beats price + shipping', () {
      final rows = <StorePrice>[
        row('X', 10000, slug: 'x', shipping: 100, total: 9999),
        row('Y', 9000, slug: 'y', shipping: 100),
      ];
      final sorted = sortStorePrices(rows, CompareSortMode.total);
      expect(sorted.first.store, 'Y'); // 9100 < 9999
      expect(row('X', 10000, slug: 'x', shipping: 100, total: 9999)
          .effectiveTotal, 9999);
    });
  });

  group('Coupon math', () {
    test('percent discount', () {
      const coupon = Coupon(
        id: 1,
        store: 'Jumia',
        storeSlug: 'jumia',
        code: 'SAVE10',
        discountType: 'percent',
        discountValue: 10,
      );
      expect(coupon.priceAfterDiscount(50000), 45000);
    });

    test('fixed discount, clamped at zero', () {
      const coupon = Coupon(
        id: 2,
        store: 'Noon',
        storeSlug: 'noon',
        code: 'OFF500',
        discountType: 'fixed',
        discountValue: 500,
      );
      expect(coupon.priceAfterDiscount(50000), 49500);
      expect(coupon.priceAfterDiscount(300), 0);
    });

    test('min_order blocks the discount', () {
      const coupon = Coupon(
        id: 3,
        store: 'Jumia',
        storeSlug: 'jumia',
        code: 'BIG',
        discountType: 'percent',
        discountValue: 20,
        minOrder: 100000,
      );
      expect(coupon.appliesTo(50000), isFalse);
      expect(coupon.priceAfterDiscount(50000), 50000);
      expect(coupon.appliesTo(100000), isTrue);
    });

    test('unknown discount type leaves the price unchanged', () {
      const coupon = Coupon(
        id: 4,
        store: 'X',
        storeSlug: 'x',
        code: '???',
        discountType: 'mystery',
        discountValue: 50,
      );
      expect(coupon.priceAfterDiscount(1000), 1000);
    });

    test('Coupon parses nullable fields gracefully', () {
      final coupon = Coupon.fromJson(<String, dynamic>{
        'id': 5,
        'store': 'Jumia',
        'store_slug': 'jumia',
        'code': 'S1',
        'discount_type': 'percent',
        'discount_value': 5,
      });
      expect(coupon.minOrder, isNull);
      expect(coupon.isSample, isFalse);
      expect(coupon.active, isTrue);
    });
  });

  group('Share text builder', () {
    final prices = <StorePrice>[
      row('جوميا', 50000, slug: 'jumia'),
      row('أمازون مصر', 50500, slug: 'amazon'),
    ];

    test('Arabic: cheapest first, savings line, sample note', () {
      final text = buildShareText(
        locale: 'ar',
        productName: 'بلايستيشن 5',
        pricesCheapestFirst: prices,
        savingsVsMax: 500,
        isSample: true,
      );
      expect(text, contains('بلايستيشن 5'));
      expect(
        text.indexOf('جوميا: 50,000 جنيه'),
        lessThan(text.indexOf('أمازون مصر: 50,500 جنيه')),
      );
      expect(text, contains('الأرخص: جوميا — 50,000 جنيه'));
      expect(text, contains('وفّر 500 جنيه عن أغلى سعر'));
      expect(text, contains('أسعار تجريبية'));
    });

    test('English: no sample note for live prices', () {
      final text = buildShareText(
        locale: 'en',
        productName: 'PlayStation 5',
        pricesCheapestFirst: prices,
        savingsVsMax: 500,
        isSample: false,
      );
      expect(text, contains('Price comparison for PlayStation 5'));
      expect(text, contains('Cheapest: جوميا — EGP 50,000'));
      expect(text, contains('Save EGP 500 vs the highest price'));
      expect(text, isNot(contains('sample')));
    });
  });

  group('Back-in-stock alert payload', () {
    test('POST /alerts carries alert_type + store_slug, no target_price',
        () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((http.Request request) async {
        if (request.url.path == '/alerts' && request.method == 'POST') {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse(<String, dynamic>{
              'id': 9,
              'product_id': 1,
              'target_price': null,
              'active': true,
              'alert_type': 'back_in_stock',
              'store_slug': 'carrefour',
              'triggered': false,
              'created_at': '2026-11-25T10:00:00Z',
            });
        }
        return http.Response('not found', 404);
      });
      final alert = await ApiService(client: client)
          .createBackInStockAlert(1, 'carrefour');
      expect(sentBody, isNotNull);
      expect(sentBody!['product_id'], 1);
      expect(sentBody!['alert_type'], 'back_in_stock');
      expect(sentBody!['store_slug'], 'carrefour');
      expect(sentBody!.containsKey('target_price'), isFalse);
      expect(alert.isBackInStock, isTrue);
      expect(alert.storeSlug, 'carrefour');
      expect(alert.targetPrice, isNull);
      expect(alert.triggered, isFalse);
    });

    test('price alert payload is unchanged (target_price present)', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((http.Request request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse(<String, dynamic>{
            'id': 10,
            'product_id': 1,
            'target_price': 40000,
            'active': true,
            'alert_type': 'price',
            'triggered': false,
          });
      });
      await ApiService(client: client).createAlert(1, 40000);
      expect(sentBody!['alert_type'], 'price');
      expect(sentBody!['target_price'], 40000);
      expect(sentBody!.containsKey('store_slug'), isFalse);
    });
  });

  group('StorePrice Phase 3 parsing', () {
    test('new fields parse, missing fields mean unavailable', () {
      final full = StorePrice.fromJson(<String, dynamic>{
        'store': 'Jumia',
        'store_slug': 'jumia',
        'price': 50000,
        'currency': 'EGP',
        'in_stock': true,
        'url': 'https://example.com',
        'installment_monthly': 4208,
        'installment_months': 12,
        'installment_is_sample': true,
        'shipping_fee': 0,
        'shipping_is_sample': false,
        'delivery_days_min': 2,
        'delivery_days_max': 4,
        'total_price': 50000,
      });
      expect(full.installmentMonthly, 4208);
      expect(full.installmentMonths, 12);
      expect(full.installmentIsSample, isTrue);
      expect(full.shippingFee, 0);
      expect(full.deliveryDaysMax, 4);
      expect(full.effectiveTotal, 50000);

      final bare = StorePrice.fromJson(<String, dynamic>{
        'store': 'Noon',
        'store_slug': 'noon',
        'price': 51000,
        'currency': 'EGP',
        'in_stock': true,
        'url': 'https://example.com',
      });
      expect(bare.installmentMonthly, isNull);
      expect(bare.shippingFee, isNull);
      expect(bare.effectiveTotal, isNull);
    });
  });

  testWidgets('Comparison screen shows advice, installments, shipping, '
      'coupons and a back-in-stock button', (tester) async {
    // Tall viewport so the whole (taller, Phase 3) screen is built and
    // visible at once — no scrolling needed for taps/asserts.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockLauncher = _MockUrlLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = mockLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    final postedBodies = <Map<String, dynamic>>[];
    final client = MockClient((http.Request request) async {
      final path = request.url.path;
      if (path == '/products/1/compare') {
        return jsonResponse(_compareJson());
      }
      if (path == '/products/1/advice') {
        return jsonResponse(<String, dynamic>{
            'product_id': 1,
            'current': 50000,
            'low_30d': 49000,
            'avg_30d': 52000,
            'points_used': 12,
            'verdict': 'buy_now',
          });
      }
      if (path == '/products/1/coupons') {
        return jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'store': 'جوميا',
              'store_slug': 'jumia',
              'code': 'SAVE10',
              'discount_type': 'percent',
              'discount_value': 10,
              'min_order': null,
              'expires_at': '2026-12-31',
              'is_sample': false,
              'active': true,
            },
            <String, dynamic>{
              'id': 2,
              'store': 'أمازون مصر',
              'store_slug': 'amazon',
              'code': 'DEMO5',
              'discount_type': 'percent',
              'discount_value': 5,
              'min_order': null,
              'expires_at': null,
              'is_sample': true,
              'active': true,
            },
          ]);
      }
      if (path == '/alerts' && request.method == 'POST') {
        postedBodies
            .add(jsonDecode(request.body) as Map<String, dynamic>);
        return jsonResponse(<String, dynamic>{
            'id': 9,
            'product_id': 1,
            'target_price': null,
            'active': true,
            'alert_type': 'back_in_stock',
            'store_slug': 'carrefour',
            'triggered': false,
          });
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ComparisonScreen(api: ApiService(client: client), productId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Advice card: verdict badge + 30-day figures.
    expect(find.text('هل أشتري الآن؟'), findsOneWidget);
    expect(find.text('اشتري دلوقتي'), findsOneWidget);
    expect(find.textContaining('49,000 جنيه'), findsOneWidget);
    // Sort control present, default cash.
    expect(find.text('ترتيب حسب'), findsOneWidget);
    expect(find.text('السعر النقدي'), findsOneWidget);
    // Installment line + shipping + free shipping + delivery + total.
    expect(find.textContaining('قسط شهري: 4,167 جنيه × 12 شهر'),
        findsOneWidget);
    expect(find.textContaining('شحن مجاني'), findsOneWidget);
    expect(find.textContaining('2-4 أيام'), findsOneWidget);
    // Coupon code + price after 10% off 50,000 = 45,000.
    expect(find.text('SAVE10'), findsOneWidget);
    expect(find.textContaining('السعر بعد الخصم: 45,000 جنيه'),
        findsOneWidget);
    // Sample coupon is labelled as a sample, never as confirmed.
    expect(find.text('DEMO5'), findsOneWidget);
    expect(find.text('كوبون تجريبي — غير مؤكد'), findsOneWidget);
    // Out-of-stock Carrefour row offers the back-in-stock button.
    expect(find.text('نبّهني لما يتوفر'), findsOneWidget);
    // Share button present.
    expect(find.text('شارك المقارنة على واتساب'), findsOneWidget);

    // Switch sort to monthly: Jumia (4,167) stays first, Amazon (no
    // installment) drops below it; Carrefour (no installment) last.
    await tester.tap(find.text('القسط الشهري'));
    await tester.pumpAndSettle();
    final storeOrder = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => s == 'جوميا' || s == 'أمازون مصر' || s == 'كارفور')
        .toList();
    expect(storeOrder, <String>['جوميا', 'أمازون مصر', 'كارفور']);

    // Tapping the back-in-stock button posts the right payload.
    await tester.tap(find.text('نبّهني لما يتوفر'));
    await tester.pumpAndSettle();
    expect(postedBodies, hasLength(1));
    expect(postedBodies.first['alert_type'], 'back_in_stock');
    expect(postedBodies.first['store_slug'], 'carrefour');
    expect(postedBodies.first.containsKey('target_price'), isFalse);
    expect(
      find.textContaining('سننبّهك عندما يتوفر المنتج في كارفور'),
      findsOneWidget,
    );

    // Share opens wa.me with the comparison text.
    await tester.tap(find.text('شارك المقارنة على واتساب'));
    await tester.pumpAndSettle();
    expect(mockLauncher.launchedUrls, hasLength(1));
    expect(mockLauncher.launchedUrls.first, startsWith('https://wa.me/?text='));
    expect(
      Uri.decodeComponent(
        mockLauncher.launchedUrls.first.split('text=').last,
      ),
      contains('بلايستيشن 5'),
    );
  });

  testWidgets('Offline comparison: advice unavailable, coupons hidden, '
      'no verdict from sample data', (tester) async {
    final client = MockClient(
      (http.Request request) async => http.Response('not found', 404),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ComparisonScreen(api: ApiService(client: client), productId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('أسعار تجريبية'), findsOneWidget);
    expect(find.text('هل أشتري الآن؟'), findsOneWidget);
    expect(find.textContaining('نصيحة الشراء غير متاحة'), findsOneWidget);
    expect(find.text('اشتري دلوقتي'), findsNothing);
    expect(find.text('استنى شوية'), findsNothing);
    expect(find.text('SAVE10'), findsNothing);
    // Sample rows show "not available" for installments/total.
    expect(find.textContaining('غير متوفر'), findsWidgets);
  });

  testWidgets('History screen shows back-in-stock alerts distinctly',
      (tester) async {
    final client = MockClient((http.Request request) async {
      final path = request.url.path;
      if (path == '/products/1/history') {
        return jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              'price': 50000,
              'store': 'Jumia',
              'fetched_at': '2026-11-25T08:00:00Z',
            },
          ]);
      }
      if (path == '/products/1/compare') {
        return jsonResponse(_compareJson());
      }
      if (path == '/alerts') {
        return jsonResponse(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'product_id': 1,
              'product_name': 'PlayStation 5 Console (Disc Edition)',
              'target_price': 10000,
              'active': true,
              'alert_type': 'price',
              'triggered': false,
              'created_at': '2026-11-25T09:00:00Z',
            },
            <String, dynamic>{
              'id': 2,
              'product_id': 1,
              'product_name': 'PlayStation 5 Console (Disc Edition)',
              'target_price': null,
              'active': true,
              'alert_type': 'back_in_stock',
              'store_slug': 'carrefour',
              'triggered': true,
              'created_at': '2026-11-25T09:00:00Z',
            },
          ]);
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HistoryScreen(
            api: ApiService(client: client),
            productId: 1,
            onProductChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('تنبيهاتك لهذا المنتج'),
      300,
    );
    await tester.pumpAndSettle();

    // Back-in-stock alert is shown with its store name, distinctly
    // from the price alert ("نبّهني عند …").
    expect(find.text('تنبيه توفر في كارفور'), findsOneWidget);
    expect(find.textContaining('نبّهني عند 10,000 جنيه'), findsOneWidget);
    // The triggered back-in-stock alert shows as triggered, while the
    // price alert (target 10,000, lowest 50,000) stays active.
    expect(find.text('تم تفعيله!'), findsOneWidget);
    expect(find.text('مفعّل'), findsOneWidget);
  });
}

Map<String, dynamic> _compareJson() {
  Map<String, dynamic> price(
    String store,
    String slug,
    double price, {
    bool inStock = true,
    double? monthly,
    int? months,
    double? shipping,
    int? dMin,
    int? dMax,
  }) =>
      <String, dynamic>{
        'store': store,
        'store_slug': slug,
        'price': price,
        'currency': 'EGP',
        'in_stock': inStock,
        'url': 'https://example.com/$slug',
        'fetched_at': '2026-11-25T08:00:00Z',
        'installment_monthly': monthly,
        'installment_months': months,
        'installment_is_sample': false,
        'shipping_fee': shipping,
        'shipping_is_sample': false,
        'delivery_days_min': dMin,
        'delivery_days_max': dMax,
        'total_price': shipping == null ? null : price + shipping,
      };
  final jumia = price('جوميا', 'jumia', 50000,
      monthly: 4167, months: 12, shipping: 0, dMin: 2, dMax: 4);
  final amazon = price('أمازون مصر', 'amazon', 50500,
      shipping: 100, dMin: 1, dMax: 3);
  final carrefour = price('كارفور', 'carrefour', 52000,
      inStock: false, shipping: 50, dMin: 3, dMax: 5);
  return <String, dynamic>{
    'product': <String, dynamic>{
      'id': 1,
      'name': 'بلايستيشن 5 سليم — 1 تيرابايت',
      'brand': 'سوني',
      'category': 'ألعاب',
      'image_url': null,
      'lowest_price': 50000,
      'stores_count': 3,
    },
    'prices': <Map<String, dynamic>>[jumia, amazon, carrefour],
    'cheapest': jumia,
    'savings_vs_max': 2000,
  };
}

/// Records every URL the app asks url_launcher to open, instead of
/// opening a real browser.
class _MockUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}
