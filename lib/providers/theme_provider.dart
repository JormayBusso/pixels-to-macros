import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'user_prefs_provider.dart';

/// Provides a [ThemeData] derived from the user's chosen [AppColorSeed].
/// Automatically rebuilds whenever [userPrefsProvider] changes.
final themeProvider = Provider<ThemeData>((ref) {
  final seed = ref.watch(userPrefsProvider).themeColorSeed;
  return AppTheme.fromSeed(seed);
});
