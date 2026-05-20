import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_locale.dart';

const _kLocaleKey = 'app_language_code';

class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier() : super(AppLanguage.english);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    state = AppLanguage.fromCode(code);
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, lang.code);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLanguage>(
  (ref) => LocaleNotifier(),
);
