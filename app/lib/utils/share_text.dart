import '../l10n/strings.dart';
import '../models/store_price.dart';
import 'format.dart';

/// Builds the WhatsApp share text for a product comparison.
///
/// Pure function (no BuildContext, no network) so it is unit-testable.
/// The text is in the current UI language ([locale] 'ar' or 'en'):
/// product name, store prices cheapest-first (store + price), a
/// cheapest + savings line, and a note when the prices are sample
/// data. Callers URL-encode the result into a `https://wa.me/?text=…`
/// link and open it with url_launcher.
String buildShareText({
  required String locale,
  required String productName,
  required List<StorePrice> pricesCheapestFirst,
  required double savingsVsMax,
  required bool isSample,
}) {
  final lines = <String>[
    AppStrings.get(
      locale,
      'shareTitle',
      <String, String>{'product': productName},
    ),
  ];
  for (final price in pricesCheapestFirst) {
    lines.add(
      '${price.store}: ${formatEgp(price.price, locale: locale)}',
    );
  }
  if (pricesCheapestFirst.isNotEmpty) {
    final cheapest = pricesCheapestFirst.first;
    lines.add(
      AppStrings.get(locale, 'shareCheapestLine', <String, String>{
        'store': cheapest.store,
        'price': formatEgp(cheapest.price, locale: locale),
      }),
    );
  }
  if (savingsVsMax > 0) {
    lines.add(
      AppStrings.get(locale, 'shareSavingsLine', <String, String>{
        'amount': formatEgp(savingsVsMax, locale: locale),
      }),
    );
  }
  if (isSample) {
    lines.add(AppStrings.get(locale, 'shareSampleNote'));
  }
  return lines.join('\n');
}
