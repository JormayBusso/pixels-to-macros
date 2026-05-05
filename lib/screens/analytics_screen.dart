import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analytics_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// Analytics tab.
///
/// A re-design of the previous bare bar-chart screen. Adds an animated
/// calorie-vs-goal line chart with a tap-to-inspect cursor, weekday-pattern
/// chart, average-macros donut, weekly trend insight card, streak/consistency
/// stat tiles, and a per-day breakdown list. Pure-Dart custom painters; no
/// new package dependencies.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _range = 7;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await ref.read(analyticsProvider.notifier).load(rangeDays: _range);
  }

  void _setRange(int days) {
    setState(() {
      _range = days;
      _selectedIndex = null;
    });
    ref.read(analyticsProvider.notifier).load(rangeDays: days);
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(analyticsProvider);
    final prefs = ref.watch(userPrefsProvider);
    final goal = prefs.dailyCalorieGoal.toDouble();
    final proteinTarget = prefs.dailyProteinTargetG.toDouble();
    final carbsTarget = prefs.dailyCarbLimitG.toDouble();
    final fatTarget = prefs.dailyFatTargetG.toDouble();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: analytics.loading && analytics.days.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _RangeSelector(active: _range, onSelect: _setRange),
                  const SizedBox(height: 20),
                  _CalorieTrendCard(
                    state: analytics,
                    goal: goal,
                    selectedIndex: _selectedIndex,
                    onSelect: (i) => setState(() => _selectedIndex = i),
                  ),
                  const SizedBox(height: 16),
                  _StatTilesGrid(state: analytics, goal: goal),
                  const SizedBox(height: 16),
                  _MacroDonutCard(
                    state: analytics,
                    proteinTarget: proteinTarget,
                    carbsTarget: carbsTarget,
                    fatTarget: fatTarget,
                  ),
                  const SizedBox(height: 16),
                  _WeekdayPatternCard(state: analytics, goal: goal),
                  const SizedBox(height: 16),
                  _InsightCard(state: analytics, goal: goal),
                  const SizedBox(height: 16),
                  _DayBreakdownCard(state: analytics, goal: goal),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────── Range selector ───────────────────────────

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.active, required this.onSelect});
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = const [(7, '7d'), (14, '14d'), (30, '30d'), (90, '90d')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((o) {
          final selected = o.$1 == active;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(o.$1),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  o.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color:
                        selected ? context.primary600 : AppTheme.gray500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────── Calorie trend (line chart) ───────────────────────

class _CalorieTrendCard extends StatelessWidget {
  const _CalorieTrendCard({
    required this.state,
    required this.goal,
    required this.selectedIndex,
    required this.onSelect,
  });

  final AnalyticsState state;
  final double goal;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final days = state.days;
    if (days.isEmpty) {
      return _CardShell(
        title: 'Calorie trend',
        child: const SizedBox(
          height: 160,
          child: Center(
            child: Text('No data yet', style: TextStyle(color: AppTheme.gray400)),
          ),
        ),
      );
    }

    final selected = selectedIndex != null && selectedIndex! < days.length
        ? days[selectedIndex!]
        : null;

    return _CardShell(
      title: 'Calorie trend',
      trailing: selected == null
          ? null
          : Text(
              '${_formatDate(selected.date)}: ${selected.caloriesAvg.round()} kcal',
              style: TextStyle(
                fontSize: 12,
                color: context.primary600,
                fontWeight: FontWeight.w700,
              ),
            ),
      child: AspectRatio(
        aspectRatio: 1.7,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final w = constraints.maxWidth - 8;
                final dx = (d.localPosition.dx - 4).clamp(0.0, w);
                final i = (dx / (w / (days.length - 1).clamp(1, 999)))
                    .round()
                    .clamp(0, days.length - 1);
                onSelect(i);
              },
              onTap: () {},
              child: CustomPaint(
                painter: _CaloriesLinePainter(
                  days: days,
                  goal: goal,
                  primary: context.primary500,
                  primarySoft: context.primary100,
                  highlightIndex: selectedIndex,
                ),
                size: Size.infinite,
              ),
            );
          },
        ),
      ),
    );
  }

  static String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month.toString().padLeft(2, '0')}';
}

