import 'package:flutter/material.dart';

/// Supported app languages.
enum AppLanguage {
  english('en', 'English', '🇬🇧'),
  polish('pl', 'Polski', '🇵🇱'),
  dutch('nl', 'Nederlands', '🇳🇱'),
  spanish('es', 'Español', '🇪🇸'),
  german('de', 'Deutsch', '🇩🇪');

  const AppLanguage(this.code, this.nativeName, this.flag);

  final String code;
  final String nativeName;
  final String flag;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}
