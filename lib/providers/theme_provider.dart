import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mascot_type.dart';
import '../theme/app_theme.dart';
import 'user_prefs_provider.dart';

/// Provides a [ThemeData] derived from the user's chosen [AppColorSeed].
/// Automatically rebuilds whenever [userPrefsProvider] changes.
///
/// Premium seeds only take effect while the premium pack is unlocked; otherwise
/// the effective theme falls back to the default so premium stays paid-only.
/// The user's stored seed is preserved and re-applies automatically on unlock.
final themeProvider = Provider<ThemeData>((ref) {
  final prefs = ref.watch(userPrefsProvider);
  final seed = effectiveColorSeed(prefs.themeColorSeed, prefs.premiumUnlocked);
  return AppTheme.fromSeed(seed);
});

/// The seed that should actually be applied: premium seeds collapse to
/// [AppColorSeed.green] until [premiumUnlocked] is true.
AppColorSeed effectiveColorSeed(AppColorSeed seed, bool premiumUnlocked) {
  if (seed.isPremium && !premiumUnlocked) return AppColorSeed.green;
  return seed;
}
