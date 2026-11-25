// Pryzo translations — Arabic (default) + English.
//
// Approach: plain Dart maps, one map per language, keyed by a stable
// string id. No code generation step (no `flutter gen-l10n`), so adding a
// string is just adding one line in each language map below — see
// app/README.md ("Adding a new string").
//
// Lookup: [AppStrings.get] (pure, testable) or [tr] (reads the current
// locale from the widget tree). Every user-facing string in the app must
// go through [tr]; product/store names come from data (API or sample
// data) and are shown as-is, never translated.
//
// Categories are a special case: the backend returns English category
// names ("Smartphones") while the bundled sample data uses Arabic ones
// ("موبايلات"). [categoryKey] normalises either spelling to one internal
// key (e.g. "mobiles"), which is what the home screen filters on and
// what `cat_<key>` translates for display.

import 'package:flutter/widgets.dart';

/// Current locale's language code ('ar' or 'en').
String localeCode(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// Translate [key] for the locale in scope, substituting `{name}` tokens
/// from [params] when given.
String tr(BuildContext context, String key, [Map<String, String>? params]) {
  return AppStrings.get(localeCode(context), key, params);
}

/// Normalise a category name from any source (backend English, sample
/// Arabic) to its internal key.
String categoryKey(String raw) {
  switch (raw.trim()) {
    case 'الكل':
    case 'All':
      return 'all';
    case 'موبايلات':
    case 'Smartphones':
      return 'mobiles';
    case 'أجهزة منزلية':
    case 'Home Appliances':
      return 'home';
    case 'تلفزيونات':
    case 'TVs':
      return 'tvs';
    case 'ألعاب':
    case 'Gaming':
      return 'gaming';
    case 'صوتيات':
    case 'Audio':
      return 'audio';
    default:
      return raw;
  }
}

class AppStrings {
  AppStrings._();

  static const Map<String, Map<String, String>> _values =
      <String, Map<String, String>>{
    'ar': <String, String>{
      // App shell / navigation.
      'navHome': 'الرئيسية',
      'navCompare': 'المقارنة',
      'navPrices': 'الأسعار',
      'navWatchlist': 'المتابعة',
      'titleCompare': 'مقارنة الأسعار',
      'titleHistory': 'سجل الأسعار والتنبيهات',
      'titleWatchlist': 'قائمة المتابعة',
      'searchTooltip': 'بحث',
      'languageTooltip': 'اللغة',
      'languageName': 'العربية',
      // Sample-data banner.
      'sampleBanner':
          'أسعار تجريبية — شغّل الخادم (الباك إند) لعرض الأسعار الحية',
      // Short badge shown on an individual sample price point in the
      // history list / chart legend (a live point never gets this badge).
      'sampleBadge': 'تجريبي',
      'chartSampleLegend': 'النقاط الكهرمانية: أسعار تجريبية',
      // Home / search.
      'searchHint': 'دوّر على منتج… مثال: آيفون 15',
      'noResults': 'لا توجد نتائج مطابقة — جرّب كلمة بحث أخرى',
      'priceUnavailable': 'السعر غير متاح',
      'storesCount': '{n} متاجر',
      'cat_all': 'الكل',
      'cat_mobiles': 'موبايلات',
      'cat_home': 'أجهزة منزلية',
      'cat_tvs': 'تلفزيونات',
      'cat_gaming': 'ألعاب',
      'cat_audio': 'صوتيات',
      // Comparison screen.
      'loadFailed': 'تعذّر تحميل بيانات المنتج',
      'lowestPriceLabel': 'أقل سعر: ',
      'inStore': 'في {store}',
      'saveVsMax': 'وفّر {price} عن أغلى سعر',
      'storePricesTitle': 'الأسعار في المتاجر',
      'cheapestBadge': 'الأرخص',
      'inStock': 'متوفر',
      'outOfStock': 'غير متوفر حاليًا',
      'goToStore': 'اذهب للمتجر',
      'noStoreLink': 'لا يوجد رابط متاح لهذا المتجر بعد',
      'couldNotOpenLink': 'تعذّر فتح رابط المتجر',
      'addToWatchlist': 'أضف إلى قائمة المتابعة',
      'saving': 'جارٍ الحفظ…',
      'addedToWatchlist': 'تمت الإضافة إلى قائمة المتابعة',
      'alreadyInWatchlist': 'هذا المنتج موجود بالفعل في قائمة المتابعة',
      'addedLocallyWatchlist':
          'تمت الإضافة إلى قائمة المتابعة (محفوظة محليًا)',
      'alertTitle': 'تنبيه سعر',
      'alertDesc':
          'اكتب السعر الذي تريده، وسننبّهك عندما ينزل السعر إليه أو أقل.',
      'alertHint': 'مثال: {price}',
      'createAlert': 'أنشئ التنبيه',
      'invalidAlertPrice': 'اكتب سعرًا صحيحًا للتنبيه، مثال: 25000',
      'alertCreated':
          'تم إنشاء التنبيه — سننبّهك عند وصول السعر إلى {price}',
      'alertSavedLocally':
          'تم حفظ التنبيه محليًا — سيُفعَّل عند توفر الاتصال بالخادم',
      // History / alerts screen.
      'historyTitle': 'سجل الأسعار',
      'productLabel': 'المنتج',
      'latestPrices': 'أحدث الأسعار المسجلة',
      'noHistory': 'لا يوجد سجل أسعار بعد',
      'yourAlerts': 'تنبيهاتك لهذا المنتج',
      'noAlerts':
          'لا توجد تنبيهات بعد — أنشئ تنبيهًا من شاشة مقارنة الأسعار.',
      'notifyAt': 'نبّهني عند {price}',
      'savedLocally': 'محفوظ محليًا',
      'alertActive': 'مفعّل',
      'alertInactive': 'متوقف',
      'alertTriggeredShort': 'تم تفعيله!',
      'alertTriggeredDetail': 'السعر وصل إلى {price}',
      'productFallback': 'منتج {id}',
      // Price chart.
      'onePrice': 'سعر واحد مسجّل: {price}',
      'chartMax': 'الأعلى: {price}',
      'chartMin': 'الأقل: {price}',
      // Watchlist screen.
      'watchlistHint':
          'اسحب أي منتج لإزالته، أو اضغط عليه لعرض مقارنته.',
      'watchlistEmpty':
          'قائمتك فارغة — أضف منتجات من شاشة مقارنة الأسعار.',
      'removedFromWatchlist': 'تمت الإزالة من قائمة المتابعة',
      'removeFailed': 'تعذّرت الإزالة — تحقق من الاتصال بالخادم',
      'lowestPricePrefix': 'أقل سعر: {price}',
      // Phase 3 — installments / sorting.
      'sortBy': 'ترتيب حسب',
      'sortCash': 'السعر النقدي',
      'sortMonthly': 'القسط الشهري',
      'sortTotal': 'السعر الإجمالي',
      'installmentLabel': 'قسط شهري',
      'installmentLine': 'قسط شهري: {monthly} × {months} شهر',
      'notAvailable': 'غير متوفر',
      // Phase 3 — buy-now-or-wait advice.
      'adviceTitle': 'هل أشتري الآن؟',
      'adviceCurrent': 'السعر الحالي',
      'adviceLow30': 'أدنى سعر (30 يومًا)',
      'adviceAvg30': 'متوسط 30 يومًا',
      'adviceVerdictBuyNow': 'اشتري دلوقتي',
      'adviceVerdictWait': 'استنى شوية',
      'adviceVerdictFair': 'السعر عادي',
      'adviceVerdictUnknown': 'لا توجد بيانات كافية',
      'adviceReasonBuyNow': 'السعر قريب من أدنى سعر في آخر 30 يومًا.',
      'adviceReasonWait': 'السعر أعلى من متوسط آخر 30 يومًا.',
      'adviceReasonFair': 'السعر قريب من متوسط آخر 30 يومًا.',
      'adviceReasonUnknown':
          'لا توجد بيانات حية كافية لتقييم السعر.',
      'adviceUnavailable':
          'نصيحة الشراء غير متاحة حاليًا — تحقق من الاتصال بالخادم.',
      // Phase 3 — shipping / delivery / total.
      'shippingLabel': 'الشحن',
      'freeShipping': 'شحن مجاني',
      'deliveryLabel': 'التوصيل',
      'deliveryDays': '{min}-{max} أيام',
      'deliveryDaysOne': '{days} أيام',
      'totalPriceLabel': 'الإجمالي',
      // Phase 3 — back-in-stock alerts.
      'backInStockNotify': 'نبّهني لما يتوفر',
      'backInStockCreated':
          'سننبّهك عندما يتوفر المنتج في {store}',
      'backInStockSavedLocally':
          'تم حفظ تنبيه التوفر محليًا — سيُفعَّل عند توفر الاتصال بالخادم',
      'backInStockAlertTitle': 'تنبيه توفر في {store}',
      'backInStockNow': 'أصبح متوفرًا في {store}',
      // Phase 3 — coupons.
      'couponsTitle': 'كوبونات الخصم',
      'couponSampleNote': 'كوبون تجريبي — غير مؤكد',
      'couponAfterDiscount': 'السعر بعد الخصم: {price}',
      'couponDiscountPercent': 'خصم {value}%',
      'couponDiscountFixed': 'خصم {value}',
      'couponMinOrder': 'حد أدنى للطلب: {price}',
      'couponExpires': 'ينتهي: {date}',
      // Phase 3 — WhatsApp share.
      'shareButton': 'شارك المقارنة على واتساب',
      'shareCouldNotOpen': 'تعذّر فتح واتساب',
      'shareTitle': 'مقارنة أسعار {product} — Pryzo',
      'shareCheapestLine': 'الأرخص: {store} — {price}',
      'shareSavingsLine': 'وفّر {amount} عن أغلى سعر',
      'shareSampleNote':
          'ملاحظة: هذه أسعار تجريبية، وليست أسعارًا حية.',
    },
    'en': <String, String>{
      // App shell / navigation.
      'navHome': 'Home',
      'navCompare': 'Compare',
      'navPrices': 'Prices',
      'navWatchlist': 'Watchlist',
      'titleCompare': 'Price comparison',
      'titleHistory': 'Price history & alerts',
      'titleWatchlist': 'Watchlist',
      'searchTooltip': 'Search',
      'languageTooltip': 'Language',
      'languageName': 'English',
      // Sample-data banner.
      'sampleBanner':
          'Sample prices — start the backend server to see live prices',
      // Short badge shown on an individual sample price point in the
      // history list / chart legend (a live point never gets this badge).
      'sampleBadge': 'Sample',
      'chartSampleLegend': 'Amber dots: sample prices',
      // Home / search.
      'searchHint': 'Search for a product… e.g. iPhone 15',
      'noResults': 'No matching results — try another search word',
      'priceUnavailable': 'Price unavailable',
      'storesCount': '{n} stores',
      'cat_all': 'All',
      'cat_mobiles': 'Mobiles',
      'cat_home': 'Home appliances',
      'cat_tvs': 'TVs',
      'cat_gaming': 'Gaming',
      'cat_audio': 'Audio',
      // Comparison screen.
      'loadFailed': 'Could not load product data',
      'lowestPriceLabel': 'Lowest price: ',
      'inStore': 'at {store}',
      'saveVsMax': 'Save {price} vs the highest price',
      'storePricesTitle': 'Store prices',
      'cheapestBadge': 'Cheapest',
      'inStock': 'In stock',
      'outOfStock': 'Currently out of stock',
      'goToStore': 'Go to store',
      'noStoreLink': 'No link is available for this store yet',
      'couldNotOpenLink': 'Could not open the store link',
      'addToWatchlist': 'Add to watchlist',
      'saving': 'Saving…',
      'addedToWatchlist': 'Added to watchlist',
      'alreadyInWatchlist': 'This product is already in your watchlist',
      'addedLocallyWatchlist': 'Added to watchlist (saved locally)',
      'alertTitle': 'Price alert',
      'alertDesc':
          'Enter the price you want, and we will notify you when the price drops to it or below.',
      'alertHint': 'e.g. {price}',
      'createAlert': 'Create alert',
      'invalidAlertPrice': 'Enter a valid price for the alert, e.g. 25000',
      'alertCreated':
          'Alert created — we will notify you when the price reaches {price}',
      'alertSavedLocally':
          'Alert saved locally — it will activate when the server is reachable',
      // History / alerts screen.
      'historyTitle': 'Price history',
      'productLabel': 'Product',
      'latestPrices': 'Latest recorded prices',
      'noHistory': 'No price history yet',
      'yourAlerts': 'Your alerts for this product',
      'noAlerts':
          'No alerts yet — create one from the price comparison screen.',
      'notifyAt': 'Notify me at {price}',
      'savedLocally': 'Saved locally',
      'alertActive': 'Active',
      'alertInactive': 'Paused',
      'alertTriggeredShort': 'Triggered!',
      'alertTriggeredDetail': 'Price reached {price}',
      'productFallback': 'Product {id}',
      // Price chart.
      'onePrice': 'One recorded price: {price}',
      'chartMax': 'Highest: {price}',
      'chartMin': 'Lowest: {price}',
      // Watchlist screen.
      'watchlistHint':
          'Swipe a product to remove it, or tap it to see its comparison.',
      'watchlistEmpty':
          'Your list is empty — add products from the price comparison screen.',
      'removedFromWatchlist': 'Removed from watchlist',
      'removeFailed': 'Could not remove — check the server connection',
      'lowestPricePrefix': 'Lowest price: {price}',
      // Phase 3 — installments / sorting.
      'sortBy': 'Sort by',
      'sortCash': 'Cash price',
      'sortMonthly': 'Monthly installment',
      'sortTotal': 'Total price',
      'installmentLabel': 'Monthly installment',
      'installmentLine': 'Monthly: {monthly} × {months} mo',
      'notAvailable': 'Not available',
      // Phase 3 — buy-now-or-wait advice.
      'adviceTitle': 'Buy now or wait?',
      'adviceCurrent': 'Current price',
      'adviceLow30': '30-day low',
      'adviceAvg30': '30-day average',
      'adviceVerdictBuyNow': 'Buy now',
      'adviceVerdictWait': 'Wait a bit',
      'adviceVerdictFair': 'Fair price',
      'adviceVerdictUnknown': 'Not enough data',
      'adviceReasonBuyNow':
          'The price is close to the 30-day low.',
      'adviceReasonWait': 'The price is above the 30-day average.',
      'adviceReasonFair': 'The price is near the 30-day average.',
      'adviceReasonUnknown':
          'Not enough live data to judge the price.',
      'adviceUnavailable':
          'Buying advice is unavailable right now — check the server connection.',
      // Phase 3 — shipping / delivery / total.
      'shippingLabel': 'Shipping',
      'freeShipping': 'Free shipping',
      'deliveryLabel': 'Delivery',
      'deliveryDays': '{min}-{max} days',
      'deliveryDaysOne': '{days} days',
      'totalPriceLabel': 'Total',
      // Phase 3 — back-in-stock alerts.
      'backInStockNotify': 'Notify me when back in stock',
      'backInStockCreated':
          'We will notify you when it is back in stock at {store}',
      'backInStockSavedLocally':
          'Back-in-stock alert saved locally — it will activate when the server is reachable',
      'backInStockAlertTitle': 'Back-in-stock alert at {store}',
      'backInStockNow': 'Back in stock at {store}',
      // Phase 3 — coupons.
      'couponsTitle': 'Discount coupons',
      'couponSampleNote': 'Sample coupon — not confirmed',
      'couponAfterDiscount': 'Price after discount: {price}',
      'couponDiscountPercent': '{value}% off',
      'couponDiscountFixed': '{value} off',
      'couponMinOrder': 'Min. order: {price}',
      'couponExpires': 'Expires: {date}',
      // Phase 3 — WhatsApp share.
      'shareButton': 'Share comparison on WhatsApp',
      'shareCouldNotOpen': 'Could not open WhatsApp',
      'shareTitle': 'Price comparison for {product} — Pryzo',
      'shareCheapestLine': 'Cheapest: {store} — {price}',
      'shareSavingsLine': 'Save {amount} vs the highest price',
      'shareSampleNote':
          'Note: these are sample prices, not live prices.',
    },
  };

  /// Look up [key] for [localeCode] ('ar' falls back to Arabic, anything
  /// else to English). Unknown keys return the key itself so a missing
  /// translation is visible instead of crashing.
  static String get(String localeCode, String key,
      [Map<String, String>? params]) {
    final map = _values[localeCode] ?? _values['en']!;
    var value = map[key] ?? _values['ar']?[key] ?? key;
    if (params != null) {
      for (final entry in params.entries) {
        value = value.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return value;
  }

  /// All supported locale codes.
  static List<String> get supportedCodes => _values.keys.toList();
}
