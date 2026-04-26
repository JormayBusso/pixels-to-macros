import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Micronutrient Wheel Collection Game + Weekly Overview.
///
/// Shows a colourful segmented ring where each segment represents a
/// micronutrient.  Segments fill up as the user eats foods rich in that
/// nutrient.  A weekly bar-chart summary sits below the wheel.
class NutrientWheelScreen extends ConsumerStatefulWidget {
  const NutrientWheelScreen({super.key});

  @override
  ConsumerState<NutrientWheelScreen> createState() =>
      _NutrientWheelScreenState();
}

class _NutrientWheelScreenState extends ConsumerState<NutrientWheelScreen> {
  List<_DaySummary> _weeklySummaries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWeekly();
  }

  Future<void> _loadWeekly() async {
    final allScans = await DatabaseService.instance.getAllScanResults();
    final now = DateTime.now();
    final summaries = <_DaySummary>[];

    for (int d = 6; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      final nextDay = day.add(const Duration(days: 1));

      final dayScans = allScans.where((s) =>
          s.timestamp.isAfter(day) && s.timestamp.isBefore(nextDay));

      var totals = const NutrientTotals();
      for (final scan in dayScans) {
        for (final food in scan.foods) {
          final foodData =
              await DatabaseService.instance.getFoodByLabel(food.label);
          if (foodData != null && foodData.kcalPer100g > 0) {
            final avgCal = (food.caloriesMin + food.caloriesMax) / 2;
            final weightG = avgCal / (foodData.kcalPer100g / 100);
            totals = totals +
                estimateNutrientsForFood(
                  category: foodData.category,
                  weightG: weightG,
                );
          }
        }
      }
      summaries.add(_DaySummary(
        date: day,
        totals: totals,
        scanCount: dayScans.length,
      ));
    }

    if (mounted) {
      setState(() {
        _weeklySummaries = summaries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;

    final nutrients = _buildNutrientList(intake.nutrientTotals, isMale);
    final collected = nutrients.where((n) => n.ratio >= 1.0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrient Wheel'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Collection badge ───────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Text(
                        '$collected / ${nutrients.length}',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: context.primary700,
                        ),
                      ),
                      const Text(
                        'nutrients collected today',
                        style: TextStyle(fontSize: 13, color: AppTheme.gray400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Wheel ──────────────────────────────────────────────
                Center(
                  child: SizedBox(
                    width: 260,
                    height: 260,
                    child: CustomPaint(
                      painter: _WheelPainter(nutrients: nutrients),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              collected == nutrients.length ? '🏆' : '🎯',
                              style: const TextStyle(fontSize: 32),
                            ),
                            Text(
                              collected == nutrients.length
                                  ? 'All collected!'
                                  : 'Keep eating!',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: collected == nutrients.length
                                    ? context.primary700
                                    : AppTheme.gray400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Nutrient list ──────────────────────────────────────
                ...nutrients.map((n) => _NutrientRow(nutrient: n)),
                const SizedBox(height: 24),

                // ── Weekly overview ────────────────────────────────────
                const Text(
                  'Weekly Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gray700,
                  ),
                ),
                const SizedBox(height: 12),
                _WeeklyChart(summaries: _weeklySummaries, isMale: isMale),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

// ── Data models ──────────────────────────────────────────────────────────────

class _NutrientInfo {
  final String name;
  final String emoji;
  final double current;
  final double drv;
  final String unit;
  final Color color;

  _NutrientInfo({
    required this.name,
    required this.emoji,
    required this.current,
    required this.drv,
    required this.unit,
    required this.color,
  });

  double get ratio => drv > 0 ? (current / drv).clamp(0.0, 1.0) : 0.0;
  bool get collected => ratio >= 1.0;
  int get percent => (ratio * 100).round();
}

class _DaySummary {
  final DateTime date;
  final NutrientTotals totals;
  final int scanCount;
  const _DaySummary({required this.date, required this.totals, required this.scanCount});
}

List<_NutrientInfo> _buildNutrientList(NutrientTotals t, bool isMale) {
  return [
    _NutrientInfo(name: 'Fiber', emoji: '🌾', current: t.fiberG, drv: NutrientDRV.fiberG, unit: 'g', color: const Color(0xFF8D6E63)),
    _NutrientInfo(name: 'Vitamin A', emoji: '🥕', current: t.vitaminAUg, drv: isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female, unit: 'µg', color: const Color(0xFFFF9800)),
    _NutrientInfo(name: 'Vitamin C', emoji: '🍊', current: t.vitaminCMg, drv: isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female, unit: 'mg', color: const Color(0xFFFFEB3B)),
    _NutrientInfo(name: 'Vitamin D', emoji: '☀️', current: t.vitaminDUg, drv: NutrientDRV.vitaminDUg, unit: 'µg', color: const Color(0xFFFFC107)),
    _NutrientInfo(name: 'Vitamin E', emoji: '🌻', current: t.vitaminEMg, drv: NutrientDRV.vitaminEMg, unit: 'mg', color: const Color(0xFF4CAF50)),
    _NutrientInfo(name: 'Vitamin K', emoji: '🥦', current: t.vitaminKUg, drv: isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female, unit: 'µg', color: const Color(0xFF388E3C)),
    _NutrientInfo(name: 'Folate', emoji: '🥬', current: t.folateMcg, drv: NutrientDRV.folateMcg, unit: 'µg', color: const Color(0xFF66BB6A)),
    _NutrientInfo(name: 'B12', emoji: '🥩', current: t.b12Mcg, drv: NutrientDRV.b12Mcg, unit: 'µg', color: const Color(0xFFE91E63)),
    _NutrientInfo(name: 'Calcium', emoji: '🦴', current: t.calciumMg, drv: isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female, unit: 'mg', color: const Color(0xFFECEFF1)),
    _NutrientInfo(name: 'Iron', emoji: '🔴', current: t.ironMg, drv: isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female, unit: 'mg', color: const Color(0xFFB71C1C)),
    _NutrientInfo(name: 'Magnesium', emoji: '🧲', current: t.magnesiumMg, drv: isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female, unit: 'mg', color: const Color(0xFF7B1FA2)),
    _NutrientInfo(name: 'Potassium', emoji: '🍌', current: t.potassiumMg, drv: isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female, unit: 'mg', color: const Color(0xFFFF6F00)),
    _NutrientInfo(name: 'Zinc', emoji: '⚡', current: t.zincMg, drv: isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female, unit: 'mg', color: const Color(0xFF0097A7)),
  ];
}

// ── Wheel painter ────────────────────────────────────────────────────────────

class _WheelPainter extends CustomPainter {
  final List<_NutrientInfo> nutrients;
  _WheelPainter({required this.nutrients});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2 - 4;
    final innerR = outerR * 0.62;
    final segAngle = (2 * math.pi) / nutrients.length;
    final gap = 0.02; // small gap between segments

    for (int i = 0; i < nutrients.length; i++) {
      final n = nutrients[i];
      final startAngle = -math.pi / 2 + i * segAngle + gap / 2;
      final sweep = segAngle - gap;

      // Background arc (dim)
      final bgPaint = Paint()
        ..color = n.color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR - innerR
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: (outerR + innerR) / 2),
        startAngle,
        sweep,
        false,
        bgPaint,
      );

      // Filled arc (progress)
      final fillPaint = Paint()
        ..color = n.collected ? n.color : n.color.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerR - innerR
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: (outerR + innerR) / 2),
        startAngle,
        sweep * n.ratio,
        false,
        fillPaint,
      );

      // Emoji label outside
      final midAngle = startAngle + sweep / 2;
      final labelR = outerR + 2;
      final lx = center.dx + labelR * math.cos(midAngle);
      final ly = center.dy + labelR * math.sin(midAngle);
      final tp = TextPainter(
        text: TextSpan(text: n.emoji, style: const TextStyle(fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => true;
}

// ── Nutrient row ─────────────────────────────────────────────────────────────

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({required this.nutrient});
  final _NutrientInfo nutrient;

  @override
  Widget build(BuildContext context) {
    final n = nutrient;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(n.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      n.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: n.collected ? context.primary700 : AppTheme.gray700,
                      ),
                    ),
                    if (n.collected) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle, size: 14, color: context.primary600),
                    ],
                    const Spacer(),
                    Text(
                      '${n.current.toStringAsFixed(1)} / ${n.drv.toStringAsFixed(0)} ${n.unit}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.gray400),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: n.ratio,
                    backgroundColor: n.color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(n.color),
                    minHeight: 5,
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

// ── Weekly chart ─────────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.summaries, required this.isMale});
  final List<_DaySummary> summaries;
  final bool isMale;

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) {
      return const Text('No data yet.', style: TextStyle(color: AppTheme.gray400));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Bar chart: each day gets a row with number of nutrients collected
            ...summaries.map((s) {
              final nutrients = _buildNutrientList(s.totals, isMale);
              final collected = nutrients.where((n) => n.ratio >= 1.0).length;
              final total = nutrients.length;
              final ratio = total > 0 ? collected / total : 0.0;

              const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final dayLabel = dayNames[s.date.weekday - 1];

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        dayLabel,
                        style: const TextStyle(fontSize: 11, color: AppTheme.gray600),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: context.primary100,
                          valueColor: AlwaysStoppedAnimation(
                            collected == total
                                ? const Color(0xFF4CAF50)
                                : context.primary400,
                          ),
                          minHeight: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$collected/$total',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: collected == total
                              ? const Color(0xFF4CAF50)
                              : AppTheme.gray600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
