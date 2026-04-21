import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/streak_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/debug_log.dart';
import '../theme/app_theme.dart';
import 'debug_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
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

    final greeting = prefs.name.isNotEmpty
        ? 'Hi, ${prefs.name}!'
        : 'Hi there!';

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.green600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: Colors.white, size: 20),
          ),
        ),
        title: const Text('Pixels to Macros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug Log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
          ),
        ],
      ),
      body: _initialLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.green500),
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
            padding: const EdgeInsets.all(16),
            children: [
              // ── Greeting ─────────────────────────────────────────────
              Text(
                greeting,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gray900,
                ),
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

              // ── Streak card ──────────────────────────────────────────
              _StreakCard(streak: streak),
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
                            color: AppTheme.green50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_menu,
                              color: AppTheme.green300, size: 20),
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
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.restaurant,
                                  size: 16, color: AppTheme.green500),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.green700,
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
                              color: AppTheme.green100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.fastfood,
                                color: AppTheme.green600, size: 20),
                          ),
                        ),
                        title: Text(
                          '${scan.foods.length} item${scan.foods.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.green700,
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
    final target = widget.goal > 0
        ? (widget.consumed / widget.goal).clamp(0.0, 1.0)
        : 0.0;
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
                        backgroundColor: AppTheme.green100,
                        color: widget.consumed > widget.goal
                            ? AppTheme.amber500
                            : AppTheme.green500,
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
                        : AppTheme.green700,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: streak.currentStreak > 0
                    ? AppTheme.amber100
                    : AppTheme.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.local_fire_department,
                size: 28,
                color: streak.currentStreak > 0
                    ? AppTheme.amber500
                    : AppTheme.gray400,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${streak.currentStreak} day streak',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gray900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    streak.scannedToday
                        ? 'Keep it going!'
                        : 'Scan today to continue!',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${streak.longestStreak}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.green700,
                  ),
                ),
                const Text(
                  'best',
                  style: TextStyle(fontSize: 11, color: AppTheme.gray400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
