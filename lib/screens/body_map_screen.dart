import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// 2D interactive body map.
///
/// Shows a greyed-out human silhouette with colored nutrient-status circles.
class BodyMapScreen extends ConsumerWidget {
  const BodyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final regions = _buildRegions(intake.nutrientTotals, isMale);

    return Scaffold(
      appBar: AppBar(title: const Text('Body Map')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          final imgW = w * 0.60;
          final imgH = h * 0.82;
          final imgLeft = (w - imgW) / 2;
          final imgTop = (h - imgH) / 2;

          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: imgW,
                    height: imgH,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: Image.asset(
                        'assets/anatomy_body.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              ...regions.map((region) {
                final sx = imgLeft + region.cx * imgW;
                final sy = imgTop + region.cy * imgH;
                final color = _scoreColor(region.score);
                final spotSize = region.size * 0.55;

                return Positioned(
                  left: sx - spotSize / 2,
                  top: sy - spotSize / 2,
                  child: GestureDetector(
                    onTap: () => _showDetail(context, region),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: spotSize,
                      height: spotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.72),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.45),
                            blurRadius: region.score > 0.7 ? 14 : 6,
                            spreadRadius: region.score > 0.7 ? 3 : 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              ...regions.map((region) {
                final sx = imgLeft + region.cx * imgW;
                final sy = imgTop + region.cy * imgH;
                final color = _scoreColor(region.score);
                final isLeft = region.labelSide == _LabelSide.left;
                final labelWidth =
                    isLeft ? (sx - 16).clamp(44.0, w) : (w - sx - 16);

                return Positioned(
                  left: isLeft ? 4 : (sx + 8),
                  top: sy - 10,
                  width: labelWidth,
                  child: GestureDetector(
                    onTap: () => _showDetail(context, region),
                    child: CustomPaint(
                      painter: _LineLabelPainter(
                        color: color,
                        isLeft: isLeft,
                        label: region.label,
                      ),
                      size: Size(labelWidth, 20),
                    ),
                  ),
                );
              }),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _LegendDot(
                          color: Colors.red.shade700,
                          label: 'Low / Over',
                        ),
                        const _LegendDot(
                            color: Colors.orange, label: 'Moderate'),
                        _LegendDot(
                          color: Colors.yellow.shade700,
                          label: 'Good',
                        ),
                        const _LegendDot(color: Colors.green, label: 'Great'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, _BodyRegion region) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _scoreColor(region.score).withValues(alpha: 0.2),
                    border: Border.all(
                      color: _scoreColor(region.score),
                      width: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        region.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${(region.score * 100).round()}% nourished',
                        style: TextStyle(
                          fontSize: 13,
                          color: _scoreColor(region.score),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              region.explanation,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.gray600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Key nutrients:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ...region.nutrients.map(
              (nutrient) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(
                        nutrient.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.gray600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: nutrient.ratio.clamp(0.0, 1.0),
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(
                            _scoreColor(nutrient.ratio),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(nutrient.ratio * 100).round().clamp(0, 999)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _LineLabelPainter extends CustomPainter {
  _LineLabelPainter({
    required this.color,
    required this.isLeft,
    required this.label,
  });

  final Color color;
  final bool isLeft;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final lineY = size.height / 2;
    if (isLeft) {
      canvas.drawLine(
        Offset(size.width, lineY),
        Offset(size.width - 20, lineY),
        paint,
      );
    } else {
      canvas.drawLine(Offset(0, lineY), Offset(20, lineY), paint);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: isLeft ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    );
    tp.layout(maxWidth: size.width - 24);

    final textX = isLeft ? (size.width - 24 - tp.width) : 24.0;
    tp.paint(canvas, Offset(textX, lineY - tp.height / 2));
  }

  @override
  bool shouldRepaint(_LineLabelPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.label != label;
}

Color _scoreColor(double score) {
  if (score > 1.6) return const Color(0xFFB71C1C);
  if (score >= 1.0) return const Color(0xFF4CAF50);
  if (score >= 0.7) return const Color(0xFF9CCC65);
  if (score >= 0.4) return const Color(0xFFFF9800);
  return const Color(0xFFE53935);
}

class _NutrientRatio {
  const _NutrientRatio(this.name, this.ratio);

  final String name;
  final double ratio;
}

enum _LabelSide { left, right }

class _BodyRegion {
  const _BodyRegion({
    required this.label,
    required this.cx,
    required this.cy,
    required this.labelSide,
    this.size = 48,
    required this.score,
    required this.explanation,
    required this.nutrients,
  });

  final String label;
  final double cx;
  final double cy;
  final _LabelSide labelSide;
  final double size;
  final double score;
  final String explanation;
  final List<_NutrientRatio> nutrients;
}

List<_BodyRegion> _buildRegions(NutrientTotals totals, bool isMale) {
  double ratio(double current, double drv) => drv > 0 ? current / drv : 0;
  double avg(List<double> values) =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

  final vitA = ratio(
    totals.vitaminAUg,
    isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female,
  );
  final vitC = ratio(
    totals.vitaminCMg,
    isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female,
  );
  final vitD = ratio(totals.vitaminDUg, NutrientDRV.vitaminDUg);
  final vitE = ratio(totals.vitaminEMg, NutrientDRV.vitaminEMg);
  final vitK = ratio(
    totals.vitaminKUg,
    isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female,
  );
  final folate = ratio(totals.folateMcg, NutrientDRV.folateMcg);
  final b12 = ratio(totals.b12Mcg, NutrientDRV.b12Mcg);
  final calcium = ratio(
    totals.calciumMg,
    isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female,
  );
  final iron = ratio(
    totals.ironMg,
    isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female,
  );
  final mag = ratio(
    totals.magnesiumMg,
    isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female,
  );
  final potassium = ratio(
    totals.potassiumMg,
    isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female,
  );
  final zinc = ratio(
    totals.zincMg,
    isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female,
  );
  final fiber = ratio(totals.fiberG, NutrientDRV.fiberG);

  return [
    _BodyRegion(
      label: 'Brain',
      cx: 0.50,
      cy: 0.073,
      labelSide: _LabelSide.left,
      size: 46,
      score: avg([b12, folate, iron]).clamp(0.0, 2.0),
      explanation:
          'B12 and folate support nerve function and cognitive health. Iron carries oxygen to the brain.',
      nutrients: [
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
        _NutrientRatio('Iron', iron),
      ],
    ),
    _BodyRegion(
      label: 'Eyes',
      cx: 0.50,
      cy: 0.135,
      labelSide: _LabelSide.right,
      size: 34,
      score: avg([vitA, vitC, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin A is essential for vision. Vitamin C and zinc protect against age-related macular degeneration.',
      nutrients: [
        _NutrientRatio('Vitamin A', vitA),
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Lungs',
      cx: 0.43,
      cy: 0.300,
      labelSide: _LabelSide.left,
      size: 44,
      score: avg([vitC, vitE, vitA]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C protects lung tissue. Vitamin E and A are antioxidants that defend against inflammation.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin A', vitA),
      ],
    ),
    _BodyRegion(
      label: 'Heart',
      cx: 0.54,
      cy: 0.320,
      labelSide: _LabelSide.right,
      size: 42,
      score: avg([potassium, mag, vitE]).clamp(0.0, 2.0),
      explanation:
          'Potassium regulates heartbeat. Magnesium relaxes blood vessels. Vitamin E prevents oxidative damage to cells.',
      nutrients: [
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Vitamin E', vitE),
      ],
    ),
    _BodyRegion(
      label: 'Immune System',
      cx: 0.56,
      cy: 0.230,
      labelSide: _LabelSide.right,
      size: 36,
      score: avg([vitC, vitD, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C, D, and zinc are the big three for immune defence. They help white blood cells fight infections.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Liver',
      cx: 0.42,
      cy: 0.410,
      labelSide: _LabelSide.left,
      size: 40,
      score: avg([vitE, vitK, b12]).clamp(0.0, 2.0),
      explanation:
          'The liver stores vitamins and detoxifies the body. Vitamin K is synthesised here and supports blood clotting.',
      nutrients: [
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin K', vitK),
        _NutrientRatio('B12', b12),
      ],
    ),
    _BodyRegion(
      label: 'Skin',
      cx: 0.68,
      cy: 0.430,
      labelSide: _LabelSide.right,
      size: 36,
      score: avg([vitC, vitE, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C produces collagen for skin elasticity. Vitamin E protects against UV damage. Zinc helps wound healing.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Gut',
      cx: 0.50,
      cy: 0.515,
      labelSide: _LabelSide.right,
      size: 44,
      score: avg([fiber, mag, potassium]).clamp(0.0, 2.0),
      explanation:
          'Dietary fiber feeds healthy gut bacteria and aids digestion. Magnesium helps with muscle contractions in the intestines.',
      nutrients: [
        _NutrientRatio('Fiber', fiber),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
      ],
    ),
    _BodyRegion(
      label: 'Muscles',
      cx: 0.34,
      cy: 0.560,
      labelSide: _LabelSide.left,
      score: avg([mag, potassium, calcium]).clamp(0.0, 2.0),
      explanation:
          'Magnesium and potassium prevent cramps and support muscle contraction. Calcium triggers muscle fibers.',
      nutrients: [
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Calcium', calcium),
      ],
    ),
    _BodyRegion(
      label: 'Bones',
      cx: 0.56,
      cy: 0.620,
      labelSide: _LabelSide.right,
      score: avg([calcium, vitD, vitK]).clamp(0.0, 2.0),
      explanation:
          'Calcium builds bone density. Vitamin D helps absorb calcium. Vitamin K directs calcium to bones instead of arteries.',
      nutrients: [
        _NutrientRatio('Calcium', calcium),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Vitamin K', vitK),
      ],
    ),
    _BodyRegion(
      label: 'Blood',
      cx: 0.42,
      cy: 0.700,
      labelSide: _LabelSide.left,
      size: 38,
      score: avg([iron, b12, folate]).clamp(0.0, 2.0),
      explanation:
          'Iron is the core of haemoglobin. B12 and folate are needed to produce healthy red blood cells.',
      nutrients: [
        _NutrientRatio('Iron', iron),
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
      ],
    ),
  ];
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.gray600),
        ),
      ],
    );
  }
}
