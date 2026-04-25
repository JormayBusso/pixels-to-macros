import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analytics_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// Weekly/monthly analytics with bar chart and stats.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _range = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(analyticsProvider.notifier).load(rangeDays: _range);
  }

  void _setRange(int days) {
    setState(() => _range = days);
    ref.read(analyticsProvider.notifier).load(rangeDays: days);
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(analyticsProvider);
    final goal = ref.watch(userPrefsProvider).dailyCalorieGoal.toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: analytics.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Range selector ─────────────────────────────────────
                Row(
                  children: [
                    _RangeChip(label: '7d', days: 7, active: _range == 7, onTap: _setRange),
                    const SizedBox(width: 8),
                    _RangeChip(label: '14d', days: 14, active: _range == 14, onTap: _setRange),
                    const SizedBox(width: 8),
                    _RangeChip(label: '30d', days: 30, active: _range == 30, onTap: _setRange),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Bar chart ──────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Daily Calories',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gray700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 180,
                          child: analytics.days.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No data yet',
                                    style: TextStyle(color: AppTheme.gray400),
                                  ),
                                )
                              : _BarChart(
                                  days: analytics.days,
                                  goal: goal,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Summary stats ──────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Avg / day',
                        value: '${analytics.averageDaily.round()}',
                        unit: 'kcal',
                        icon: Icons.show_chart,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Peak day',
                        value: '${analytics.peakDay.round()}',
                        unit: 'kcal',
                        icon: Icons.arrow_upward,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Total scans',
                        value: '${analytics.totalScans}',
                        unit: '',
                        icon: Icons.camera_alt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Goal',
                        value: '${goal.round()}',
                        unit: 'kcal/day',
                        icon: Icons.flag,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Day-by-day breakdown ───────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Day by Day',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gray700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...analytics.days.reversed.map((d) => _DayRow(
                              day: d,
                              goal: goal,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

// ── Bar chart (custom painted) ──────────────────────────────────────────────

class _BarChart extends StatelessWidget {
  const _BarChart({required this.days, required this.goal});
  final List<DaySummary> days;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final maxVal = days
        .map((d) => d.caloriesAvg)
        .fold(goal, (a, b) => a > b ? a : b);
    final ceiling = maxVal * 1.15;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = (constraints.maxWidth / days.length) - 4;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: days.map((d) {
            final fraction = ceiling > 0 ? d.caloriesAvg / ceiling : 0.0;
            final barHeight = (constraints.maxHeight - 20) * fraction;
            final overGoal = d.caloriesAvg > goal;

            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (d.caloriesAvg > 0)
                    Text(
                      '${d.caloriesAvg.round()}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: overGoal ? AppTheme.amber700 : AppTheme.gray400,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    height: barHeight.clamp(2.0, constraints.maxHeight - 20),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: overGoal ? AppTheme.amber500 : context.primary400,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _dayLabel(d.date),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _dayLabel(DateTime dt) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[dt.weekday - 1];
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.days,
    required this.active,
    required this.onTap,
  });
  final String label;
  final int days;
  final bool active;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: active,
      selectedColor: context.primary200,
      onSelected: (_) => onTap(days),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.primary500),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.gray400),
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.gray400,
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

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.goal});
  final DaySummary day;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final pct = goal > 0 ? (day.caloriesAvg / goal).clamp(0.0, 1.0) : 0.0;
    final over = day.caloriesAvg > goal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              _formatDate(day.date),
              style: const TextStyle(fontSize: 12, color: AppTheme.gray400),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: context.primary100,
                color: over ? AppTheme.amber500 : context.primary500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 65,
            child: Text(
              '${day.caloriesAvg.round()} kcal',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: over ? AppTheme.amber700 : AppTheme.gray700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}';
  }
}
