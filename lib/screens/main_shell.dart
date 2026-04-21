import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scan_state_provider.dart';
import '../theme/app_theme.dart';
import 'analytics_screen.dart';
import 'home_screen_v2.dart';
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

  static const _tabs = [
    HomeScreen(),
    AnalyticsScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

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
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.green100,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppTheme.green700),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: AppTheme.green700),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: AppTheme.green700),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: AppTheme.green700),
            label: 'Settings',
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'manual',
            onPressed: _openManualEntry,
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.green700,
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: _openScan,
            backgroundColor: AppTheme.green600,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan'),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
