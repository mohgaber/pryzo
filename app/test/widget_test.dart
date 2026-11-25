// Pryzo tests.
//
// - Boots to the home screen in Arabic (default, RTL) with the bottom
//   navigation and the sample-data banner, even with no backend running.
// - Boots in English (LTR) with every key string translated, both via
//   the `initialLocale` override and via a persisted SharedPreferences
//   choice, and switches language at runtime from the AppBar menu.
// - Alerts end-to-end (mock backend): an alert whose target is above
//   the current lowest price shows as triggered; one below it stays
//   active-but-waiting. The mock omits the backend `triggered` field,
//   so this also verifies the app's local evaluation.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pryzo/main.dart';
import 'package:pryzo/models/price_point.dart';
import 'package:pryzo/screens/comparison_screen.dart';
import 'package:pryzo/screens/history_screen.dart';
import 'package:pryzo/services/api_service.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Pryzo boots to the Arabic home screen', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const PryzoApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // AppBar shows the Pryzo title.
    expect(find.text('Pryzo'), findsWidgets);
    // Bottom navigation with the four tabs, in Arabic.
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('المقارنة'), findsOneWidget);
    expect(find.text('الأسعار'), findsOneWidget);
    expect(find.text('المتابعة'), findsOneWidget);
    // Search field is present on the home screen.
    expect(find.byType(TextField), findsOneWidget);
    // Sample-data banner is shown while the backend is unreachable.
    expect(find.textContaining('أسعار تجريبية'), findsOneWidget);
    // Arabic layout is right-to-left.
    expect(
      Directionality.of(tester.element(find.text('الرئيسية'))),
      TextDirection.rtl,
    );
    // A sample price is formatted the Arabic way.
    expect(find.textContaining('جنيه'), findsWidgets);
  });

  testWidgets('Pryzo renders in English with LTR layout', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(
      const PryzoApp(initialLocale: Locale('en')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Prices'), findsOneWidget);
    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.textContaining('Sample prices'), findsOneWidget);
    expect(find.textContaining('EGP'), findsWidgets);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Mobiles'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Home'))),
      TextDirection.ltr,
    );
  });

  testWidgets('Persisted language choice is loaded on boot', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pryzo_locale': 'en',
    });
    await tester.pumpWidget(const PryzoApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('Sample prices'), findsOneWidget);
  });

  testWidgets('Language can be switched at runtime from the AppBar',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const PryzoApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('الرئيسية'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('Sample prices'), findsOneWidget);
    expect(
      await SharedPreferences.getInstance().then(
        (prefs) => prefs.getString('pryzo_locale'),
      ),
      'en',
    );
  });

  testWidgets('Alerts show a triggered state when the price is reached',
      (tester) async {
    final client = MockClient((http.Request request) async {
      final path = request.url.path;
      if (path == '/products/1/history') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'price': 33999,
              'store': 'Jumia',
              'fetched_at': '2026-11-20T08:00:00Z',
            },
            <String, dynamic>{
              'price': 32999,
              'store': 'Jumia',
              'fetched_at': '2026-11-25T08:00:00Z',
            },
          ]),
          200,
        );
      }
      if (path == '/products/1/compare') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'product': <String, dynamic>{
              'id': 1,
              'name': 'PlayStation 5 Console (Disc Edition)',
              'brand': 'Sony',
              'category': 'Gaming',
              'image_url': null,
              'lowest_price': 32999,
              'stores_count': 3,
            },
            'prices': <Map<String, dynamic>>[
              <String, dynamic>{
                'store': 'Jumia',
                'store_slug': 'jumia-eg',
                'price': 32999,
                'currency': 'EGP',
                'in_stock': true,
                'url': 'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
                'fetched_at': '2026-11-25T08:00:00Z',
              },
            ],
            'cheapest': <String, dynamic>{
              'store': 'Jumia',
              'store_slug': 'jumia-eg',
              'price': 32999,
              'currency': 'EGP',
              'in_stock': true,
              'url': 'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
              'fetched_at': '2026-11-25T08:00:00Z',
            },
            'savings_vs_max': 0,
          }),
          200,
        );
      }
      if (path == '/alerts') {
        // NOTE: no `triggered` field — the app must evaluate it locally
        // from the compare data (lowest 32,999).
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'id': 1,
              'product_id': 1,
              'product_name': 'PlayStation 5 Console (Disc Edition)',
              'target_price': 40000,
              'active': true,
              'created_at': '2026-11-25T09:00:00Z',
            },
            <String, dynamic>{
              'id': 2,
              'product_id': 1,
              'product_name': 'PlayStation 5 Console (Disc Edition)',
              'target_price': 10000,
              'active': true,
              'created_at': '2026-11-25T09:00:00Z',
            },
          ]),
          200,
        );
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
    // The alerts section sits below the fold in the test viewport.
    await tester.scrollUntilVisible(
      find.text('تنبيهاتك لهذا المنتج'),
      300,
    );
    await tester.pumpAndSettle();

    // Target 40,000 is above the current lowest (32,999) → triggered.
    expect(find.text('تم تفعيله!'), findsOneWidget);
    expect(find.textContaining('السعر وصل إلى'), findsOneWidget);
    // Target 10,000 is below the current lowest → still waiting.
    expect(find.text('مفعّل'), findsOneWidget);
  });

  testWidgets('Tapping a store price opens the store link; an empty or '
      'malformed URL shows a message instead of crashing', (tester) async {
    final mockLauncher = _MockUrlLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = mockLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    final client = MockClient((http.Request request) async {
      if (request.url.path == '/products/1/compare') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'product': <String, dynamic>{
              'id': 1,
              'name': 'PlayStation 5 Console (Disc Edition)',
              'brand': 'Sony',
              'category': 'Gaming',
              'image_url': null,
              'lowest_price': 32999,
              'stores_count': 3,
            },
            'prices': <Map<String, dynamic>>[
              <String, dynamic>{
                'store': 'Jumia',
                'store_slug': 'jumia-eg',
                'price': 32999,
                'currency': 'EGP',
                'in_stock': true,
                'url':
                    'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
                'fetched_at': '2026-11-25T08:00:00Z',
              },
              <String, dynamic>{
                'store': 'Noon',
                'store_slug': 'noon',
                'price': 34999,
                'currency': 'EGP',
                'in_stock': true,
                'url': '',
                'fetched_at': '2026-11-25T08:00:00Z',
              },
              <String, dynamic>{
                'store': 'Carrefour',
                'store_slug': 'carrefour',
                'price': 35999,
                'currency': 'EGP',
                'in_stock': true,
                'url': 'not-a-url',
                'fetched_at': '2026-11-25T08:00:00Z',
              },
            ],
            'cheapest': <String, dynamic>{
              'store': 'Jumia',
              'store_slug': 'jumia-eg',
              'price': 32999,
              'currency': 'EGP',
              'in_stock': true,
              'url': 'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
              'fetched_at': '2026-11-25T08:00:00Z',
            },
            'savings_vs_max': 3000,
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await _pumpComparison(
      tester,
      ApiService(client: client),
      1,
    );

    // The price text also appears in the header ("lowest price"), so
    // target the one wrapped in the tappable InkWell in the store row.
    Finder priceLink(String priceText) => find.ancestor(
          of: find.text(priceText),
          matching: find.byType(InkWell),
        );

    // The store rows sit below the fold (the advice card and sort
    // control made the screen taller), so scroll the first row into
    // view before tapping — ListView only builds visible rows.
    await tester.scrollUntilVisible(priceLink('32,999 جنيه'), 300);
    await tester.pumpAndSettle();

    // The price is styled as a link (underlined, theme primary colour).
    final priceText = tester.widget<Text>(find.text('32,999 جنيه').last);
    expect(priceText.style?.decoration, TextDecoration.underline);

    // Tapping the Jumia price opens Jumia's product page.
    await tester.tap(priceLink('32,999 جنيه'));
    await tester.pumpAndSettle();
    expect(
      mockLauncher.launchedUrls,
      <String>['https://www.jumia.com.eg/catalog/?q=PlayStation+5'],
    );

    // Tapping a price with an empty URL launches nothing and shows a
    // message instead of crashing.
    await tester.tap(priceLink('34,999 جنيه'));
    await tester.pumpAndSettle();
    expect(mockLauncher.launchedUrls, hasLength(1));
    expect(
      find.text('لا يوجد رابط متاح لهذا المتجر بعد'),
      findsOneWidget,
    );
    // Let that SnackBar dismiss so the next message can show.
    await tester.pump(const Duration(seconds: 5));

    // Same for a malformed URL (no scheme).
    await tester.tap(priceLink('35,999 جنيه'));
    await tester.pumpAndSettle();
    expect(mockLauncher.launchedUrls, hasLength(1));
    expect(find.text('تعذّر فتح رابط المتجر'), findsOneWidget);
  });

  testWidgets('Tapping a sample (offline fallback) price opens the '
      'store search URL', (tester) async {
    final mockLauncher = _MockUrlLauncher();
    final originalLauncher = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = mockLauncher;
    addTearDown(() => UrlLauncherPlatform.instance = originalLauncher);

    // Backend unreachable: every call 404s, so the screen falls back to
    // the bundled sample data for product 1 (PS5).
    final client = MockClient(
      (http.Request request) async => http.Response('not found', 404),
    );

    await _pumpComparison(
      tester,
      ApiService(client: client),
      1,
    );

    // Sample banner confirms this is the offline fallback.
    expect(find.textContaining('أسعار تجريبية'), findsOneWidget);

    // The store rows sit below the fold, so scroll the cheapest row
    // into view before tapping — ListView only builds visible rows.
    await tester.scrollUntilVisible(
      find.ancestor(
        of: find.text('26,999 جنيه'),
        matching: find.byType(InkWell),
      ),
      300,
    );
    await tester.pumpAndSettle();

    // Cheapest sample price is Jumia 26,999, linking to Jumia search.
    await tester.tap(
      find.ancestor(
        of: find.text('26,999 جنيه'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      mockLauncher.launchedUrls,
      <String>[
        'https://www.jumia.com.eg/catalog/?q=PlayStation+5+Slim+1TB',
      ],
    );
  });

  test('PricePoint parses is_sample, missing flag means live', () {
    final flagged = PricePoint.fromJson(<String, dynamic>{
      'price': 10000,
      'store': 'Jumia',
      'fetched_at': '2026-11-20T08:00:00Z',
      'is_sample': true,
    });
    expect(flagged.isSample, isTrue);

    // Older / live responses omit the flag: that means live, not sample.
    final unflagged = PricePoint.fromJson(<String, dynamic>{
      'price': 32999,
      'store': 'Jumia',
      'fetched_at': '2026-11-25T08:00:00Z',
    });
    expect(unflagged.isSample, isFalse);
  });

  testWidgets('A flagged sample history point is labelled sample and '
      'never sets the chart lowest', (tester) async {
    final client = MockClient((http.Request request) async {
      final path = request.url.path;
      if (path == '/products/1/history') {
        return http.Response(
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{
              'price': 10000,
              'store': 'Jumia',
              'fetched_at': '2026-11-20T08:00:00Z',
              'is_sample': true,
            },
            <String, dynamic>{
              'price': 33999,
              'store': 'Jumia',
              'fetched_at': '2026-11-22T08:00:00Z',
            },
            <String, dynamic>{
              'price': 32999,
              'store': 'Jumia',
              'fetched_at': '2026-11-25T08:00:00Z',
              'is_sample': false,
            },
          ]),
          200,
        );
      }
      if (path == '/products/1/compare') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'product': <String, dynamic>{
              'id': 1,
              'name': 'PlayStation 5 Console (Disc Edition)',
              'brand': 'Sony',
              'category': 'Gaming',
              'image_url': null,
              'lowest_price': 32999,
              'stores_count': 3,
            },
            'prices': <Map<String, dynamic>>[
              <String, dynamic>{
                'store': 'Jumia',
                'store_slug': 'jumia-eg',
                'price': 32999,
                'currency': 'EGP',
                'in_stock': true,
                'url': 'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
                'fetched_at': '2026-11-25T08:00:00Z',
              },
            ],
            'cheapest': <String, dynamic>{
              'store': 'Jumia',
              'store_slug': 'jumia-eg',
              'price': 32999,
              'currency': 'EGP',
              'in_stock': true,
              'url': 'https://www.jumia.com.eg/catalog/?q=PlayStation+5',
              'fetched_at': '2026-11-25T08:00:00Z',
            },
            'savings_vs_max': 0,
          }),
          200,
        );
      }
      if (path == '/alerts') {
        return http.Response(jsonEncode(<Map<String, dynamic>>[]), 200);
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

    // Chart lowest is the LIVE lowest (32,999), not the 10,000 sample
    // point — even though the sample point is the cheapest in the list.
    expect(find.text('الأقل: 32,999 جنيه'), findsOneWidget);
    // The chart explains the amber sample dots.
    expect(
      find.text('النقاط الكهرمانية: أسعار تجريبية'),
      findsOneWidget,
    );
    // The sample point itself carries a "تجريبي" badge in the list.
    await tester.scrollUntilVisible(
      find.text('تجريبي'),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.text('تجريبي'), findsOneWidget);
    // The two live points carry no badge.
    expect(find.text('10,000 جنيه'), findsOneWidget);
  });
}

/// Records every URL the app asks url_launcher to open, instead of
/// opening a real browser. Extending (not implementing)
/// [UrlLauncherPlatform] keeps the platform-interface token check happy.
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

/// Pumps [ComparisonScreen] for [productId] in Arabic, as the app does.
Future<void> _pumpComparison(
  WidgetTester tester,
  ApiService api,
  int productId,
) async {
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
        body: ComparisonScreen(api: api, productId: productId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
