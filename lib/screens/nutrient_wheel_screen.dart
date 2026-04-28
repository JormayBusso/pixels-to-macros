import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';
import 'nutrition_dashboard_screen.dart';

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

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const NutritionDashboardScreen(),
        ),
      ),
      child: Card(
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
              child: _WheelWithLabels(nutrients: nutrients),
            ),
          ],
        ),
      ),
    ),
    );  }
}
// ── Data models ──────────────────────────────────────────────────────────────

class _NutrientInfo {
  final String name;
  final String emoji;
  final double current;
  final double drv;
  final String unit;
  final Color color;
  final String? assetPath; // PNG icon for minerals

  _NutrientInfo({
    required this.name,
    required this.emoji,
    required this.current,
    required this.drv,
    required this.unit,
    required this.color,
    this.assetPath,
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
    _NutrientInfo(name: 'Calcium', emoji: '🦴', assetPath: 'assets/Calcium.png', current: t.calciumMg, drv: isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female, unit: 'mg', color: const Color(0xFFECEFF1)),
    _NutrientInfo(name: 'Iron', emoji: '🔴', assetPath: 'assets/Iron.png', current: t.ironMg, drv: isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female, unit: 'mg', color: const Color(0xFFB71C1C)),
    _NutrientInfo(name: 'Magnesium', emoji: '🧲', assetPath: 'assets/Magnesium.png', current: t.magnesiumMg, drv: isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female, unit: 'mg', color: const Color(0xFF7B1FA2)),
    _NutrientInfo(name: 'Potassium', emoji: '🍌', assetPath: 'assets/Potassium.png', current: t.potassiumMg, drv: isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female, unit: 'mg', color: const Color(0xFFFF6F00)),
    _NutrientInfo(name: 'Zinc', emoji: '⚡', assetPath: 'assets/Zink.png', current: t.zincMg, drv: isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female, unit: 'mg', color: const Color(0xFF0097A7)),
  ];
}

// ── Wheel with labels as Stack overlay ───────────────────────────────────────────

class _WheelWithLabels extends StatelessWidget {
  const _WheelWithLabels({required this.nutrients});
  final List<_NutrientInfo> nutrients;

  static const double _boxSize   = 220.0;
  static const double _outerR    = _boxSize / 2 - 4;  // 106
  static const double _innerR    = _outerR * 0.62;
  static const double _labelR    = _outerR + 14;       // centre of label
  static const double _labelSize = 20.0;               // widget size for labels

  @override
  Widget build(BuildContext context) {
    final collected = nutrients.where((n) => n.collected).length;
    final segAngle  = (2 * math.pi) / nutrients.length;
    const gap       = 0.02;

    final labels = <Widget>[];
    for (int i = 0; i < nutrients.length; i++) {
      final n         = nutrients[i];
      final midAngle  = -math.pi / 2 + i * segAngle + (segAngle - gap) / 2;
      final lx        = _boxSize / 2 + _labelR * math.cos(midAngle);
      final ly        = _boxSize / 2 + _labelR * math.sin(midAngle);
      final half      = _labelSize / 2;

      Widget label;
      if (n.assetPath != null) {
        label = Image.asset(
          n.assetPath!,
          width: _labelSize,
          height: _labelSize,
          fit: BoxFit.contain,
        );
      } else {
        label = Text(
          n.emoji,
          style: const TextStyle(fontSize: 13, height: 1),
        );
      }

      labels.add(Positioned(
        left:  lx - half,
        top:   ly - half,
        width:  _labelSize,
        height: _labelSize,
        child:  Center(child: label),
      ));
    }

    return SizedBox(
      width:  _boxSize,
      height: _boxSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(_boxSize, _boxSize),
            painter: _WheelPainter(
              nutrients:  nutrients,
              outerR:     _outerR,
              innerR:     _innerR,
            ),
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
          ...labels,
        ],
      ),
    );
  }
}

// ── Wheel painter ────────────────────────────────────────────────────────────

class _WheelPainter extends CustomPainter {
  final List<_NutrientInfo> nutrients;
  final double outerR;
  final double innerR;

  _WheelPainter({
    required this.nutrients,
    required this.outerR,
    required this.innerR,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final segAngle = (2 * math.pi) / nutrients.length;
    const gap = 0.02;

    for (int i = 0; i < nutrients.length; i++) {
      final n = nutrients[i];
      final startAngle = -math.pi / 2 + i * segAngle + gap / 2;
      final sweep = segAngle - gap;

      // Background arc (dim)
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: (outerR + innerR) / 2),
        startAngle,
        sweep,
        false,
        Paint()
          ..color = n.color.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = outerR - innerR
          ..strokeCap = StrokeCap.butt,
      );

      // Filled arc (progress)
      if (n.ratio > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: (outerR + innerR) / 2),
          startAngle,
          sweep * n.ratio,
          false,
          Paint()
            ..color = n.collected ? n.color : n.color.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = outerR - innerR
            ..strokeCap = StrokeCap.butt,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.nutrients != nutrients || old.outerR != outerR;
}

