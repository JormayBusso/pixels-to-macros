import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

class NutrientWheelWidget extends ConsumerWidget {
  const NutrientWheelWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final nutrients = _buildNutrientList(
      intake.nutrientTotals,
      prefs.gender == UserGender.male,
    );
    final onTarget =
        nutrients.where((nutrient) => nutrient.rawRatio >= 0.95).length;
    final low = nutrients.where((nutrient) => nutrient.rawRatio < 0.60).length;
    final score = nutrients.isEmpty
        ? 0
        : (nutrients
                    .map((nutrient) => nutrient.ratio)
                    .fold<double>(0, (sum, ratio) => sum + ratio) /
                nutrients.length *
                100)
            .round();

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () => _showNutrientDetails(
          context,
          nutrients: nutrients,
          score: score,
          onTarget: onTarget,
          low: low,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: context.primary100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        Icon(Icons.radar_outlined, color: context.primary700),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Micronutrient Coverage',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.gray900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Targets from today\'s logged foods',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _ScorePill(score: score),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 500;
                  final wheel = _WheelWithLabels(
                    nutrients: nutrients,
                    score: score,
                    onTarget: onTarget,
                  );
                  final details = _NutrientWheelDetails(
                    onTarget: onTarget,
                    low: low,
                    total: nutrients.length,
                  );

                  if (wide) {
                    return Row(
                      children: [
                        wheel,
                        const SizedBox(width: 18),
                        Expanded(child: details),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Center(child: wheel),
                      const SizedBox(height: 14),
                      details,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNutrientDetails(
    BuildContext context, {
    required List<_NutrientInfo> nutrients,
    required int score,
    required int onTarget,
    required int low,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _WheelDetailSheet(
        nutrients: nutrients,
        score: score,
        onTarget: onTarget,
        low: low,
      ),
    );
  }
}

class _NutrientInfo {
  const _NutrientInfo({
    required this.name,
    required this.current,
    required this.drv,
    required this.unit,
    required this.color,
    this.emoji,
    this.assetPath,
  });

  final String name;
  final double current;
  final double drv;
  final String unit;
  final Color color;
  final String? emoji;
  final String? assetPath;

  double get rawRatio => drv > 0 ? current / drv : 0;
  double get ratio => rawRatio.clamp(0.0, 1.0);
  int get percent => (rawRatio * 100).round().clamp(0, 999);

  String get status {
    if (rawRatio >= 0.95) return 'On target';
    if (rawRatio >= 0.60) return 'Building';
    return 'Low';
  }

  Color statusColor(BuildContext context) {
    if (rawRatio >= 0.95) return context.primary600;
    if (rawRatio >= 0.60) return AppTheme.amber600;
    return AppTheme.red500;
  }

  String fmt(double value) {
    if (value == 0) return '0';
    if (value < 10) return value.toStringAsFixed(1);
    return value.round().toString();
  }

  Widget iconWidget({double size = 18}) {
    final path = assetPath;
    if (path != null) {
      return Image.asset(path, width: size, height: size, fit: BoxFit.contain);
    }
    return Text(
      emoji ?? '',
      style: TextStyle(fontSize: size, height: 1),
      textAlign: TextAlign.center,
    );
  }
}

List<_NutrientInfo> _buildNutrientList(NutrientTotals totals, bool isMale) {
  return [
    _NutrientInfo(
      name: 'Dietary Fiber',
      emoji: '🌾',
      current: totals.fiberG,
      drv: NutrientDRV.fiberG,
      unit: 'g',
      color: const Color(0xFF7A5C3A),
    ),
    _NutrientInfo(
      name: 'Vitamin A',
      emoji: '🥕',
      current: totals.vitaminAUg,
      drv: isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female,
      unit: 'μg',
      color: const Color(0xFFE7811D),
    ),
    _NutrientInfo(
      name: 'Vitamin C',
      emoji: '🍊',
      current: totals.vitaminCMg,
      drv: isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female,
      unit: 'mg',
      color: const Color(0xFFD6A600),
    ),
    _NutrientInfo(
      name: 'Vitamin D',
      emoji: '☀️',
      current: totals.vitaminDUg,
      drv: NutrientDRV.vitaminDUg,
      unit: 'μg',
      color: const Color(0xFFC79000),
    ),
    _NutrientInfo(
      name: 'Vitamin E',
      emoji: '🌻',
      current: totals.vitaminEMg,
      drv: NutrientDRV.vitaminEMg,
      unit: 'mg',
      color: const Color(0xFF4C8C3A),
    ),
    _NutrientInfo(
      name: 'Vitamin K',
      emoji: '🥬',
      current: totals.vitaminKUg,
      drv: isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female,
      unit: 'μg',
      color: const Color(0xFF2F7D32),
    ),
    _NutrientInfo(
      name: 'Folate (B9)',
      emoji: '🫘',
      current: totals.folateMcg,
      drv: NutrientDRV.folateMcg,
      unit: 'μg',
      color: const Color(0xFF43A047),
    ),
    _NutrientInfo(
      name: 'Vitamin B12',
      emoji: '🥩',
      current: totals.b12Mcg,
      drv: NutrientDRV.b12Mcg,
      unit: 'μg',
      color: const Color(0xFFC2185B),
    ),
    _NutrientInfo(
      name: 'Calcium',
      assetPath: 'assets/Calcium.png',
      current: totals.calciumMg,
      drv: isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female,
      unit: 'mg',
      color: const Color(0xFF78909C),
    ),
    _NutrientInfo(
      name: 'Iron',
      assetPath: 'assets/Iron.png',
      current: totals.ironMg,
      drv: isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female,
      unit: 'mg',
      color: const Color(0xFFB71C1C),
    ),
    _NutrientInfo(
      name: 'Magnesium',
      assetPath: 'assets/Magnesium.png',
      current: totals.magnesiumMg,
      drv: isMale
          ? NutrientDRV.magnesiumMg_male
          : NutrientDRV.magnesiumMg_female,
      unit: 'mg',
      color: const Color(0xFF7B1FA2),
    ),
    _NutrientInfo(
      name: 'Potassium',
      assetPath: 'assets/Potassium.png',
      current: totals.potassiumMg,
      drv: isMale
          ? NutrientDRV.potassiumMg_male
          : NutrientDRV.potassiumMg_female,
      unit: 'mg',
      color: const Color(0xFFEF6C00),
    ),
    _NutrientInfo(
      name: 'Zinc',
      assetPath: 'assets/Zink.png',
      current: totals.zincMg,
      drv: isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female,
      unit: 'mg',
      color: const Color(0xFF00838F),
    ),
  ];
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.primary50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.primary200),
      ),
      child: Text(
        '$score%',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: context.primary700,
        ),
      ),
    );
  }
}

