// Pryzo — تطبيق مقارنة أسعار المتاجر الإلكترونية المصرية.
//
// Bilingual Arabic (default, RTL) + English (LTR). All user-facing strings
// live in lib/l10n/strings.dart; the language is picked from the AppBar
// menu and persisted with SharedPreferences (see
// lib/l10n/locale_provider.dart). MaterialApp.locale + flutter_localizations
// flip the whole layout direction automatically.
//
// Muted slate theme (#475569 primary, light background). Four screens
// behind a bottom navigation bar: Home/Search, Comparison, Price history
// + alerts, Watchlist. All data comes from the FastAPI backend (see
// lib/services/api_service.dart); when the backend cannot be reached the
// app falls back to clearly-labelled sample data and never crashes.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/locale_provider.dart';
import 'l10n/strings.dart';
import 'screens/comparison_screen.dart';
import 'screens/history_screen.dart';
import 'screens/home_screen.dart';
import 'screens/watchlist_screen.dart';
import 'services/api_service.dart';

void main() {
  runApp(const PryzoApp());
}

class PryzoApp extends StatefulWidget {
  const PryzoApp({super.key, this.initialLocale});

  /// Test-only override: skips loading the persisted language choice.
  final Locale? initialLocale;

  @override
  State<PryzoApp> createState() => _PryzoAppState();
}

class _PryzoAppState extends State<PryzoApp> {
  late final LocaleProvider _localeProvider;

  @override
  void initState() {
    super.initState();
    _localeProvider = LocaleProvider(
      initial: widget.initialLocale ?? const Locale('ar'),
    );
    if (widget.initialLocale == null) {
      _localeProvider.load();
    }
  }

  @override
  void dispose() {
    _localeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _localeProvider,
      builder: (context, _) {
        return MaterialApp(
          title: 'Pryzo',
          debugShowCheckedModeBanner: false,
          locale: _localeProvider.locale,
          supportedLocales: const <Locale>[
            Locale('ar'),
            Locale('en'),
          ],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF475569),
              brightness: Brightness.light,
            ),
            primaryColor: const Color(0xFF475569),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF475569),
              foregroundColor: Colors.white,
              centerTitle: true,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF475569),
                foregroundColor: Colors.white,
              ),
            ),
            cardTheme: const CardThemeData(
              color: Colors.white,
            ),
          ),
          home: MainScreen(localeProvider: _localeProvider),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.localeProvider});

  final LocaleProvider localeProvider;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ApiService _api = ApiService();

  int _currentIndex = 0;

  /// Product shown on the Comparison and History tabs.
  /// Defaults to the first sample product (PlayStation 5).
  int _selectedProductId = 1;

  /// Bumped whenever the Watchlist tab is opened so it reloads.
  int _watchlistNonce = 0;

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  void _onProductSelected(int productId) {
    setState(() {
      _selectedProductId = productId;
    });
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 3) {
        _watchlistNonce++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(
        key: const ValueKey<String>('home'),
        api: _api,
        onProductSelected: _onProductSelected,
      ),
      ComparisonScreen(
        key: ValueKey<String>('compare-$_selectedProductId'),
        api: _api,
        productId: _selectedProductId,
      ),
      HistoryScreen(
        key: ValueKey<String>('history-$_selectedProductId'),
        api: _api,
        productId: _selectedProductId,
        onProductChanged: _onProductSelected,
      ),
      WatchlistScreen(
        key: const ValueKey<String>('watchlist'),
        api: _api,
        refreshNonce: _watchlistNonce,
        onProductSelected: (id) {
          _onProductSelected(id);
          _onTabTapped(1);
        },
      ),
    ];

    final titles = <String>[
      'Pryzo',
      tr(context, 'titleCompare'),
      tr(context, 'titleHistory'),
      tr(context, 'titleWatchlist'),
    ];

    final provider = widget.localeProvider;
    return Scaffold(
      appBar: AppBar(
        // Title only: the logo asset has a white background, so next to
        // the name on the slate AppBar it read as an unclear white
        // square. The wordmark alone is cleaner.
        title: Text(
          _currentIndex == 0 ? 'Pryzo' : titles[_currentIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: <Widget>[
          PopupMenuButton<Locale>(
            icon: const Icon(Icons.language),
            tooltip: tr(context, 'languageTooltip'),
            onSelected: (locale) => provider.setLocale(locale),
            itemBuilder: (context) => <PopupMenuEntry<Locale>>[
              PopupMenuItem<Locale>(
                value: const Locale('ar'),
                child: Row(
                  children: <Widget>[
                    const Text('العربية'),
                    if (provider.isArabic) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(Icons.check, size: 18),
                    ],
                  ],
                ),
              ),
              PopupMenuItem<Locale>(
                value: const Locale('en'),
                child: Row(
                  children: <Widget>[
                    const Text('English'),
                    if (!provider.isArabic) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(Icons.check, size: 18),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // No search action here: the home tab already has the main
          // search bar, and a second search icon in the header was a
          // duplicate.
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF475569),
        unselectedItemColor: const Color(0xFF64748B),
        backgroundColor: Colors.white,
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: tr(context, 'navHome'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.compare_arrows_outlined),
            activeIcon: const Icon(Icons.compare_arrows),
            label: tr(context, 'navCompare'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.show_chart_outlined),
            activeIcon: const Icon(Icons.show_chart),
            label: tr(context, 'navPrices'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bookmark_outline),
            activeIcon: const Icon(Icons.bookmark),
            label: tr(context, 'navWatchlist'),
          ),
        ],
      ),
    );
  }
}
