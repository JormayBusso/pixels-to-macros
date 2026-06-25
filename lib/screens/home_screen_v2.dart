import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/nutrition_goal.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/recommendations_provider.dart';
import '../providers/streak_provider.dart';
import '../providers/scroll_trigger_provider.dart';
import '../providers/tab_navigation_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../services/scan_media_resolver.dart';
import '../theme/app_theme.dart';
import '../widgets/drink_sheet.dart';
import '../widgets/goal_mascot_widget.dart';
import '../widgets/premium_theme_effects.dart';
import '../widgets/tour_keys.dart';
import '../widgets/weekly_challenges_card.dart';
import 'body_map_screen.dart';
import 'nutrition_dashboard_screen.dart';
import 'scan_detail_screen.dart';

/// Dashboard showing today's calorie intake, progress ring,
/// recent scans, and food breakdown.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _initialLoading = true;
  final _scrollController = ScrollController();
  // Private keys removed — TourKeys.hydrationCard / TourKeys.recommendationsCard
  // are used directly so AppTutorialOverlay can measure them.
  int _lastHydrationTrigger = 0;
  int _lastRecommendationsTrigger = 0;

  // Multi-select state for bulk deletes.
  final Set<int> _selectedFoodIds = <int>{};
  final Set<int> _selectedScanIds = <int>{};
  // Selection MODE can be active with zero items selected — entered via the
  // card's long-press or the section header's select affordance.
  bool _foodSelectionMode = false;
  bool _scanSelectionMode = false;

  bool get _foodSelecting => _foodSelectionMode || _selectedFoodIds.isNotEmpty;
  bool get _scanSelecting => _scanSelectionMode || _selectedScanIds.isNotEmpty;

  void _enterFoodSelection() => setState(() => _foodSelectionMode = true);
  void _exitFoodSelection() => setState(() {
        _foodSelectionMode = false;
        _selectedFoodIds.clear();
      });
  void _enterScanSelection() => setState(() => _scanSelectionMode = true);
  void _exitScanSelection() => setState(() {
        _scanSelectionMode = false;
        _selectedScanIds.clear();
      });

  void _toggleFoodSelected(int id) {
    setState(() {
      if (!_selectedFoodIds.add(id)) _selectedFoodIds.remove(id);
    });
  }

  void _toggleScanSelected(int id) {
    setState(() {
      if (!_selectedScanIds.add(id)) _selectedScanIds.remove(id);
    });
  }

  Future<void> _confirmDeleteSelected({
    required int count,
    required Future<void> Function() onConfirm,
  }) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteSelectedQuestion(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  Future<void> _deleteSelectedFoods() async {
    final ids = _selectedFoodIds.toList();
    if (ids.isEmpty) return;
    await DatabaseService.instance.deleteDetectedFoods(ids);
    await ref.read(dailyIntakeProvider.notifier).load();
    await ref.read(historyProvider.notifier).load();
    if (mounted) {
      setState(() {
        _selectedFoodIds.clear();
        _foodSelectionMode = false;
      });
    }
  }

  Future<void> _deleteSelectedScans() async {
    final ids = _selectedScanIds.toList();
    if (ids.isEmpty) return;
    await ref.read(historyProvider.notifier).deleteScans(ids);
    if (mounted) {
      setState(() {
        _selectedScanIds.clear();
        _scanSelectionMode = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await ref.read(userPrefsProvider.notifier).load();
    await ref.read(dailyIntakeProvider.notifier).load();
    await ref.read(historyProvider.notifier).load();
    final scans = ref.read(historyProvider).scans;
    final newestId = scans.isEmpty ? 0 : (scans.first.id ?? 0);
    if (newestId > 0) {
      await ref.read(userPrefsProvider.notifier).markHistorySeen(newestId);
    }
    await ref.read(streakProvider.notifier).load();
    if (mounted) setState(() => _initialLoading = false);
  }

  void _showEditFoodSheet(BuildContext context, DetectedFood food) {
    final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
    final calController =
        TextEditingController(text: avgCal.round().toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit "${food.label}"',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: calController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Calories (kcal)',
                border: OutlineInputBorder(),
                suffixText: 'kcal',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      if (food.id != null) {
                        await DatabaseService.instance
                            .deleteDetectedFood(food.id!);
                        await ref.read(dailyIntakeProvider.notifier).load();
                        await ref.read(historyProvider.notifier).load();
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 18),
                    label: Text(AppLocalizations.of(context).remove,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final newCal =
                          double.tryParse(calController.text) ?? avgCal;
                      if (food.id != null) {
                        // Keep the same ± spread ratio
                        final ratio = avgCal > 0 ? newCal / avgCal : 1.0;
                        await DatabaseService.instance.updateDetectedFood(
                          food.id!,
                          label: food.label,
                          caloriesMin: food.caloriesMin * ratio,
                          caloriesMax: food.caloriesMax * ratio,
                        );
                        await ref.read(dailyIntakeProvider.notifier).load();
                        await ref.read(historyProvider.notifier).load();
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(AppLocalizations.of(context).save),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPrefsProvider);
    final intake = ref.watch(dailyIntakeProvider);
    final history = ref.watch(historyProvider);
    final streak = ref.watch(streakProvider);
    final hydrationTrigger = ref.watch(scrollToHydrationProvider);
    final recommendationsTrigger = ref.watch(scrollToRecommendationsProvider);

    // Scroll to hydration card when the tour fires the trigger
    if (hydrationTrigger != _lastHydrationTrigger) {
      _lastHydrationTrigger = hydrationTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = TourKeys.hydrationCard.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.16,
          );
        } else if (_scrollController.hasClients) {
          _scrollController.animateTo(
            600,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }

    if (recommendationsTrigger != _lastRecommendationsTrigger) {
      _lastRecommendationsTrigger = recommendationsTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = TourKeys.recommendationsCard.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.16,
          );
        }
      });
    }

    final greeting = prefs.name.isNotEmpty ? 'Hi, ${prefs.name}!' : 'Hi there!';
    final visualTheme = context.visualTheme;

    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              key: TourKeys.bodyMapIcon,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BodyMapScreen()),
              ),
              child: PremiumMotionSurface(
                enabled: visualTheme.premium,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.all(2),
                borderWidth: 2.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: visualTheme.premium
                        ? visualTheme.cardColor
                        : context.primary600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.accessibility_new,
                    color: visualTheme.premium
                        ? visualTheme.primaryAccent
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              key: TourKeys.nutritionIcon,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NutritionDashboardScreen()),
              ),
              child: PremiumMotionSurface(
                enabled: visualTheme.premium,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.all(2),
                borderWidth: 2.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: visualTheme.premium
                        ? visualTheme.cardColor
                        : context.primary600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.eco,
                    color: visualTheme.premium
                        ? visualTheme.primaryAccent
                        : Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _initialLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: context.primary500),
                  SizedBox(height: 16),
                  Text(
                    'Loading your data…',
                    style: TextStyle(color: AppTheme.gray400),
                  ),
                ],
              ),
            )
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Greeting + streak badge ────────────────────────────
                    Row(
                      children: [
                        PremiumGradientText(
                          text: greeting,
                          enabled: visualTheme.premium,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: visualTheme.premium
                                ? visualTheme.primaryAccent
                                : AppTheme.gray900,
                          ),
                        ),
                        const Spacer(),
                        if (streak.currentStreak > 0) ...[
                          PremiumMotionSurface(
                            key: TourKeys.streakBadge,
                            enabled: visualTheme.premium,
                            borderRadius: BorderRadius.circular(24),
                            padding: const EdgeInsets.all(2),
                            borderWidth: 2.8,
                            fillColor: visualTheme.cardColor,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: visualTheme.premium
                                    ? visualTheme.cardColor
                                    : null,
                                gradient: visualTheme.premium
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFFFF5A00),
                                          Color(0xFFFFA000),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: visualTheme.premium
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: const Color(0xFFFF8C00)
                                              .withValues(alpha: 0.45),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('🔥',
                                      style: TextStyle(
                                          fontSize: 20,
                                          height: 1,
                                          color: visualTheme.premium
                                              ? visualTheme.primaryAccent
                                              : Colors.white)),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${streak.currentStreak} day streak',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: visualTheme.premium
                                          ? visualTheme.primaryAccent
                                          : Colors.white,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _todayLabel(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.gray400,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Calorie progress ring ────────────────────────────────
                    _CalorieRingCard(
                      consumed: intake.caloriesAvg,
                      goal: prefs.dailyCalorieGoal.toDouble(),
                      scanCount: intake.scanCount,
                    ),
                    const SizedBox(height: 16),

                    // ── Goal mascot card ─────────────────────────────────────
                    _GoalProgressCard(prefs: prefs, intake: intake),
                    const SizedBox(height: 16),

                    // ── Hydration card ───────────────────────────────────────
                    Container(
                      key: TourKeys.hydrationCard,
                      child: const _HydrationCard(),
                    ),
                    const SizedBox(height: 16),

                    // ── Weekly challenges ────────────────────────────────────
                    const WeeklyChallengesCard(),
                    const SizedBox(height: 16),

                    // ── Recommendations (above Today's Foods) ────────────────
                    Container(
                      key: TourKeys.recommendationsCard,
                      child: _RecommendationsCard(),
                    ),
                    const SizedBox(height: 16),

                    // ── Food breakdown ───────────────────────────────────────
                    _SelectableSectionHeader(
                      title: 'Today\'s Foods',
                      selecting: _foodSelecting,
                      selectedCount: _selectedFoodIds.length,
                      onEnterSelection: _enterFoodSelection,
                      onDelete: () => _confirmDeleteSelected(
                        count: _selectedFoodIds.length,
                        onConfirm: _deleteSelectedFoods,
                      ),
                      onCancel: _exitFoodSelection,
                    ),
                    const SizedBox(height: 8),
                    // ICR warning for diabetes users
                    if (prefs.nutritionGoal == NutritionGoalType.diabetes &&
                        prefs.icrGramsPerUnit <= 0)
                      GestureDetector(
                        onTap: () {
                          // Navigate to Settings tab (index 5) to set ICR
                          ref.read(tabNavigationProvider.notifier).state = 5;
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.red.shade300, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.red.shade600, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ICR not set — bolus cannot be calculated',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap here to set your Insulin-to-Carb Ratio in Settings.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  color: Colors.red.shade400),
                            ],
                          ),
                        ),
                      ),
                    if (intake.foods.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: context.primary50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.restaurant_menu,
                                    color: context.primary400, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'No food logged yet today.\nScan or add food to start tracking!',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.gray400,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onLongPress: _enterFoodSelection,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Column(
                              children: intake.foods.map((f) {
                                final avg = (f.caloriesMin + f.caloriesMax) / 2;
                                final selecting = _foodSelecting;
                                final selected = f.id != null &&
                                    _selectedFoodIds.contains(f.id);

                                final row = InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    if (selecting) {
                                      if (f.id != null) {
                                        _toggleFoodSelected(f.id!);
                                      }
                                    } else {
                                      _showEditFoodSheet(context, f);
                                    }
                                  },
                                  onLongPress: f.id == null
                                      ? null
                                      : () => _toggleFoodSelected(f.id!),
                                  child: Container(
                                    decoration: selected
                                        ? BoxDecoration(
                                            color: context.primary50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          )
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 4),
                                      child: Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 10),
                                            child: selecting
                                                ? Icon(
                                                    selected
                                                        ? Icons.check_circle
                                                        : Icons.circle_outlined,
                                                    size: 20,
                                                    color: selected
                                                        ? context.primary600
                                                        : AppTheme.gray300,
                                                  )
                                                : Icon(Icons.restaurant,
                                                    size: 16,
                                                    color: context.primary500),
                                          ),
                                          Expanded(
                                            child: Text(
                                              f.label,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${avg.round()} kcal',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: context.primary700,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            selecting
                                                ? Icons.drag_handle
                                                : Icons.edit_outlined,
                                            size: 14,
                                            color: AppTheme.gray300,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );

                                // Swipe-to-delete only when not multi-selecting.
                                if (selecting || f.id == null) return row;
                                return Dismissible(
                                  key: ValueKey(f.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade400,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.delete_outline,
                                        color: Colors.white),
                                  ),
                                  confirmDismiss: (_) async {
                                    return await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Remove Food'),
                                        content: Text(
                                            'Remove "${f.label}" from today\'s intake?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Remove',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  onDismissed: (_) async {
                                    await DatabaseService.instance
                                        .deleteDetectedFood(f.id!);
                                    await ref
                                        .read(dailyIntakeProvider.notifier)
                                        .load();
                                    await ref
                                        .read(historyProvider.notifier)
                                        .load();
                                  },
                                  child: row,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // ── Scan history (full list) ───────────────────────────
                    _SelectableSectionHeader(
                      title: 'Scan History',
                      selecting: _scanSelecting,
                      selectedCount: _selectedScanIds.length,
                      onEnterSelection: _enterScanSelection,
                      onDelete: () => _confirmDeleteSelected(
                        count: _selectedScanIds.length,
                        onConfirm: _deleteSelectedScans,
                      ),
                      onCancel: _exitScanSelection,
                    ),
                    const SizedBox(height: 8),
                    if (history.scans.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.camera_alt_outlined,
                                    size: 40, color: AppTheme.gray200),
                                const SizedBox(height: 8),
                                Text(
                                  'No scans yet — tap Scan to start!',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.gray400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      ...history.scans.map((scan) {
                        final avg =
                            (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
                        final selecting = _scanSelecting;
                        final selected = scan.id != null &&
                            _selectedScanIds.contains(scan.id);

                        final thumbPath = ScanMediaResolver.resolve(
                            scan.topImagePath ?? scan.imagePath);
                        final hasThumb = thumbPath != null;

                        final card = GestureDetector(
                          onTap: () {
                            if (selecting) {
                              if (scan.id != null) {
                                _toggleScanSelected(scan.id!);
                              }
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ScanDetailScreen(scan: scan),
                                ),
                              );
                            }
                          },
                          onLongPress: scan.id == null
                              ? null
                              : () => _toggleScanSelected(scan.id!),
                          child: Card(
                            color: selected ? context.primary50 : null,
                            child: ListTile(
                              leading: selecting
                                  ? Icon(
                                      selected
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: selected
                                          ? context.primary600
                                          : AppTheme.gray300,
                                    )
                                  : Hero(
                                      tag: 'scan_icon_${scan.id}',
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: context.primary100,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: hasThumb
                                            ? Image.file(
                                                File(thumbPath),
                                                fit: BoxFit.cover,
                                              )
                                            : Icon(Icons.fastfood,
                                                color: context.primary600,
                                                size: 20),
                                      ),
                                    ),
                              title: Text(
                                '${scan.foods.length} item${scan.foods.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                _timeAgo(scan.timestamp),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.gray400,
                                ),
                              ),
                              trailing: Text(
                                '${avg.round()} kcal',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: context.primary700,
                                ),
                              ),
                            ),
                          ),
                        );

                        // Swipe-to-delete only when not multi-selecting.
                        final Widget content = (selecting || scan.id == null)
                            ? card
                            : Dismissible(
                                key: ValueKey('scan_${scan.id}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade400,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.delete_outline,
                                      color: Colors.white),
                                ),
                                confirmDismiss: (_) async {
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete Scan'),
                                      content: const Text(
                                          'Delete this scan from history?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Delete',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDismissed: (_) async {
                                  await ref
                                      .read(historyProvider.notifier)
                                      .deleteScan(scan.id!);
                                },
                                child: card,
                              );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: content,
                        );
                      }),

                    const SizedBox(height: 80), // space for FAB
                  ],
                ),
              ),
            ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Calorie progress ring ────────────────────────────────────────────────────

