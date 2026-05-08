import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/scan_state_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/app_recovery_service.dart';
import '../services/debug_log.dart';
import '../services/notification_service.dart';
import '../services/weekly_badge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tutorial_overlay.dart';
import '../widgets/tour_keys.dart';
import '../widgets/weekly_badge_recap_sheet.dart';
import 'analytics_screen.dart';
import 'meal_planner_screen.dart';
import 'home_screen_v2.dart';
import 'grocery_list_screen.dart';
import 'manual_entry_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';
import 'scan_screen.dart';
import 'voice_entry_screen.dart';

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
  bool _checkedWeeklyBadgeRecap = false;
  late final VoidCallback _recoveryListener;

  static const _tabs = [
    HomeScreen(),
    AnalyticsScreen(),
    RecipesScreen(),
    GroceryListScreen(),
    MealPlannerScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _recoveryListener = () {
      if (!mounted || _tabIndex == 0) return;
      setState(() => _tabIndex = 0);
    };
    AppRecoveryService.homeRecoverySignal.addListener(_recoveryListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final showingTutorial = _checkTutorial();
      unawaited(_initNotifications());
      if (!showingTutorial) {
        unawaited(_checkWeeklyBadgeRecap());
      }
    });
  }

  @override
  void dispose() {
    AppRecoveryService.homeRecoverySignal.removeListener(_recoveryListener);
    super.dispose();
  }

  Future<void> _initNotifications() async {
    try {
      await NotificationService.instance.initialize();
      final prefs = ref.read(userPrefsProvider);
      await NotificationService.instance.scheduleReminders(prefs: prefs);
    } catch (e, st) {
      DebugLog.instance.log('Notifications', 'Initialization failed: $e\n$st');
      AppRecoveryService.recover(e, st, source: 'Notifications');
    }
  }

  bool _checkTutorial() {
    final prefs = ref.read(userPrefsProvider);
    if (prefs.onboardingComplete && !prefs.hasSeenAppTutorial) {
      setState(() => _showTutorial = true);
      return true;
    }
    return false;
  }

  void _dismissTutorial() {
    ref.read(userPrefsProvider.notifier).dismissAppTutorial();
    ref.read(showTourProvider.notifier).state = false;
    setState(() => _showTutorial = false);
    unawaited(_checkWeeklyBadgeRecap());
  }

  Future<void> _checkWeeklyBadgeRecap() async {
    try {
      if (_checkedWeeklyBadgeRecap) return;
      _checkedWeeklyBadgeRecap = true;

      final prefs = ref.read(userPrefsProvider);
      if (!prefs.onboardingComplete || !prefs.weeklyBadgeRecapEnabled) return;

      final recap = await WeeklyBadgeService.instance.buildPreviousWeekRecap(
        prefs: prefs,
      );
      if (!mounted) return;

      final latestPrefs = ref.read(userPrefsProvider);
      if (latestPrefs.lastWeeklyBadgeRecapWeek == recap.currentWeekKey) return;

      if (recap.badges.isNotEmpty) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => WeeklyBadgeRecapSheet(recap: recap),
        );
      }

      if (!mounted) return;
      await ref
          .read(userPrefsProvider.notifier)
          .markWeeklyBadgeRecapSeen(recap.currentWeekKey);
    } catch (e, st) {
      DebugLog.instance.log('WeeklyBadges', 'Recap failed: $e\n$st');
      AppRecoveryService.recover(e, st, source: 'Weekly badges');
    }
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
    ref.watch(userPrefsProvider);

    // Watch showTourProvider so we can re-show tour on demand (from Settings).
    ref.listen<bool>(showTourProvider, (_, show) {
      if (show && !_showTutorial) {
        setState(() => _showTutorial = true);
      }
    });

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _tabIndex,
            children: _tabs,
          ),
          bottomNavigationBar: NavigationBar(
            key: TourKeys.navBar,
            selectedIndex: _tabIndex,
            onDestinationSelected: (i) {
              setState(() => _tabIndex = i);
            },
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
                icon: const Icon(Icons.restaurant_menu_outlined),
                selectedIcon:
                    Icon(Icons.restaurant_menu, color: context.primary700),
                label: 'Recipes',
              ),
              NavigationDestination(
                icon: const Icon(Icons.shopping_cart_outlined),
                selectedIcon:
                    Icon(Icons.shopping_cart, color: context.primary700),
                label: 'Groceries',
              ),
              NavigationDestination(
                icon: const Icon(Icons.calendar_month_outlined),
                selectedIcon:
                    Icon(Icons.calendar_month, color: context.primary700),
                label: 'Planner',
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
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── AI Speech (voice) ─────────────────────────────────
                    SizedBox(
                      width: 125,
                      child: FloatingActionButton.extended(                        key: TourKeys.speechFab,                        heroTag: 'voice',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const VoiceEntryScreen()),
                        ),
                        backgroundColor: Colors.white,
                        foregroundColor: context.primary700,
                        elevation: 2,
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.mic, size: 20),
                            Positioned(
                              right: -5,
                              bottom: -5,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: context.primary600,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.auto_awesome,
                                    size: 8, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        label: const Text('AI Speech',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── Manual Log ────────────────────────────────────────
                    SizedBox(
                      width: 125,
                      child: FloatingActionButton.extended(                        key: TourKeys.manualFab,                        heroTag: 'manual',
                        onPressed: _openManualEntry,
                        backgroundColor: Colors.white,
                        foregroundColor: context.primary700,
                        elevation: 2,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: const Text('Manual Log',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── AI Scan ───────────────────────────────────────────
                    SizedBox(
                      width: 125,
                      child: FloatingActionButton.extended(                        key: TourKeys.scanFab,                        heroTag: 'scan',
                        onPressed: _openScan,
                        backgroundColor: context.primary600,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.camera_alt, size: 20),
                            Positioned(
                              right: -5,
                              bottom: -5,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.auto_awesome,
                                    size: 8, color: context.primary600),
                              ),
                            ),
                          ],
                        ),
                        label: const Text('AI Scan',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
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
