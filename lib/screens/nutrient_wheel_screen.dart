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
    final drv = NutrientDRV.forContext(
      isMale: prefs.gender != UserGender.female,
      goal: prefs.nutritionGoal,
    );
    final nutrients = _buildNutrientList(intake.nutrientTotals, drv);
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
                    onSelect: (nutrient) => _showSingleNutrientDetail(
                      context,
                      nutrient: nutrient,
                    ),
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
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _WheelDetailSheet(
        nutrients: nutrients,
        score: score,
        onTarget: onTarget,
        low: low,
      ),
    );
  }

  void _showSingleNutrientDetail(
    BuildContext context, {
    required _NutrientInfo nutrient,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SingleNutrientSheet(nutrient: nutrient),
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
    required this.role,
    required this.sources,
    required this.lowTip,
    required this.highTip,
    this.emoji,
    this.assetPath,
    this.upperLimit,
  });

  final String name;
  final double current;
  final double drv;
  final String unit;
  final Color color;
  final String role;
  final String sources;
  final String lowTip;
  final String highTip;
  final String? emoji;
  final String? assetPath;
  final double? upperLimit;

  double get rawRatio => drv > 0 ? current / drv : 0;
  double get ratio => rawRatio.clamp(0.0, 1.0);
  int get percent => (rawRatio * 100).round().clamp(0, 999);
  bool get isAboveUpperLimit => upperLimit != null && current > upperLimit!;

  String get status {
    if (isAboveUpperLimit) return 'Too high';
    if (rawRatio >= 0.95) return 'On target';
    if (rawRatio >= 0.60) return 'Building';
    return 'Low';
  }

  Color statusColor(BuildContext context) {
    if (isAboveUpperLimit) return AppTheme.red500;
    if (rawRatio >= 0.95) return context.primary600;
    if (rawRatio >= 0.60) return AppTheme.amber600;
    return AppTheme.red500;
  }

  String get actionText {
    if (isAboveUpperLimit) return highTip;
    if (rawRatio < 0.60) return lowTip;
    if (rawRatio < 0.95) {
      return 'You are close to target. Add a modest serving from the source list if it fits today\'s meal plan.';
    }
    return 'This is in a useful range today. Keep variety across meals so coverage stays balanced without relying on one food.';
  }

  String get targetText {
    final upper =
        upperLimit == null ? '' : ' · upper limit ${fmt(upperLimit!)} $unit';
    return 'Target ${fmt(drv)} $unit$upper';
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

List<_NutrientInfo> _buildNutrientList(NutrientTotals totals, NutrientDRV drv) {
  return [
    _NutrientInfo(
      name: 'Dietary Fiber',
      emoji: '🌾',
      current: totals.fiberG,
      drv: drv.fiberG,
      unit: 'g',
      color: const Color(0xFF7A5C3A),
      role:
          'Feeds gut bacteria, supports bowel regularity, slows glucose absorption, and improves fullness.',
      sources:
          'Oats, beans, lentils, berries, apples, whole grains, vegetables, chia, flax, nuts.',
      lowTip:
          'Add a fiber-rich side such as beans, vegetables, oats, fruit, or seeds. Increase gradually with enough fluids.',
      highTip:
          'Very high fiber can cause bloating if it rises too fast. Spread it across meals and keep hydration steady.',
    ),
    _NutrientInfo(
      name: 'Vitamin A',
      emoji: '🥕',
      current: totals.vitaminAUg,
      drv: drv.vitaminAUg,
      unit: 'μg',
      color: const Color(0xFFE7811D),
      upperLimit: 3000,
      role:
          'Supports night vision, immune defense, skin integrity, and cell growth.',
      sources:
          'Carrot, sweet potato, pumpkin, spinach, kale, eggs, dairy, liver in small portions.',
      lowTip:
          'Add orange vegetables or leafy greens. Pairing with some fat improves absorption.',
      highTip:
          'Vitamin A can become unhealthy when repeatedly high, especially from retinol supplements or liver.',
    ),
    _NutrientInfo(
      name: 'Vitamin C',
      emoji: '🍊',
      current: totals.vitaminCMg,
      drv: drv.vitaminCMg,
      unit: 'mg',
      color: const Color(0xFFD6A600),
      upperLimit: 2000,
      role:
          'Builds collagen, supports immune cells, improves iron absorption, and acts as an antioxidant.',
      sources:
          'Citrus, kiwi, strawberries, bell pepper, broccoli, potatoes, Brussels sprouts.',
      lowTip:
          'Add a fresh fruit or vegetable with vitamin C, especially next to iron-rich foods.',
      highTip:
          'Very high vitamin C can irritate digestion. Food sources are usually easier to tolerate than large supplements.',
    ),
    _NutrientInfo(
      name: 'Vitamin D',
      emoji: '☀️',
      current: totals.vitaminDUg,
      drv: drv.vitaminDUg,
      unit: 'μg',
      color: const Color(0xFFC79000),
      upperLimit: 100,
      role:
          'Helps absorb calcium, supports bones, immune function, and muscle performance.',
      sources:
          'Fatty fish, eggs, fortified dairy or plant milk, fortified cereals, and responsible sunlight exposure.',
      lowTip:
          'Choose fortified foods, eggs, or fatty fish. Many people need a clinician-guided supplement when intake stays low.',
      highTip:
          'Vitamin D is fat-soluble. Repeated excess can raise calcium too much, so high supplement doses need supervision.',
    ),
    _NutrientInfo(
      name: 'Vitamin E',
      emoji: '🌻',
      current: totals.vitaminEMg,
      drv: drv.vitaminEMg,
      unit: 'mg',
      color: const Color(0xFF4C8C3A),
      upperLimit: 1000,
      role:
          'Protects cell membranes from oxidative stress and supports immune signaling.',
      sources:
          'Sunflower seeds, almonds, hazelnuts, avocado, spinach, olive oil, wheat germ.',
      lowTip:
          'Add nuts, seeds, avocado, or a little olive oil to meals that already have vegetables or grains.',
      highTip:
          'Repeated high vitamin E, usually from supplements, can affect bleeding risk. Keep excess in check.',
    ),
    _NutrientInfo(
      name: 'Vitamin K',
      emoji: '🥬',
      current: totals.vitaminKUg,
      drv: drv.vitaminKUg,
      unit: 'μg',
      color: const Color(0xFF2F7D32),
      role: 'Supports blood clotting and helps direct calcium into bones.',
      sources:
          'Kale, spinach, broccoli, Brussels sprouts, cabbage, parsley, fermented foods.',
      lowTip:
          'Add leafy greens or cruciferous vegetables. Keep intake consistent if using anticoagulant medication.',
      highTip:
          'No standard food-based upper limit is set, but sudden changes can matter for anticoagulant medication.',
    ),
    _NutrientInfo(
      name: 'Folate (B9)',
      emoji: '🫘',
      current: totals.folateMcg,
      drv: drv.folateMcg,
      unit: 'μg',
      color: const Color(0xFF43A047),
      upperLimit: 1000,
      role:
          'Needed for DNA synthesis, red blood cell formation, and nervous-system support.',
      sources:
          'Lentils, beans, asparagus, spinach, avocado, oranges, fortified grains.',
      lowTip:
          'Add legumes or leafy greens. Folate pairs well with B12-rich foods for blood and nerve health.',
      highTip:
          'Very high folic acid from fortified foods or supplements can mask B12 deficiency, so balance matters.',
    ),
    _NutrientInfo(
      name: 'Vitamin B12',
      emoji: '🥩',
      current: totals.b12Mcg,
      drv: drv.b12Mcg,
      unit: 'μg',
      color: const Color(0xFFC2185B),
      role:
          'Supports nerves, red blood cells, DNA synthesis, and energy metabolism.',
      sources:
          'Fish, meat, eggs, dairy, fortified plant milks, fortified nutritional yeast.',
      lowTip:
          'Add an animal food or fortified vegan source. Vegan users usually need reliable fortified foods or supplements.',
      highTip:
          'No food-based upper limit is set for B12; very high values usually come from supplements.',
    ),
    _NutrientInfo(
      name: 'Calcium',
      assetPath: 'assets/Calcium.png',
      current: totals.calciumMg,
      drv: drv.calciumMg,
      unit: 'mg',
      color: const Color(0xFF78909C),
      upperLimit: 2500,
      role:
          'Builds bones and teeth, supports muscle contraction, nerves, and heartbeat regulation.',
      sources:
          'Dairy, fortified plant milk, calcium-set tofu, sardines, kale, bok choy, yogurt.',
      lowTip:
          'Add a calcium-rich serving such as yogurt, fortified milk, tofu, or leafy greens.',
      highTip:
          'Repeated excess calcium, especially from supplements, can raise kidney-stone risk and interfere with other minerals.',
    ),
    _NutrientInfo(
      name: 'Iron',
      assetPath: 'assets/Iron.png',
      current: totals.ironMg,
      drv: drv.ironMg,
      unit: 'mg',
      color: const Color(0xFFB71C1C),
      upperLimit: 45,
      role:
          'Carries oxygen in blood, supports energy, cognition, immunity, and exercise capacity.',
      sources:
          'Beef, poultry, fish, lentils, beans, tofu, spinach, fortified grains, pumpkin seeds.',
      lowTip:
          'Pair iron foods with vitamin C. Avoid tea or coffee directly with iron-rich meals if intake is low.',
      highTip:
          'Too much iron can be harmful. High supplement doses should be clinician-guided.',
    ),
    _NutrientInfo(
      name: 'Magnesium',
      assetPath: 'assets/Magnesium.png',
      current: totals.magnesiumMg,
      drv: drv.magnesiumMg,
      unit: 'mg',
      color: const Color(0xFF7B1FA2),
      role:
          'Supports muscle relaxation, glucose control, nerves, blood pressure, and energy production.',
      sources:
          'Pumpkin seeds, almonds, cashews, oats, legumes, dark chocolate, spinach, whole grains.',
      lowTip:
          'Add nuts, seeds, legumes, oats, or greens. Magnesium is often low when meals lack whole plant foods.',
      highTip:
          'Food magnesium is usually safe; very high supplemental magnesium can upset digestion.',
    ),
    _NutrientInfo(
      name: 'Potassium',
      assetPath: 'assets/Potassium.png',
      current: totals.potassiumMg,
      drv: drv.potassiumMg,
      unit: 'mg',
      color: const Color(0xFFEF6C00),
      role:
          'Balances fluids, supports blood pressure, nerve signals, and muscle contraction.',
      sources:
          'Potatoes, beans, lentils, bananas, yogurt, spinach, tomatoes, avocado, salmon.',
      lowTip:
          'Add a potassium-rich whole food such as potato, legumes, banana, yogurt, tomatoes, or leafy greens.',
      highTip:
          'Very high potassium can matter for kidney disease or some medications. Food intake should stay balanced.',
    ),
    _NutrientInfo(
      name: 'Zinc',
      assetPath: 'assets/Zink.png',
      current: totals.zincMg,
      drv: drv.zincMg,
      unit: 'mg',
      color: const Color(0xFF00838F),
      upperLimit: 40,
      role:
          'Supports immunity, wound healing, taste, hormone signaling, and protein synthesis.',
      sources:
          'Oysters, beef, poultry, yogurt, pumpkin seeds, beans, chickpeas, cashews.',
      lowTip:
          'Add zinc-rich protein, seafood, dairy, legumes, or seeds. Soaking legumes can improve mineral availability.',
      highTip:
          'Repeated excess zinc can reduce copper status and upset digestion, especially from supplements.',
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
    required this.onSelect,
  });

  final List<_NutrientInfo> nutrients;
  final int score;
  final int onTarget;
  final ValueChanged<_NutrientInfo> onSelect;

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
            child: GestureDetector(
              onTap: () => onSelect(nutrient),
              behavior: HitTestBehavior.opaque,
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
    final strokeWidth =
        size.shortestSide * 0.120; // slightly thicker for clarity
    final segmentAngle = (2 * math.pi) / nutrients.length;
    const gap = 0.045;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < nutrients.length; i++) {
      final nutrient = nutrients[i];
      final start = -math.pi / 2 + i * segmentAngle + gap / 2;
      final sweep = segmentAngle - gap;

      // Track (background arc): flat caps so there is no dot at the start.
      final basePaint = Paint()
        ..color = AppTheme.gray200
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      // Fill arc: flat caps on both ends — no bleeding dot.
      final fillPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            nutrient.color.withValues(alpha: 0.80),
            nutrient.color,
          ],
          startAngle: start,
          endAngle: start + sweep,
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, start, sweep, false, basePaint);
      if (nutrient.ratio > 0.01) {
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
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
                color: AppTheme.gray500,
              ),
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
          const Text(
            'Nutrient-specific guidance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.gray100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.gray400),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              nutrient.role,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.gray600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              nutrient.actionText,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleNutrientSheet extends StatelessWidget {
  const _SingleNutrientSheet({required this.nutrient});

  final _NutrientInfo nutrient;

  @override
  Widget build(BuildContext context) {
    final color = nutrient.statusColor(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: nutrient.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: nutrient.iconWidget(
                  size: nutrient.assetPath == null ? 22 : 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nutrient.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.gray900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nutrient.targetText,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.gray400),
                    ),
                  ],
                ),
              ),
              _ScorePill(score: nutrient.percent.clamp(0, 100)),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
                color: AppTheme.gray500,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: nutrient.ratio,
              minHeight: 10,
              backgroundColor: AppTheme.gray100,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${nutrient.fmt(nutrient.current)} ${nutrient.unit} logged today · ${nutrient.status}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 16),
          _NutrientInfoBlock(
            title: 'What it does',
            body: nutrient.role,
            icon: Icons.psychology_outlined,
          ),
          const SizedBox(height: 10),
          _NutrientInfoBlock(
            title: 'Best food sources',
            body: nutrient.sources,
            icon: Icons.restaurant_menu_outlined,
          ),
          const SizedBox(height: 10),
          _NutrientInfoBlock(
            title: 'What to do today',
            body: nutrient.actionText,
            icon: Icons.tips_and_updates_outlined,
          ),
        ],
      ),
    );
  }
}

class _NutrientInfoBlock extends StatelessWidget {
  const _NutrientInfoBlock({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gray50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.gray100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.primary600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.gray800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.gray600,
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
