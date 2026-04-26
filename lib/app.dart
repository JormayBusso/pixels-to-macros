import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/theme_provider.dart';
import 'providers/user_prefs_provider.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';

class PixelsToMacrosApp extends ConsumerWidget {
  const PixelsToMacrosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(userPrefsProvider.notifier).load();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final prefs = ref.watch(userPrefsProvider);
    if (!prefs.onboardingComplete) {
      return const OnboardingScreen();
    }
    return const MainShell();
  }
}
