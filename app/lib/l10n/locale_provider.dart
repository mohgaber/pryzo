// Runtime language choice (Arabic default, English optional).
//
// The choice is persisted in SharedPreferences under [prefsKey] so the
// app reopens in the language the user last picked. The provider is held
// by PryzoApp and drives MaterialApp.locale; switching notifies
// listeners and the whole UI rebuilds (MaterialApp + flutter_localizations
// also flip the layout direction: RTL for Arabic, LTR for English).

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  LocaleProvider({Locale initial = const Locale('ar')}) : _locale = initial;

  static const String prefsKey = 'pryzo_locale';

  Locale _locale;

  Locale get locale => _locale;

  bool get isArabic => _locale.languageCode == 'ar';

  /// Loads the persisted choice (if any). No-op when nothing was saved —
  /// Arabic stays the default.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(prefsKey);
    if ((code == 'ar' || code == 'en') && code != _locale.languageCode) {
      _locale = Locale(code!);
      notifyListeners();
    }
  }

  /// Switches language now and persists the choice.
  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) {
      return;
    }
    _locale = Locale(locale.languageCode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, _locale.languageCode);
  }
}