class _CalorieRingCard extends StatefulWidget {
  const _CalorieRingCard({
    required this.consumed,
    required this.goal,
    required this.scanCount,
  });
  final double consumed;
  final double goal;
  final int scanCount;

  @override
  State<_CalorieRingCard> createState() => _CalorieRingCardState();
}

class _CalorieRingCardState extends State<_CalorieRingCard>
    with TickerProviderStateMixin {
  late AnimationController _anim;
  late AnimationController _motion;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _motion = AnimationController(vsync: this);
    _setupAnimation();
    _anim.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(_CalorieRingCard old) {
    super.didUpdateWidget(old);
    if (old.consumed != widget.consumed || old.goal != widget.goal) {
      _setupAnimation();
      _anim.forward(from: 0);
    }
  }

  void _setupAnimation() {
    final target =
        widget.goal > 0 ? (widget.consumed / widget.goal).clamp(0.0, 1.0) : 0.0;
    _progress = Tween<double>(begin: 0, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );
  }

  void _syncMotion() {
    final visual = context.visualTheme;
    _motion.duration = visual.motionDuration;
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate =
        visual.premium && TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (shouldAnimate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!shouldAnimate && _motion.isAnimating) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.goal - widget.consumed).clamp(0, double.infinity);

    return PremiumSurface(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // Animated ring
          AnimatedBuilder(
            animation: Listenable.merge([_progress, _motion]),
            builder: (_, __) => SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CustomPaint(
                      painter: _CalorieRingPainter(
                        progress: _progress.value,
                        phase: _motion.value,
                        visual: context.visualTheme,
                        trackColor: context.primary100,
                        fallbackColor: widget.consumed > widget.goal
                            ? AppTheme.amber500
                            : context.primary500,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.consumed.round().toString(),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: context.appTextColor,
                        ),
                      ),
                      Text(
                        'kcal',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appMutedTextColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),

          // Stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatRow(
                  label: 'Goal',
                  value: '${widget.goal.round()} kcal',
                  color: context.appTextColor,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Remaining',
                  value: '${remaining.round()} kcal',
                  color: widget.consumed > widget.goal
                      ? AppTheme.amber700
                      : context.primary700,
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Scans today',
                  value: '${widget.scanCount}',
                  color: context.appTextColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  const _CalorieRingPainter({
    required this.progress,
    required this.phase,
    required this.visual,
    required this.trackColor,
    required this.fallbackColor,
  });

  final double progress;
  final double phase;
  final AppVisualTheme visual;
  final Color trackColor;
  final Color fallbackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final circle = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final foreground = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (visual.premium) {
      final colors = [...visual.gradient, visual.gradient.first];
      foreground.shader = SweepGradient(
        transform: GradientRotation(phase * math.pi * 2),
        colors: colors,
      ).createShader(circle);
    } else {
      foreground.color = fallbackColor;
    }

    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(covariant _CalorieRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.visual != visual ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fallbackColor != fallbackColor;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: context.appMutedTextColor),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: context.appTextColor,
      ),
    );
  }
}

