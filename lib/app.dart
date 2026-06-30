import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/app_locale.dart';
import 'core/app_localizations.dart';
import 'providers/locale_provider.dart';
import 'providers/startup_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/intro_video_screen.dart';
import 'services/app_recovery_service.dart';
import 'services/debug_log.dart';

class PixelsToMacrosApp extends ConsumerWidget {
  const PixelsToMacrosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      final theme = ref.watch(themeProvider);
      final fontScale = ref.watch(
        userPrefsProvider.select((p) => p.fontScale),
      );
      final appLanguage = ref.watch(localeProvider);
      return MaterialApp(
        title: 'Pixels to Macros',
        debugShowCheckedModeBanner: false,
        navigatorKey: AppRecoveryService.navigatorKey,
        scaffoldMessengerKey: AppRecoveryService.scaffoldMessengerKey,
        theme: theme,
        locale: appLanguage.locale,
        supportedLocales: AppLanguage.values.map((l) => l.locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Apply user-selected font scale to every screen in the app, and let
        // a tap on any empty area dismiss the keyboard app-wide (so every edit
        // field / settings screen can hide the keyboard without a dedicated
        // button).
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              final focus = FocusManager.instance.primaryFocus;
              if (focus != null && focus.hasFocus) focus.unfocus();
            },
            child: child!,
          ),
        ),
        home: const IntroVideoScreen(nextScreen: _AppGate()),
      );
    } catch (e) {
      DebugLog.instance.log('App', 'Root build error: $e');
      return MaterialApp(
        navigatorKey: AppRecoveryService.navigatorKey,
        scaffoldMessengerKey: AppRecoveryService.scaffoldMessengerKey,
        home: _RecoveryScreen(onRetry: () {
          // Force a full rebuild by invalidating providers
          ref.invalidate(themeProvider);
          ref.invalidate(userPrefsProvider);
        }),
      );
    }
  }
}

/// Gates between onboarding and main app based on user preferences.
///
/// The startup data load is kicked off during the intro video (see
/// [startupLoadProvider]), so it is almost always finished by the time this
/// gate is shown — the home screen appears with no loading spinner.
class _AppGate extends ConsumerWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupLoadProvider);
    return startup.when(
      // The load is triggered during the intro video, so this loading frame is
      // a rare fallback. Show the plain app background (no spinner) so there is
      // never a visible "loading" flash before the home screen.
      loading: () => const Scaffold(),
      error: (e, _) {
        DebugLog.instance.log('App', 'Startup load failed: $e');
        return _RecoveryScreen(
          onRetry: () => ref.invalidate(startupLoadProvider),
        );
      },
      data: (_) {
        final prefs = ref.watch(userPrefsProvider);
        if (!prefs.onboardingComplete) {
          return const OnboardingScreen();
        }
        return const MainShell();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recovery screen — shown when the app fails to start up.
// "Try Again" re-runs _load(). The user never needs to force-quit.
// ─────────────────────────────────────────────────────────────────────────────

class _RecoveryScreen extends StatelessWidget {
  const _RecoveryScreen({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 72,
                  color: Colors.orange,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The app had trouble starting up.\n'
                  'Tap below to try again — your data is safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
