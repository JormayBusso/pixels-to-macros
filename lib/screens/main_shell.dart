import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/history_provider.dart';
import '../providers/scan_state_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tutorial_overlay.dart';
import 'analytics_screen.dart';
import 'home_screen_v2.dart';
import 'grocery_list_screen.dart';
import 'history_screen.dart';
import 'manual_entry_screen.dart';
import 'settings_screen.dart';
import 'scan_screen.dart';

/// Root shell with bottom navigation: Home / Analytics / History / Settings.
///
/// Scan and Manual Entry open as full-screen pushes.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tabIndex = 0;
  bool _showTutorial = false;

  static const _tabs = [
    HomeScreen(),
    AnalyticsScreen(),
    GroceryListScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
    });
  }

  void _checkTutorial() {
    final prefs = ref.read(userPrefsProvider);
    if (prefs.onboardingComplete && !prefs.hasSeenAppTutorial) {
      setState(() => _showTutorial = true);
    }
  }

  void _dismissTutorial() {
    ref.read(userPrefsProvider.notifier).dismissAppTutorial();
    setState(() => _showTutorial = false);
  }

  void _openScan() {
    ref.read(scanStateProvider.notifier).reset();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
  }

  void _openManualEntry() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManualEntryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(historyProvider);
    final scanCount = historyState.scans.length;

    return Stack(
      children: [
        Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: context.primary100,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: context.primary700),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: context.primary700),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart, color: context.primary700),
            label: 'Groceries',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: scanCount > 0,
              label: Text('$scanCount'),
              child: const Icon(Icons.history_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: scanCount > 0,
              label: Text('$scanCount'),
              child: Icon(Icons.history, color: context.primary700),
            ),
            label: 'History',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: context.primary700),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'manual',
            onPressed: _openManualEntry,
            backgroundColor: Colors.white,
            foregroundColor: context.primary700,
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: _openScan,
            backgroundColor: context.primary600,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan'),
          ),
        ],
      )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    ),
        if (_showTutorial)
          AppTutorialOverlay(
            onDismiss: _dismissTutorial,
            onNavigateToTab: (i) => setState(() => _tabIndex = i),
          ),
      ],
    );
  }
}
