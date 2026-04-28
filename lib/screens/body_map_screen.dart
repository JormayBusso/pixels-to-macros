import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// 2D interactive body map — anatomy style.
///
/// Shows a greyed-out human silhouette with body regions colored directly
/// on the figure (no emojis).  Text labels with lines point to each area.
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

          // The body image is centered at 60% width, 82% height
          final imgW = w * 0.60;
          final imgH = h * 0.82;
          final imgLeft = (w - imgW) / 2;
          final imgTop = (h - imgH) / 2;

          return Stack(
            children: [
              // ── Background anatomy image (greyscale) ──────────────
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: imgW,
                    height: imgH,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0,      0,      0,      1, 0,
                      ]),
                      child: Image.asset(
                        'assets/anatomy_body.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Colored region spots on the body ──────────────────
              ...regions.map((r) {
                // cx/cy are relative to the full screen, but the body image is
                // centered — convert region coords to body-image coords then
                // back to screen coords.
                final sx = imgLeft + r.cx * imgW;
                final sy = imgTop + r.cy * imgH;
                final color = _scoreColor(r.score);
                final spotSize = r.size * 0.55; // smaller than emoji circles

                return Positioned(
                  left: sx - spotSize / 2,
                  top: sy - spotSize / 2,
                  child: GestureDetector(
                    onTap: () => _showDetail(context, r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: spotSize,
                      height: spotSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.72),
                        border: Border.all(color: color, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.50),
                            blurRadius: r.score > 0.7 ? 16 : 6,
                            spreadRadius: r.score > 0.7 ? 4 : 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              // ── Text labels with lines ────────────────────────────
              ...regions.map((r) {
                final sx = imgLeft + r.cx * imgW;
                final sy = imgTop + r.cy * imgH;
                final color = _scoreColor(r.score);
                // Labels on the left side if cx < 0.5, else right
                final isLeft = r.cx < 0.50;
                final labelX = isLeft ? 4.0 : w - 4.0;
                final labelW = imgLeft - 12;

                return Positioned(
                  left: isLeft ? 4 : (sx + 8),
                  top: sy - 10,
                  width: isLeft ? (sx - 16) : (w - sx - 16),
                  child: GestureDetector(
                    onTap: () => _showDetail(context, r),
                    child: CustomPaint(
                      painter: _LineLabelPainter(
                        color: color,
                        isLeft: isLeft,
                        label: r.label,
                      ),
                      size: Size(isLeft ? (sx - 16) : (w - sx - 16), 20),
                    ),
                  ),
                );
              }),

              // ── Legend ───────────────────────────────────────────
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
                        _LegendDot(color: Colors.red.shade700, label: 'Low / Over'),
                        _LegendDot(color: Colors.orange, label: 'Moderate'),
                        _LegendDot(color: Colors.yellow.shade700, label: 'Good'),
                        _LegendDot(color: Colors.green, label: 'Great'),
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
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _scoreColor(region.score).withValues(alpha: 0.2),
                    border: Border.all(color: _scoreColor(region.score), width: 2),
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

/// Draws a short horizontal line + label text.
/// [isLeft] — line goes right-to-left (label on left, line to right toward body).
class _LineLabelPainter extends CustomPainter {
  final Color color;
  final bool isLeft;
  final String label;

  _LineLabelPainter({
    required this.color,
    required this.isLeft,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final lineY = size.height / 2;
    if (isLeft) {
      // Line from right edge (body) toward the label text on the left
      canvas.drawLine(Offset(size.width, lineY), Offset(size.width - 20, lineY), paint);
    } else {
      // Line from left edge (body) toward label on the right
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
  // Transitions: red (low) → orange → yellow → green (good)
  // then back to red if way over the daily dose (>1.6)
  if (score > 1.6) return const Color(0xFFB71C1C); // way over → deep red
  if (score >= 1.0) return const Color(0xFF4CAF50); // ≥100%  → green
  if (score >= 0.7) return const Color(0xFF9CCC65); // 70-99% → light green
  if (score >= 0.4) return const Color(0xFFFF9800); // 40-69% → orange
  return const Color(0xFFE53935);                   // <40%   → red
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
      score: avg([b12, folate, iron]).clamp(0.0, 2.0),
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
      score: avg([vitA, vitC, zinc]).clamp(0.0, 2.0),
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
      score: avg([potassium, mag, vitE]).clamp(0.0, 2.0),
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
      score: avg([vitC, vitE, vitA]).clamp(0.0, 2.0),
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
      score: avg([vitE, vitK, b12]).clamp(0.0, 2.0),
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
      score: avg([fiber, mag, potassium]).clamp(0.0, 2.0),
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
      score: avg([calcium, vitD, vitK]).clamp(0.0, 2.0),
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
      score: avg([mag, potassium, calcium]).clamp(0.0, 2.0),
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
      score: avg([vitC, vitE, zinc]).clamp(0.0, 2.0),
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
      score: avg([iron, b12, folate]).clamp(0.0, 2.0),
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
      score: avg([vitC, vitD, zinc]).clamp(0.0, 2.0),
      explanation: 'Vitamin C, D, and zinc are the big three for immune defence. They help white blood cells fight infections.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
  ];
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
