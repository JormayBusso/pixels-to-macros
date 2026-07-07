import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../providers/scan_state_provider.dart';
import '../providers/tab_navigation_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../providers/health_sync_provider.dart';
import '../services/app_recovery_service.dart';
import '../services/debug_log.dart';
import '../services/notification_service.dart';
import '../services/weekly_badge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_tutorial_overlay.dart';
import '../widgets/premium_theme_effects.dart';
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

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final showingTutorial = _checkTutorial();
      unawaited(_initNotifications());
      _initHealthSync();
      if (!showingTutorial) {
        unawaited(_checkWeeklyBadgeRecap());
      }
    });
  }

  @override
  void dispose() {
    AppRecoveryService.homeRecoverySignal.removeListener(_recoveryListener);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Re-evaluate meal reminders when returning to the foreground so meals
    // logged in another session (or the passing of a meal window) are
    // reflected, cancelling reminders that no longer apply.
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.instance.refreshMealReminders());
      unawaited(ref.read(healthSyncProvider.notifier).syncNow());
    }
  }

  /// Mirror the persisted Health-sync flag into provider state and, when it is
  /// on, pull the latest weight + active energy so the daily calorie target is
  /// adaptive from the first frame.
  void _initHealthSync() {
    final notifier = ref.read(healthSyncProvider.notifier);
    notifier.loadFromPrefs();
    unawaited(notifier.syncNow());
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
      if (!prefs.onboardingComplete) return;

      // Always evaluate + persist last week's badges to the all-time
      // collection (idempotent), independent of the recap-sheet toggle.
      final recap = await WeeklyBadgeService.instance.evaluateAndAward(
        prefs: prefs,
      );
      if (!mounted) return;

      if (!prefs.weeklyBadgeRecapEnabled) return;

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
    final l10n = AppLocalizations.of(context);
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    ref.watch(userPrefsProvider);

    // Watch showTourProvider so we can re-show tour on demand (from Settings).
    ref.listen<bool>(showTourProvider, (_, show) {
      if (show && !_showTutorial) {
        setState(() => _showTutorial = true);
      }
    });

    return Stack(
      children: [
        Builder(
          builder: (context) {
            // Watch for programmatic tab navigation requests.
            final requestedTab = ref.watch(tabNavigationProvider);
            if (requestedTab >= 0 && requestedTab != _tabIndex) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() => _tabIndex = requestedTab);
                  ref.read(tabNavigationProvider.notifier).state = -1;
                }
              });
            }
            return const SizedBox.shrink();
          },
        ),
        Scaffold(
          body: IndexedStack(
            index: _tabIndex,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                TickerMode(enabled: i == _tabIndex, child: _tabs[i]),
            ],
          ),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                final selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: 9.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  overflow: TextOverflow.ellipsis,
                  color: selected
                      ? (premium
                          ? visualTheme.primaryAccent
                          : context.primary700)
                      : (premium ? visualTheme.onMuted : AppTheme.gray500),
                );
              }),
            ),
            child: MediaQuery.withClampedTextScaling(
              // Keep nav labels at their designed size so longer translations
              // and large text-size settings stay single-line and centred
              // under each icon for every language.
              maxScaleFactor: 1.0,
              child: NavigationBar(
                key: TourKeys.navBar,
                selectedIndex: _tabIndex,
                onDestinationSelected: (i) {
                  FocusScope.of(context).unfocus();
                  setState(() => _tabIndex = i);
                },
                backgroundColor:
                    premium ? visualTheme.navBarColor : Colors.white,
                indicatorColor: Colors.transparent,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.home,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.home,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.bar_chart_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.bar_chart,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.analytics,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.restaurant_menu_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.restaurant_menu,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.recipes,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.shopping_cart_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.shopping_cart,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.groceryList,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.calendar_month_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.calendar_month,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.mealPlanner,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: PremiumFocusRing(
                      enabled: true,
                      radius: 24,
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.settings,
                          color: premium
                              ? visualTheme.primaryAccent
                              : context.primary700),
                    ),
                    label: l10n.settings,
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: _tabIndex == 0
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── AI Scan ───────────────────────────────────────────
                    PremiumMotionSurface(
                      enabled: premium,
                      animate: premium,
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.all(3),
                      borderWidth: 3.4,
                      child: FloatingActionButton.extended(
                        key: TourKeys.scanFab,
                        heroTag: 'scan',
                        onPressed: _openScan,
                        backgroundColor: premium
                            ? visualTheme.cardColor
                            : context.primary600,
                        foregroundColor:
                            premium ? visualTheme.primaryAccent : Colors.white,
                        elevation: premium ? 2 : 4,
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.camera_alt, size: 20),
                            Positioned(
                              right: -5,
                              bottom: -5,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: premium
                                      ? visualTheme.primaryAccent
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.auto_awesome,
                                    size: 8,
                                    color: premium
                                        ? visualTheme.cardColor
                                        : context.primary600),
                              ),
                            ),
                          ],
                        ),
                        label: Text(
                          l10n.aiScan,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── AI Speech (voice) ─────────────────────────────────
                    PremiumMotionSurface(
                      enabled: premium,
                      animate: premium,
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.all(3),
                      borderWidth: 3.4,
                      child: FloatingActionButton.extended(
                        key: TourKeys.speechFab,
                        heroTag: 'voice',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const VoiceEntryScreen()),
                        ),
                        backgroundColor:
                            premium ? visualTheme.cardColor : Colors.white,
                        foregroundColor: premium
                            ? visualTheme.primaryAccent
                            : context.primary700,
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
                                  color: premium
                                      ? visualTheme.primaryAccent
                                      : context.primary600,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.auto_awesome,
                                    size: 8, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        label: Text(
                          l10n.aiSpeech,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── Manual Log ────────────────────────────────────────
                    PremiumMotionSurface(
                      enabled: premium,
                      animate: premium,
                      borderRadius: BorderRadius.circular(18),
                      padding: const EdgeInsets.all(3),
                      borderWidth: 3.4,
                      child: FloatingActionButton.extended(
                        key: TourKeys.manualFab,
                        heroTag: 'manual',
                        onPressed: _openManualEntry,
                        backgroundColor:
                            premium ? visualTheme.cardColor : Colors.white,
                        foregroundColor: premium
                            ? visualTheme.primaryAccent
                            : context.primary700,
                        elevation: 2,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: Text(
                          l10n.manualLog,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
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
