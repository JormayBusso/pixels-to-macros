import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/theme_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
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
      return MaterialApp(
        title: 'Pixels to Macros',
        debugShowCheckedModeBanner: false,
        theme: theme,
        // Apply user-selected font scale to every screen in the app
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: child!,
        ),
        home: const _AppGate(),
      );
    } catch (e) {
      DebugLog.instance.log('App', 'Root build error: $e');
      return MaterialApp(
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
class _AppGate extends ConsumerStatefulWidget {
  const _AppGate();

  @override
  ConsumerState<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<_AppGate> {
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _loadFailed = false; });
    try {
      await ref
          .read(userPrefsProvider.notifier)
          .load()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      DebugLog.instance.log('App', 'Startup load failed: $e');
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadFailed) {
      return _RecoveryScreen(onRetry: _load);
    }

    final prefs = ref.watch(userPrefsProvider);
    if (!prefs.onboardingComplete) {
      return const OnboardingScreen();
    }
    return const MainShell();
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