/// Section header that turns into a selection toolbar (N selected · Delete ·
/// Cancel) while the user is multi-selecting rows for a bulk delete.
class _SelectableSectionHeader extends StatelessWidget {
  const _SelectableSectionHeader({
    required this.title,
    required this.selecting,
    required this.selectedCount,
    required this.onEnterSelection,
    required this.onDelete,
    required this.onCancel,
  });

  final String title;
  final bool selecting;
  final int selectedCount;
  final VoidCallback onEnterSelection;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!selecting) {
      return Row(
        children: [
          Expanded(child: _SectionTitle(title)),
          // Discoverable multi-select affordance (no long-press required).
          InkWell(
            onTap: onEnterSelection,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.check_circle_outline,
                  size: 20, color: AppTheme.gray400),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.selectedCount(selectedCount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.appTextColor,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: selectedCount == 0 ? null : onDelete,
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          label: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
        ),
        TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
      ],
    );
  }
}

// ── Goal progress card ────────────────────────────────────────────────────────

class _GoalProgressCard extends StatelessWidget {
  const _GoalProgressCard({required this.prefs, required this.intake});
  final dynamic prefs; // UserPreferences
  final dynamic intake; // DailyIntake

  @override
  Widget build(BuildContext context) {
    final goal = prefs.nutritionGoal as NutritionGoalType;
    final kcalGoal = (prefs.dailyCalorieGoal as int).toDouble();
    final carbLim = (prefs.dailyCarbLimitG as int).toDouble();
    final fatGoal = (prefs.dailyFatTargetG as int).toDouble();

    final kcalProgress = kcalGoal > 0 ? intake.caloriesAvg / kcalGoal : 0.0;
    final carbStress = carbLim > 0 ? intake.carbsG / carbLim : 0.0;
    final fatStress = fatGoal > 0 ? intake.fatG / fatGoal : 0.0;

    // Composite unhealthy score for the diabetes sugar mascot:
    // start at 0 (best = very healthy sugar), rise as the person
    // overshoots carbs, fat, OR overall calories.
    // Each ratio is capped at 1.5 so one extreme macro can't dominate
    // beyond reason. Weighted: carbs 50%, fat 30%, calories 20%.
    final diabetesStress = (carbStress.clamp(0.0, 1.5) * 0.50 +
        fatStress.clamp(0.0, 1.5) * 0.30 +
        kcalProgress.clamp(0.0, 1.5) * 0.20);

    return PremiumSurface(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            color: context.primary100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              goal.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: context.primary700,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Mascot
                GoalMascotWidget(
                  goalType: goal,
                  progress: kcalProgress,
                  stressLevel: goal == NutritionGoalType.diabetes
                      ? diabetesStress
                      : carbStress,
                  mascotOverride: prefs.mascotType,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NutritionDashboardScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Stats
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MacroRow(
                        label: '🔥 Calories',
                        current: intake.caloriesAvg.round(),
                        target: prefs.dailyCalorieGoal as int,
                        unit: 'kcal',
                        color: goal.color,
                      ),
                      const SizedBox(height: 8),
                      _MacroRow(
                        label: '💪 Protein',
                        current: intake.proteinG.round(),
                        target: prefs.dailyProteinTargetG as int,
                        unit: 'g',
                        color: Colors.red.shade500,
                      ),
                      const SizedBox(height: 8),
                      _MacroRow(
                        label: '🍞 Carbs',
                        current: intake.carbsG.round(),
                        target: prefs.dailyCarbLimitG as int,
                        unit: 'g',
                        color: Colors.amber.shade700,
                        isLimit: true,
                      ),
                      const SizedBox(height: 8),
                      _MacroRow(
                        label: '🥑 Fat',
                        current: intake.fatG.round(),
                        target: prefs.dailyFatTargetG as int,
                        unit: 'g',
                        color: Colors.green.shade600,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.label,
    required this.current,
    required this.target,
    required this.unit,
    required this.color,
    this.isLimit = false,
  });
  final String label;
  final int current;
  final int target;
  final String unit;
  final Color color;
  final bool isLimit;

  @override
  Widget build(BuildContext context) {
    final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final isOver = isLimit && current > target;

    // Healthy state:
    //  • Carbs (isLimit=true):  healthy = under the limit (green = safe)
    //  • Others (protein, kcal, fat):  healthy = ≥85 % of target reached
    final isHealthy = isLimit ? !isOver : current >= (target * 0.85).round();

    final barColor = isOver
        ? Colors.red.shade500
        : isHealthy
            ? Colors.green.shade500
            : color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppTheme.gray600)),
            const Spacer(),
            Text(
              '$current / $target $unit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isOver
                    ? Colors.red.shade600
                    : isHealthy
                        ? Colors.green.shade700
                        : AppTheme.gray700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: barColor.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ── Recommendations card ──────────────────────────────────────────────────────

class _RecommendationsCard extends ConsumerWidget {
  const _RecommendationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recommendationsProvider);

    if (state.recs.isEmpty) return const SizedBox.shrink();

    return PremiumSurface(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Professional gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  context.primary500.withValues(alpha: 0.08),
                  context.isPremiumTheme
                      ? context.visualTheme.secondaryAccent
                          .withValues(alpha: 0.10)
                      : Colors.amber.shade50.withValues(alpha: 0.5),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.amber600.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      size: 16, color: AppTheme.amber600),
                ),
                const SizedBox(width: 10),
                Text(
                  'Smart Recommendations',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: context.appTextColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.primary500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${state.recs.length} tips',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.primary600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Recommendation items
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: state.recs.asMap().entries.map((entry) {
                final rec = entry.value;
                final isLast = entry.key == state.recs.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: rec.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: rec.color.withValues(alpha: 0.2)),
                        ),
                        child: Icon(rec.icon, size: 18, color: rec.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec.message,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (rec.suggestion != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: rec.color.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.tips_and_updates_outlined,
                                        size: 12,
                                        color:
                                            rec.color.withValues(alpha: 0.7)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        rec.suggestion!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.appMutedTextColor,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hydration card ────────────────────────────────────────────────────────────

class _HydrationCard extends ConsumerWidget {
  const _HydrationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);
    final intake = prefs.waterIntakeMl;
    final goal = prefs.dailyWaterGoalMl;
    final progress = goal > 0 ? (intake / goal).clamp(0.0, 1.0) : 0.0;

    // Pick glass image based on progress
    final String glassAsset;
    if (progress >= 1.0) {
      glassAsset = 'assets/mascots/full_glass.png';
    } else if (progress >= 2 / 3) {
      glassAsset = 'assets/mascots/almost_full_glass.png';
    } else if (progress >= 1 / 3) {
      glassAsset = 'assets/mascots/almost_empty_glass.png';
    } else {
      glassAsset = 'assets/mascots/empty_glass.png';
    }

    final percent = (progress * 100).round();
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    final waterAccent =
        premium ? visualTheme.primaryAccent : const Color(0xFF1976D2);

    return PremiumSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Hydration',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: waterAccent,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                color: intake > 0 ? waterAccent : context.appMutedTextColor,
                tooltip: 'Remove 250 ml',
                onPressed:
                    intake > 0 ? () => _removeWater(context, ref, 250) : null,
              ),
              IconButton(
                key: TourKeys.hydrationAddDrink,
                icon: const Icon(Icons.add_circle_outline, size: 22),
                color: waterAccent,
                tooltip: 'Add drink',
                onPressed: () => _showDrinkSheet(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                color: context.appMutedTextColor,
                tooltip: 'Adjust water goal',
                onPressed: () => _showGoalDialog(context, ref, goal),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Glass mascot
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: premium
                      ? context.appSubtleFillColor
                      : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(6),
                child: Image.asset(glassAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fmtMl(intake)} / ${_fmtMl(goal)}  ($percent%)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.appTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: premium
                            ? waterAccent.withValues(alpha: 0.16)
                            : const Color(0xFFBBDEFB),
                        valueColor: AlwaysStoppedAnimation(waterAccent),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress >= 1.0
                          ? '🎉 Hydration goal reached!'
                          : '${_fmtMl((goal - intake).clamp(0, goal))} remaining',
                      style: TextStyle(
                          fontSize: 11, color: context.appMutedTextColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Quick-add water buttons
          Row(
            children: [
              _WaterButton(label: '+150 ml', ml: 150),
              const SizedBox(width: 8),
              _WaterButton(
                  key: TourKeys.hydrationQuickAdd200,
                  label: '+200 ml',
                  ml: 200),
              const SizedBox(width: 8),
              _WaterButton(label: '+250 ml', ml: 250),
              const SizedBox(width: 8),
              _WaterButton(label: '+500 ml', ml: 500),
            ],
          ),
        ],
      ),
    );
  }

  void _showGoalDialog(BuildContext context, WidgetRef ref, int currentGoal) {
    // Slider value in ml (2000-3500, steps of 250)
    int tempGoal = currentGoal.clamp(2000, 3500).toInt();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Daily Water Goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(tempGoal / 1000).toStringAsFixed(1)} L',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: tempGoal.toDouble(),
                min: 2000,
                max: 3500,
                divisions: 6,
                label: '${(tempGoal / 1000).toStringAsFixed(1)} L',
                onChanged: (v) => setDialogState(() => tempGoal = v.round()),
              ),
              const Text(
                'Min 2.0 L · Max 3.5 L',
                style: TextStyle(fontSize: 11, color: AppTheme.gray400),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(userPrefsProvider.notifier)
                    .setDailyWaterGoal(tempGoal);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDrinkSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DrinkSheet(
        onLog: (label, ml) {
          Navigator.of(ctx).pop();
          _logDrink(context, ref, label, ml);
        },
      ),
    );
  }

