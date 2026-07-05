import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mascot_type.dart';
import '../theme/app_theme.dart';
import 'user_prefs_provider.dart';

/// Provides a [ThemeData] derived from the user's chosen [AppColorSeed].
/// Automatically rebuilds whenever [userPrefsProvider] changes.
///
/// All color themes (including premium seeds) are available to everyone.
/// Premium themes additionally honour the user's light/dark preference
/// ([UserPreferences.premiumThemeLight]); free themes are always light.
final themeProvider = Provider<ThemeData>((ref) {
  final prefs = ref.watch(userPrefsProvider);
  final seed = effectiveColorSeed(prefs.themeColorSeed);
  final brightness = (seed.isPremium && prefs.premiumThemeLight)
      ? Brightness.light
      : Brightness.dark;
  return AppTheme.fromSeed(seed, brightness: brightness);
});

/// The seed that should actually be applied.
///
/// Premium color themes are unlocked for everyone, so the user's chosen seed is
/// always honoured.
AppColorSeed effectiveColorSeed(AppColorSeed seed) => seed;