class _CaloriesLinePainter extends CustomPainter {
  _CaloriesLinePainter({
    required this.days,
    required this.goal,
    required this.primary,
    required this.primarySoft,
    required this.highlightIndex,
  });

  final List<DaySummary> days;
  final double goal;
  final Color primary;
  final Color primarySoft;
  final int? highlightIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const padL = 4.0, padR = 4.0, padT = 12.0, padB = 22.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final maxVal = math.max(
      goal * 1.2,
      days.map((d) => d.caloriesAvg).fold<double>(0, math.max) * 1.1,
    );
    if (maxVal <= 0) return;

    Offset point(int i) {
      final x = padL + (days.length == 1 ? w / 2 : w * i / (days.length - 1));
      final y = padT + h * (1 - days[i].caloriesAvg / maxVal);
      return Offset(x, y);
    }

    // Goal line
    final goalY = padT + h * (1 - goal / maxVal);
    final goalPaint = Paint()
      ..color = AppTheme.amber500.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final dashWidth = 6.0, gap = 4.0;
    var x = padL;
    while (x < padL + w) {
      canvas.drawLine(Offset(x, goalY),
          Offset(math.min(x + dashWidth, padL + w), goalY), goalPaint);
      x += dashWidth + gap;
    }
    final goalLabelTp = TextPainter(
      text: TextSpan(
        text: 'Goal ${goal.round()}',
        style: const TextStyle(
          fontSize: 9,
          color: AppTheme.amber700,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    goalLabelTp.paint(
      canvas,
      Offset(padL + w - goalLabelTp.width, goalY - goalLabelTp.height - 1),
    );

    // Filled area + line
    final pts = [for (int i = 0; i < days.length; i++) point(i)];
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final mid = Offset(
        (pts[i - 1].dx + pts[i].dx) / 2,
        (pts[i - 1].dy + pts[i].dy) / 2,
      );
      linePath.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
    }
    linePath.lineTo(pts.last.dx, pts.last.dy);

    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, padT + h)
      ..lineTo(pts.first.dx, padT + h)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primary.withValues(alpha: 0.30),
          primarySoft.withValues(alpha: 0.00),
        ],
      ).createShader(Rect.fromLTWH(padL, padT, w, h));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Dots + day labels
    final labelPaint = TextStyle(
      fontSize: 9,
      color: AppTheme.gray400,
    );
    for (int i = 0; i < days.length; i++) {
      final p = pts[i];
      final isHi = i == highlightIndex;
      final dotPaint = Paint()
        ..color = days[i].isEmpty ? AppTheme.gray200 : primary;
      canvas.drawCircle(p, isHi ? 5 : 3, dotPaint);
      if (isHi) {
        canvas.drawCircle(
            p, 8, Paint()..color = primary.withValues(alpha: 0.20));
      }

      // X-axis label every Nth point so it never overlaps.
      final stride = days.length > 14 ? (days.length / 7).ceil() : 1;
      if (i % stride == 0 || i == days.length - 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${days[i].date.day}/${days[i].date.month}',
            style: labelPaint,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(p.dx - tp.width / 2, padT + h + 4));
      }
    }

    // Highlight vertical guide
    if (highlightIndex != null && highlightIndex! < pts.length) {
      final p = pts[highlightIndex!];
      final guidePaint = Paint()
        ..color = primary.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(p.dx, padT), Offset(p.dx, padT + h), guidePaint);
    }
  }

  @override
  bool shouldRepaint(_CaloriesLinePainter old) =>
      old.days != days ||
      old.goal != goal ||
      old.highlightIndex != highlightIndex;
}

// ─────────────────────────── Stat tiles ───────────────────────────