  Future<void> _logDrink(
    BuildContext context,
    WidgetRef ref,
    String label,
    double ml,
  ) async {
    FoodData food;
    try {
      food = await DatabaseService.instance.getFoodByLabel(label) ??
          FoodData(
            label: label,
            densityMin: 1.0,
            densityMax: 1.0,
            kcalPer100g: 0,
            category: 'drink',
            perMl: true,
          );
    } catch (_) {
      food = FoodData(
        label: label,
        densityMin: 1.0,
        densityMax: 1.0,
        kcalPer100g: 0,
        category: 'drink',
        perMl: true,
      );
    }

    final avgDensity = (food.densityMin + food.densityMax) / 2;
    final volumeCm3 = ml / avgDensity;
    final range = food.calorieRange(volumeCm3);
    final result = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'hydration',
      foods: [
        DetectedFood(
          label: food.label,
          volumeCm3: volumeCm3,
          caloriesMin: range.min,
          caloriesMax: range.max,
        ),
      ],
    );

    await ref.read(historyProvider.notifier).addScan(result);
    await ref.read(userPrefsProvider.notifier).addWater(ml.round());
    await ref.read(dailyIntakeProvider.notifier).load();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ml.round()} ml ${food.label} logged'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _removeWater(BuildContext context, WidgetRef ref, int ml) {
    ref.read(userPrefsProvider.notifier).removeWater(ml);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('-$ml ml removed'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

class _WaterButton extends ConsumerWidget {
  const _WaterButton({super.key, required this.label, required this.ml});
  final String label;
  final int ml;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: BorderSide(color: context.appBorderColor),
          foregroundColor: context.isPremiumTheme
              ? context.visualTheme.primaryAccent
              : const Color(0xFF1976D2),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        onPressed: () {
          ref.read(userPrefsProvider.notifier).addWater(ml);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('+$ml ml added'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Text(label),
      ),
    );
  }
}

/// Format a water amount precisely.
/// Under 1000 ml → shown as exact ml (e.g. "250 ml").
/// 1000 ml and above → shown in L with up to 2 decimals, trailing zeros stripped.
String _fmtMl(int ml) {
  if (ml < 1000) return '$ml ml';
  final s = (ml / 1000.0).toStringAsFixed(2);
  final trimmed =
      s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '$trimmed L';
}
