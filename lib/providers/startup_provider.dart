import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diabetes_provider.dart';
import 'locale_provider.dart';
import 'user_prefs_provider.dart';

/// One-time startup data load.
///
/// This is triggered as early as the intro video (see `IntroVideoScreen`) so
/// the locale and user preferences are ready by the time the app gate is
/// shown — the home screen then appears with no loading spinner.
///
/// Only the locale + user preferences are awaited (they decide
/// onboarding-vs-home). Opt-in diabetes/insulin state is loaded in the
/// background and never blocks first paint.
final startupLoadProvider = FutureProvider<void>((ref) async {
  await ref.read(localeProvider.notifier).load();
  await ref
      .read(userPrefsProvider.notifier)
      .load()
      .timeout(const Duration(seconds: 10));
  unawaited(ref.read(insulinSettingsProvider.notifier).load());
  unawaited(ref.read(insulinDoseLogProvider.notifier).load());
});
