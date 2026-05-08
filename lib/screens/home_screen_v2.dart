import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/recommendations_provider.dart';
import '../providers/streak_provider.dart';
import '../providers/scroll_trigger_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/drink_sheet.dart';
import '../widgets/goal_mascot_widget.dart';
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
  final _hydrationCardKey = GlobalKey();
  final _recommendationsCardKey = GlobalKey();
  int _lastHydrationTrigger = 0;
  int _lastRecommendationsTrigger = 0;

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
    await ref.read(streakProvider.notifier).load();
    if (mounted) setState(() => _initialLoading = false);
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
        final ctx = _hydrationCardKey.currentContext;
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
        final ctx = _recommendationsCardKey.currentContext;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pixels to Macros'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BodyMapScreen()),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: context.primary600,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.accessibility_new,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NutritionDashboardScreen()),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: context.primary600,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.eco, color: Colors.white, size: 20),
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
                        Text(
                          greeting,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gray900,
                          ),
                        ),
                        const Spacer(),
                        if (streak.currentStreak > 0) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF5A00), Color(0xFFFFA000)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF8C00).withValues(alpha: 0.45),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔥', style: TextStyle(fontSize: 20, height: 1)),
                                const SizedBox(width: 8),
                                Text(
                                  '${streak.currentStreak} day streak',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                              ],
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
                      key: _hydrationCardKey,
                      child: const _HydrationCard(),
                    ),
                    const SizedBox(height: 16),



                    // ── Weekly challenges ────────────────────────────────────
                    const WeeklyChallengesCard(),
                    const SizedBox(height: 16),

                    // ── Food breakdown ───────────────────────────────────────
                    _SectionTitle('Today\'s Foods'),
                    const SizedBox(height: 8),
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
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: intake.foods.map((f) {
                              final avg = (f.caloriesMin + f.caloriesMax) / 2;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.restaurant,
                                        size: 16, color: context.primary500),
                                    const SizedBox(width: 10),
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
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // ── Recommendations ───────────────────────────────────────
                    Container(
                      key: _recommendationsCardKey,
                      child: _RecommendationsCard(),
                    ),
                    const SizedBox(height: 16),

                    // ── Recent scans ─────────────────────────────────────────
                    _SectionTitle('Recent Scans'),
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
                      ...history.scans.take(3).map((scan) {
                        final avg =
                            (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ScanDetailScreen(scan: scan),
                              ),
                            ),
                            child: Card(
                              child: ListTile(
                                leading: Hero(
                                  tag: 'scan_icon_${scan.id}',
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: context.primary100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.fastfood,
                                        color: context.primary600, size: 20),
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
                          ),
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
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _setupAnimation();
    _anim.forward();
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

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.goal - widget.consumed).clamp(0, double.infinity);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Animated ring
            AnimatedBuilder(
              animation: _progress,
              builder: (_, __) => SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: _progress.value,
                        strokeWidth: 10,
                        backgroundColor: context.primary100,
                        color: widget.consumed > widget.goal
                            ? AppTheme.amber500
                            : context.primary500,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.consumed.round().toString(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gray900,
                          ),
                        ),
                        const Text(
                          'kcal',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
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
                    color: AppTheme.gray700,
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
                    color: AppTheme.gray700,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
          style: const TextStyle(fontSize: 13, color: AppTheme.gray400),
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.gray700,
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final StreakState streak;

  @override
  Widget build(BuildContext context) {
    final active = streak.currentStreak > 0;
    return Container(
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(
                colors: [Color(0xFFFF6B00), Color(0xFFFF9F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.20)
                    : const Color(0xFFE0E0E0),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  active ? '🔥' : '💤',
                  style: const TextStyle(fontSize: 32, height: 1),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    active
                        ? '${streak.currentStreak} day streak!'
                        : 'No streak yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : AppTheme.gray700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    streak.scannedToday
                        ? '✅ Logged today — keep it up!'
                        : active
                            ? 'Scan today to keep the fire going!'
                            : 'Start scanning to build your streak.',
                    style: TextStyle(
                      fontSize: 12,
                      color: active
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppTheme.gray500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.22)
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${streak.longestStreak}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: active ? Colors.white : AppTheme.gray600,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'best',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white.withValues(alpha: 0.80)
                          : AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

    return Card(
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
    final barColor = isOver ? Colors.red.shade500 : color;

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
                color: isOver ? Colors.red.shade600 : AppTheme.gray700,
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline,
                    size: 18, color: AppTheme.amber600),
                SizedBox(width: 6),
                Text(
                  'Smart Recommendations',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppTheme.gray900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...state.recs.map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: rec.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(rec.icon, size: 16, color: rec.color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec.message,
                              style: const TextStyle(fontSize: 13, height: 1.4),
                            ),
                            if (rec.suggestion != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                rec.suggestion!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.gray400,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
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
    if (progress >= 0.75) {
      glassAsset = 'assets/mascots/full_glass.png';
    } else if (progress >= 0.50) {
      glassAsset = 'assets/mascots/almost_full_glass.png';
    } else if (progress >= 0.25) {
      glassAsset = 'assets/mascots/almost_empty_glass.png';
    } else {
      glassAsset = 'assets/mascots/empty_glass.png';
    }

    final percent = (progress * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Hydration',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1565C0),
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color:
                      intake > 0 ? const Color(0xFF1976D2) : AppTheme.gray300,
                  tooltip: 'Remove 250 ml',
                  onPressed:
                      intake > 0 ? () => _removeWater(context, ref, 250) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  color: const Color(0xFF1976D2),
                  tooltip: 'Add drink',
                  onPressed: () => _showDrinkSheet(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  color: AppTheme.gray400,
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
                    color: const Color(0xFFE3F2FD),
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.gray900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: const Color(0xFFBBDEFB),
                          valueColor:
                              const AlwaysStoppedAnimation(Color(0xFF1976D2)),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        progress >= 1.0
                            ? '🎉 Hydration goal reached!'
                            : '${_fmtMl((goal - intake).clamp(0, goal))} remaining',
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.gray400),
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
                _WaterButton(label: '+200 ml', ml: 200),
                const SizedBox(width: 8),
                _WaterButton(label: '+250 ml', ml: 250),
                const SizedBox(width: 8),
                _WaterButton(label: '+500 ml', ml: 500),
              ],
            ),
          ],
        ),
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
  const _WaterButton({required this.label, required this.ml});
  final String label;
  final int ml;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: const BorderSide(color: Color(0xFF90CAF9)),
          foregroundColor: const Color(0xFF1976D2),
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
  final trimmed = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '$trimmed L';
}
