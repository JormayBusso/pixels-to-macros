import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// 2D interactive body map.
///
/// Shows a front-facing human silhouette with tappable body regions.
/// Each region glows based on how well the user has met the nutrient
/// DRVs that benefit that body part.  Tap a region to see details.
class BodyMapScreen extends ConsumerWidget {
  const BodyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final totals = intake.nutrientTotals;

    final regions = _buildRegions(totals, isMale);

    return Scaffold(
      appBar: AppBar(title: const Text('Body Map')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            children: [
              // Background silhouette
              Center(
                child: SizedBox(
                  width: w * 0.55,
                  height: h * 0.85,
                  child: CustomPaint(
                    painter: _SilhouettePainter(),
                    size: Size(w * 0.55, h * 0.85),
                  ),
                ),
              ),
              // Tappable regions
              ...regions.map((r) {
                final left = w * r.cx - (r.size / 2);
                final top = h * r.cy - (r.size / 2);
                final color = _scoreColor(r.score);

                return Positioned(
                  left: left,
                  top: top,
                  child: GestureDetector(
                    onTap: () => _showDetail(context, r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: r.size,
                      height: r.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.35),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: r.score > 0.7 ? 16 : 6,
                            spreadRadius: r.score > 0.7 ? 4 : 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          r.emoji,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              // Legend at bottom
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
                        _LegendDot(color: Colors.red, label: 'Low'),
                        _LegendDot(color: Colors.orange, label: 'Moderate'),
                        _LegendDot(color: Colors.green, label: 'Good'),
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
    showModalBottomSheet(
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
                Text(region.emoji, style: const TextStyle(fontSize: 28)),
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
              style: const TextStyle(fontSize: 14, color: AppTheme.gray600, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Key nutrients:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ...region.nutrients.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(n.name,
                            style: const TextStyle(fontSize: 12, color: AppTheme.gray600)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: n.ratio.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(_scoreColor(n.ratio)),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${(n.ratio * 100).round().clamp(0, 999)}%',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

Color _scoreColor(double score) {
  if (score >= 0.75) return const Color(0xFF4CAF50);
  if (score >= 0.40) return const Color(0xFFFF9800);
  return const Color(0xFFE53935);
}

// ── Region definitions ───────────────────────────────────────────────────────

class _NutrientRatio {
  final String name;
  final double ratio;
  const _NutrientRatio(this.name, this.ratio);
}

class _BodyRegion {
  final String label;
  final String emoji;
  final double cx; // normalised x (0-1)
  final double cy; // normalised y (0-1)
  final double size;
  final double score; // 0-1 average of nutrient ratios
  final String explanation;
  final List<_NutrientRatio> nutrients;

  const _BodyRegion({
    required this.label,
    required this.emoji,
    required this.cx,
    required this.cy,
    this.size = 48,
    required this.score,
    required this.explanation,
    required this.nutrients,
  });
}

List<_BodyRegion> _buildRegions(NutrientTotals t, bool isMale) {
  double r(double current, double drv) => drv > 0 ? (current / drv) : 0;

  final vitA = r(t.vitaminAUg, isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female);
  final vitC = r(t.vitaminCMg, isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female);
  final vitD = r(t.vitaminDUg, NutrientDRV.vitaminDUg);
  final vitE = r(t.vitaminEMg, NutrientDRV.vitaminEMg);
  final vitK = r(t.vitaminKUg, isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female);
  final folate = r(t.folateMcg, NutrientDRV.folateMcg);
  final b12 = r(t.b12Mcg, NutrientDRV.b12Mcg);
  final calcium = r(t.calciumMg, isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female);
  final iron = r(t.ironMg, isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female);
  final mag = r(t.magnesiumMg, isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female);
  final potassium = r(t.potassiumMg, isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female);
  final zinc = r(t.zincMg, isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female);
  final fiber = r(t.fiberG, NutrientDRV.fiberG);

  double avg(List<double> vals) => vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

  return [
    _BodyRegion(
      label: 'Brain',
      emoji: '🧠',
      cx: 0.50, cy: 0.08,
      score: avg([b12, folate, iron]).clamp(0, 1),
      explanation: 'B12 and folate support nerve function and cognitive health. Iron carries oxygen to the brain.',
      nutrients: [
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
        _NutrientRatio('Iron', iron),
      ],
    ),
    _BodyRegion(
      label: 'Eyes',
      emoji: '👁️',
      cx: 0.38, cy: 0.12,
      size: 40,
      score: avg([vitA, vitC, zinc]).clamp(0, 1),
      explanation: 'Vitamin A is essential for vision. Vitamin C and zinc protect against age-related macular degeneration.',
      nutrients: [
        _NutrientRatio('Vitamin A', vitA),
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Heart',
      emoji: '❤️',
      cx: 0.56, cy: 0.30,
      score: avg([potassium, mag, vitE]).clamp(0, 1),
      explanation: 'Potassium regulates heartbeat. Magnesium relaxes blood vessels. Vitamin E prevents oxidative damage to cells.',
      nutrients: [
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Vitamin E', vitE),
      ],
    ),
    _BodyRegion(
      label: 'Lungs',
      emoji: '🫁',
      cx: 0.44, cy: 0.30,
      size: 44,
      score: avg([vitC, vitE, vitA]).clamp(0, 1),
      explanation: 'Vitamin C protects lung tissue. Vitamin E and A are antioxidants that defend against inflammation.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin A', vitA),
      ],
    ),
    _BodyRegion(
      label: 'Liver',
      emoji: '🫘',
      cx: 0.40, cy: 0.40,
      size: 42,
      score: avg([vitE, vitK, b12]).clamp(0, 1),
      explanation: 'The liver stores vitamins and detoxifies the body. Vitamin K is synthesised here and supports blood clotting.',
      nutrients: [
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin K', vitK),
        _NutrientRatio('B12', b12),
      ],
    ),
    _BodyRegion(
      label: 'Gut',
      emoji: '🦠',
      cx: 0.50, cy: 0.50,
      score: avg([fiber, mag, potassium]).clamp(0, 1),
      explanation: 'Dietary fiber feeds healthy gut bacteria and aids digestion. Magnesium helps with muscle contractions in the intestines.',
      nutrients: [
        _NutrientRatio('Fiber', fiber),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
      ],
    ),
    _BodyRegion(
      label: 'Bones',
      emoji: '🦴',
      cx: 0.60, cy: 0.60,
      score: avg([calcium, vitD, vitK]).clamp(0, 1),
      explanation: 'Calcium builds bone density. Vitamin D helps absorb calcium. Vitamin K directs calcium to bones instead of arteries.',
      nutrients: [
        _NutrientRatio('Calcium', calcium),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Vitamin K', vitK),
      ],
    ),
    _BodyRegion(
      label: 'Muscles',
      emoji: '💪',
      cx: 0.32, cy: 0.55,
      score: avg([mag, potassium, calcium]).clamp(0, 1),
      explanation: 'Magnesium and potassium prevent cramps and support muscle contraction. Calcium triggers muscle fibers.',
      nutrients: [
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Calcium', calcium),
      ],
    ),
    _BodyRegion(
      label: 'Skin',
      emoji: '✨',
      cx: 0.68, cy: 0.42,
      size: 40,
      score: avg([vitC, vitE, zinc]).clamp(0, 1),
      explanation: 'Vitamin C produces collagen for skin elasticity. Vitamin E protects against UV damage. Zinc helps wound healing.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Blood',
      emoji: '🩸',
      cx: 0.38, cy: 0.68,
      size: 40,
      score: avg([iron, b12, folate]).clamp(0, 1),
      explanation: 'Iron is the core of haemoglobin. B12 and folate are needed to produce healthy red blood cells.',
      nutrients: [
        _NutrientRatio('Iron', iron),
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
      ],
    ),
    _BodyRegion(
      label: 'Immune System',
      emoji: '🛡️',
      cx: 0.62, cy: 0.20,
      size: 40,
      score: avg([vitC, vitD, zinc]).clamp(0, 1),
      explanation: 'Vitamin C, D, and zinc are the big three for immune defence. They help white blood cells fight infections.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
  ];
}

// ── Silhouette painter ───────────────────────────────────────────────────────

class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // Simple human silhouette using basic shapes
    // Head
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.08), width: w * 0.18, height: h * 0.09),
      paint,
    );
    // Neck
    canvas.drawRect(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.14), width: w * 0.08, height: h * 0.04),
      paint,
    );
    // Torso
    final torsoPath = Path()
      ..moveTo(w * 0.32, h * 0.16)
      ..lineTo(w * 0.68, h * 0.16)
      ..lineTo(w * 0.65, h * 0.52)
      ..lineTo(w * 0.35, h * 0.52)
      ..close();
    canvas.drawPath(torsoPath, paint);
    // Left arm
    final leftArm = Path()
      ..moveTo(w * 0.32, h * 0.17)
      ..lineTo(w * 0.18, h * 0.35)
      ..lineTo(w * 0.15, h * 0.50)
      ..lineTo(w * 0.21, h * 0.51)
      ..lineTo(w * 0.24, h * 0.36)
      ..lineTo(w * 0.34, h * 0.22)
      ..close();
    canvas.drawPath(leftArm, paint);
    // Right arm
    final rightArm = Path()
      ..moveTo(w * 0.68, h * 0.17)
      ..lineTo(w * 0.82, h * 0.35)
      ..lineTo(w * 0.85, h * 0.50)
      ..lineTo(w * 0.79, h * 0.51)
      ..lineTo(w * 0.76, h * 0.36)
      ..lineTo(w * 0.66, h * 0.22)
      ..close();
    canvas.drawPath(rightArm, paint);
    // Left leg
    final leftLeg = Path()
      ..moveTo(w * 0.35, h * 0.52)
      ..lineTo(w * 0.30, h * 0.80)
      ..lineTo(w * 0.28, h * 0.92)
      ..lineTo(w * 0.38, h * 0.92)
      ..lineTo(w * 0.40, h * 0.80)
      ..lineTo(w * 0.48, h * 0.52)
      ..close();
    canvas.drawPath(leftLeg, paint);
    // Right leg
    final rightLeg = Path()
      ..moveTo(w * 0.52, h * 0.52)
      ..lineTo(w * 0.60, h * 0.80)
      ..lineTo(w * 0.62, h * 0.92)
      ..lineTo(w * 0.72, h * 0.92)
      ..lineTo(w * 0.70, h * 0.80)
      ..lineTo(w * 0.65, h * 0.52)
      ..close();
    canvas.drawPath(rightLeg, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Legend dot ────────────────────────────────────────────────────────────────

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
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.gray600)),
      ],
    );
  }
}
