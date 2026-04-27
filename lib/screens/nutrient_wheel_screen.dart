import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Embeddable compact wheel widget (no Scaffold, no weekly chart)
// Used by NutritionDashboardScreen to embed the wheel above macronutrients.
// ─────────────────────────────────────────────────────────────────────────────

/// A compact view of today's micronutrient wheel that can be embedded
/// inside any scroll view.  Shows the ring + collection count only.
class NutrientWheelWidget extends ConsumerWidget {
  const NutrientWheelWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final nutrients = _buildNutrientList(intake.nutrientTotals, isMale);
    final collected = nutrients.where((n) => n.ratio >= 1.0).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(
              '$collected / ${nutrients.length} nutrients collected today',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.primary700,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 220,
                height: 220,
                child: CustomPaint(
                  painter: _WheelPainter(nutrients: nutrients),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          collected == nutrients.length ? '🏆' : '🎯',
                          style: const TextStyle(fontSize: 28),
                        ),
                        Text(
                          collected == nutrients.length
                              ? 'All collected!'
                              : 'Keep eating!',
                          style: TextStyle(
                            fontSize: 11,
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
          ],
        ),
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