class _StatTilesGrid extends StatelessWidget {
  const _StatTilesGrid({required this.state, required this.goal});
  final AnalyticsState state;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final avg = state.averageDaily;
    final avgPctOfGoal = goal > 0 ? (avg / goal * 100).round() : 0;
    final consistency = (state.consistency * 100).round();
    final trend = state.weeklyTrendPct;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        _StatTile(
          icon: Icons.show_chart,
          label: 'Daily average',
          value: '${avg.round()}',
          unit: 'kcal',
          accent: '$avgPctOfGoal% of goal',
        ),
        _StatTile(
          icon: Icons.event_available_outlined,
          label: 'Logged days',
          value: '${state.loggedDays}/${state.days.length}',
          unit: '',
          accent: '$consistency% consistency',
        ),
        _StatTile(
          icon: Icons.arrow_upward,
          label: 'Peak day',
          value: '${state.peakDay.round()}',
          unit: 'kcal',
        ),
        _StatTile(
          icon: trend == null
              ? Icons.trending_flat
              : trend > 0
                  ? Icons.trending_up
                  : Icons.trending_down,
          label: 'Recent trend',
          value: trend == null
              ? '—'
              : '${trend.abs().toStringAsFixed(1)}%',
          unit: trend == null
              ? ''
              : trend > 0
                  ? 'up'
                  : 'down',
          accent: trend == null
              ? 'Need more data'
              : trend.abs() < 5
                  ? 'Steady'
                  : trend > 0
                      ? 'Eating more'
                      : 'Eating less',
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.accent,
  });
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.primary100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: context.primary600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.gray500,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          RichText(
            text: TextSpan(children: [
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
                    fontSize: 11,
                    color: AppTheme.gray400,
                  ),
                ),
            ]),
          ),
          if (accent != null) ...[
            const SizedBox(height: 2),
            Text(
              accent!,
              style: TextStyle(
                fontSize: 11,
                color: context.primary500,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Macro donut + targets ─────────────────────────

class _MacroDonutCard extends StatelessWidget {
  const _MacroDonutCard({
    required this.state,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
  });
  final AnalyticsState state;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;

  @override
  Widget build(BuildContext context) {
    final m = state.avgMacros;
    final pCal = m.protein * 4;
    final cCal = m.carbs * 4;
    final fCal = m.fat * 9;
    final total = pCal + cCal + fCal;
    final pPct = total > 0 ? pCal / total : 0.0;
    final cPct = total > 0 ? cCal / total : 0.0;
    final fPct = total > 0 ? fCal / total : 0.0;

    return _CardShell(
      title: 'Average macros',
      subtitle: total > 0 ? null : 'No food logged in this range',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: CustomPaint(
                painter: _MacroDonutPainter(
                  proteinPct: pPct,
                  carbsPct: cPct,
                  fatPct: fPct,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${(pCal + cCal + fCal).round()}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'kcal/day',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.gray400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MacroBar(
                    label: 'Protein',
                    grams: m.protein,
                    target: proteinTarget,
                    color: const Color(0xFF42A5F5),
                  ),
                  const SizedBox(height: 8),
                  _MacroBar(
                    label: 'Carbs',
                    grams: m.carbs,
                    target: carbsTarget,
                    color: const Color(0xFFFFA726),
                  ),
                  const SizedBox(height: 8),
                  _MacroBar(
                    label: 'Fat',
                    grams: m.fat,
                    target: fatTarget,
                    color: const Color(0xFF66BB6A),
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

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.grams,
    required this.target,
    required this.color,
  });
  final String label;
  final double grams;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = target > 0 ? (grams / target).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${grams.round()}g${target > 0 ? ' / ${target.round()}g' : ''}',
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.gray500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _MacroDonutPainter extends CustomPainter {
  _MacroDonutPainter({
    required this.proteinPct,
    required this.carbsPct,
    required this.fatPct,
  });
  final double proteinPct;
  final double carbsPct;
  final double fatPct;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;

    // Background
    canvas.drawCircle(center, radius, stroke..color = AppTheme.gray100);

    if (proteinPct + carbsPct + fatPct <= 0) return;

    var startAngle = -math.pi / 2;
    final segments = [
      (proteinPct, const Color(0xFF42A5F5)),
      (carbsPct, const Color(0xFFFFA726)),
      (fatPct, const Color(0xFF66BB6A)),
    ];
    for (final s in segments) {
      final sweep = 2 * math.pi * s.$1;
      stroke.color = s.$2;
      canvas.drawArc(rect, startAngle, sweep, false, stroke);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_MacroDonutPainter old) =>
      old.proteinPct != proteinPct ||
      old.carbsPct != carbsPct ||
      old.fatPct != fatPct;
}

// ─────────────────────── Weekday pattern ───────────────────────

class _WeekdayPatternCard extends StatelessWidget {
  const _WeekdayPatternCard({required this.state, required this.goal});
  final AnalyticsState state;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final wd = state.weekdayAverages;
    if (wd.values.every((v) => v <= 0)) {
      return const SizedBox.shrink();
    }
    final maxVal = wd.values.fold<double>(0, math.max);

    return _CardShell(
      title: 'Weekday pattern',
      subtitle: 'Average kcal per weekday',
      child: SizedBox(
        height: 120,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final wdNum = i + 1;
              final v = wd[wdNum] ?? 0;
              final fraction = maxVal > 0 ? v / maxVal : 0.0;
              final overGoal = v > goal;
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (v > 0)
                      Text(
                        '${v.round()}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gray500,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: (60 * fraction).clamp(2.0, 60.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: overGoal
                              ? [AppTheme.amber500, AppTheme.amber500.withValues(alpha: 0.5)]
                              : [
                                  context.primary500,
                                  context.primary300,
                                ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _wdShort(wdNum),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.gray400,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  String _wdShort(int wd) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][wd - 1];
}

// ─────────────────────────── Insight card ───────────────────────────

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.state, required this.goal});
  final AnalyticsState state;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final messages = _buildMessages(context);
    if (messages.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.primary500.withValues(alpha: 0.10),
            context.primary600.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 16, color: context.primary600),
              const SizedBox(width: 6),
              Text(
                'Insights',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: context.primary700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...messages.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.gray700,
                          fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      m,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.gray700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _buildMessages(BuildContext context) {
    final m = <String>[];
    final avg = state.averageDaily;
    final consistency = state.consistency;
    final trend = state.weeklyTrendPct;

    if (consistency < 0.3 && state.days.length >= 7) {
      m.add(
          'You logged only ${(consistency * 100).round()}% of days. Scanning more often makes these analytics much more accurate.');
    } else if (consistency >= 0.85) {
      m.add('Excellent consistency — you logged ${state.loggedDays} of ${state.days.length} days. Trends here are reliable.');
    }

    if (goal > 0 && avg > 0) {
      final delta = avg - goal;
      if (delta.abs() < goal * 0.05) {
        m.add('Your daily average matches your goal almost exactly. Nice work staying on plan.');
      } else if (delta > 0) {
        m.add('You\'re averaging ${delta.round()} kcal/day over your ${goal.round()} kcal goal. If your goal is fat-loss, drop ~${(delta * 0.7).round()} kcal of fast carbs first.');
      } else {
        m.add('You\'re ${(-delta).round()} kcal/day under your ${goal.round()} kcal goal. If you\'re tired, add a protein-rich snack.');
      }
    }

    if (trend != null && trend.abs() >= 8) {
      m.add(trend > 0
          ? 'Calories are trending up by ${trend.toStringAsFixed(1)}% recently — worth checking which days.'
          : 'Calories are trending down by ${trend.abs().toStringAsFixed(1)}% recently — make sure you\'re still hitting protein targets.');
    }

    final macros = state.avgMacros;
    final macroCal = macros.protein * 4 + macros.carbs * 4 + macros.fat * 9;
    if (macroCal > 0) {
      final pPct = (macros.protein * 4) / macroCal;
      if (pPct < 0.18) {
        m.add('Protein is only ${(pPct * 100).round()}% of your average intake. Aim for 20–30% for satiety and muscle support.');
      }
    }
    return m;
  }
}

// ─────────────────────── Day breakdown ───────────────────────

class _DayBreakdownCard extends StatelessWidget {
  const _DayBreakdownCard({required this.state, required this.goal});
  final AnalyticsState state;
  final double goal;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Day by day',
      child: Column(
        children: state.days.reversed.map((d) {
          final pct = goal > 0 ? (d.caloriesAvg / goal).clamp(0.0, 1.5) : 0.0;
          final over = d.caloriesAvg > goal && goal > 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    '${d.date.day}/${d.date.month}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.gray500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: AppTheme.gray100,
                          color: over
                              ? AppTheme.amber500
                              : context.primary500,
                        ),
                      ),
                      if (d.scanCount > 0)
                        Positioned(
                          left: 8,
                          child: Text(
                            '${d.scanCount}×',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 70,
                  child: Text(
                    d.isEmpty ? '—' : '${d.caloriesAvg.round()} kcal',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: d.isEmpty
                          ? AppTheme.gray300
                          : (over ? AppTheme.amber700 : AppTheme.gray700),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────── Card shell ───────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gray900,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.gray400,
              ),
            ),
          ],
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