class _WheelWithLabels extends StatelessWidget {
  const _WheelWithLabels({
    required this.nutrients,
    required this.score,
    required this.onTarget,
  });

  final List<_NutrientInfo> nutrients;
  final int score;
  final int onTarget;

  static const double _boxSize = 244;
  static const double _labelRadius = 106;
  static const double _labelSize = 30;

  @override
  Widget build(BuildContext context) {
    final segmentAngle = (2 * math.pi) / nutrients.length;
    final labels = <Widget>[];
    for (var i = 0; i < nutrients.length; i++) {
      final nutrient = nutrients[i];
      final angle = -math.pi / 2 + i * segmentAngle + segmentAngle / 2;
      final x = _boxSize / 2 + _labelRadius * math.cos(angle);
      final y = _boxSize / 2 + _labelRadius * math.sin(angle);
      labels.add(
        Positioned(
          left: x - _labelSize / 2,
          top: y - _labelSize / 2,
          width: _labelSize,
          height: _labelSize,
          child: Tooltip(
            message: '${nutrient.name} · ${nutrient.percent}%',
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: nutrient.color.withValues(alpha: 0.35),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: nutrient.iconWidget(
                size: nutrient.assetPath == null ? 16 : 22,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: _boxSize,
      height: _boxSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(_boxSize, _boxSize),
            painter: _WheelPainter(nutrients: nutrients),
            child: Center(
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.gray200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.gray900,
                        height: 1,
                      ),
                    ),
                    const Text(
                      'score',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.gray400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$onTarget/${nutrients.length} target',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: context.primary700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ...labels,
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.nutrients});

  final List<_NutrientInfo> nutrients;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.36;
    final strokeWidth = size.shortestSide * 0.105;
    final segmentAngle = (2 * math.pi) / nutrients.length;
    const gap = 0.045;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < nutrients.length; i++) {
      final nutrient = nutrients[i];
      final start = -math.pi / 2 + i * segmentAngle + gap / 2;
      final sweep = segmentAngle - gap;
      final basePaint = Paint()
        ..color = AppTheme.gray200.withValues(alpha: 0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final fillPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            nutrient.color.withValues(alpha: 0.72),
            nutrient.color,
          ],
          startAngle: start,
          endAngle: start + sweep,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, start, sweep, false, basePaint);
      if (nutrient.ratio > 0) {
        canvas.drawArc(rect, start, sweep * nutrient.ratio, false, fillPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.nutrients != nutrients;
}

class _NutrientWheelDetails extends StatelessWidget {
  const _NutrientWheelDetails({
    required this.onTarget,
    required this.low,
    required this.total,
  });

  final int onTarget;
  final int low;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatBox(
            label: 'On target',
            value: '$onTarget',
            color: context.primary600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            label: 'Needs work',
            value: '$low',
            color: low == 0 ? context.primary600 : AppTheme.amber600,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            label: 'Tracked',
            value: '$total',
            color: AppTheme.gray700,
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray400,
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelDetailSheet extends StatelessWidget {
  const _WheelDetailSheet({
    required this.nutrients,
    required this.score,
    required this.onTarget,
    required this.low,
  });

  final List<_NutrientInfo> nutrients;
  final int score;
  final int onTarget;
  final int low;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: context.primary100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.radar_outlined, color: context.primary700),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Micronutrient Details',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.gray900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Today\'s vitamin and mineral coverage',
                      style: TextStyle(fontSize: 12, color: AppTheme.gray400),
                    ),
                  ],
                ),
              ),
              _ScorePill(score: score),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatBox(
                  label: 'On target',
                  value: '$onTarget',
                  color: context.primary600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatBox(
                  label: 'Needs work',
                  value: '$low',
                  color: low == 0 ? context.primary600 : AppTheme.amber600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...nutrients.map((nutrient) => _WheelDetailRow(nutrient: nutrient)),
        ],
      ),
    );
  }
}

class _WheelDetailRow extends StatelessWidget {
  const _WheelDetailRow({required this.nutrient});

  final _NutrientInfo nutrient;

  @override
  Widget build(BuildContext context) {
    final color = nutrient.statusColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: nutrient.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: nutrient.iconWidget(
              size: nutrient.assetPath == null ? 18 : 26,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nutrient.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gray700,
                        ),
                      ),
                    ),
                    Text(
                      '${nutrient.fmt(nutrient.current)} / ${nutrient.fmt(nutrient.drv)} ${nutrient.unit}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.gray400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: nutrient.ratio,
                    minHeight: 6,
                    backgroundColor: AppTheme.gray100,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${nutrient.percent}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  nutrient.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.gray400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
