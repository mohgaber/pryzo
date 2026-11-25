/// Formats an EGP amount the Egyptian way, e.g. 26999 -> "26,999 جنيه"
/// in Arabic, "EGP 26,999" in English. Pass the UI locale code
/// ('ar' default) — see `localeCode(context)` in lib/l10n/strings.dart.
String formatEgp(double value, {String locale = 'ar'}) {
  final whole = value.round();
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  if (locale == 'en') {
    return 'EGP ${buffer.toString()}';
  }
  return '${buffer.toString()} جنيه';
}

/// Short date for history rows, e.g. 2026-11-25T08:00:00Z -> "25/11".
String shortDate(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }
  return '${parsed.day}/${parsed.month}';
}

/// Wraps [text] in Unicode left-to-right isolates (U+2066 … U+2069) so a
/// Latin-script product name with numbers ("iPhone 15 128GB") keeps its
/// logical order inside an RTL (Arabic) paragraph, instead of the bidi
/// algorithm shuffling the model number and the capacity. Display-only:
/// the raw name is still used for search, filtering and sharing.
String ltr(String text) => '\u2066$text\u2069';
