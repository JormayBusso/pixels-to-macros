import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An animated circular "plate score" from 0 to 100 that reveals after a scan.
///
/// Scoring logic:
/// - Calorie proximity to goal (0–30 pts)
/// - Protein adequacy (0–25 pts)
/// - Fiber presence (0–15 pts)
/// - Variety / number of foods (0–15 pts)
/// - Low sugar / low GL (0–15 pts)
///
/// Usage: show as a bottom-sheet or inline after a scan completes.
class PlateScoreReveal extends StatefulWidget {
  const PlateScoreReveal({
    super.key,
    required this.score,
    required this.breakdown,
  });

  final int score; // 0–100
  final PlateScoreBreakdown breakdown;

  @override
  State<PlateScoreReveal> createState() => _PlateScoreRevealState();
}

class _PlateScoreRevealState extends State<PlateScoreReveal>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scoreAnim;
  late Animation<double> _ringAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _scoreAnim = Tween<double>(begin: 0, end: widget.score.toDouble())
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ringAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(widget.score);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final displayScore = _scoreAnim.value.round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              height: 160,
              child: CustomPaint(
                painter: _ScoreRingPainter(
                  progress: _ringAnim.value * widget.score / 100,
                  color: color,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$displayScore',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                      Text(
                        'Plate Score',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _verdict(widget.score),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 16),
            // Breakdown bars
            _BreakdownRow(
                label: 'Calorie balance',
                points: widget.breakdown.caloriePoints,
                max: 25),
            _BreakdownRow(
                label: 'Protein',
                points: widget.breakdown.proteinPoints,
                max: 20),
            _BreakdownRow(
                label: 'Fiber',
                points: widget.breakdown.fiberPoints,
                max: 12),
            _BreakdownRow(
                label: 'Variety',
                points: widget.breakdown.varietyPoints,
                max: 10),
            _BreakdownRow(
                label: 'Glycemic quality',
                points: widget.breakdown.sugarPoints,
                max: 13),
            _BreakdownRow(
                label: 'Fat quality',
                points: widget.breakdown.fatBalancePoints,
                max: 10),
            _BreakdownRow(
                label: 'Micronutrients',
                points: widget.breakdown.micronutrientPoints,
                max: 10),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  static Color _scoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.lime.shade700;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  static String _verdict(int score) {
    if (score >= 90) return 'Outstanding! 🏆';
    if (score >= 80) return 'Great plate! 🎉';
    if (score >= 60) return 'Good effort 👍';
    if (score >= 40) return 'Room to improve';
    return 'Let\'s do better next time';
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter({required this.progress, required this.color});
  final double progress; // 0.0 – 1.0
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppTheme.gray100
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );

    // Progress arc
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScoreRingPainter old) =>
      old.progress != progress || old.color != color;
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.points,
    required this.max,
  });
  final String label;
  final int points;
  final int max;

  @override
  Widget build(BuildContext context) {
    final pct = max > 0 ? (points / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppTheme.gray600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppTheme.gray100,
                color: pct >= 0.8
                    ? Colors.green
                    : pct >= 0.5
                        ? Colors.orange
                        : Colors.red.shade300,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$points/$max',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.gray500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Scoring Logic ───────────────────────

class PlateScoreBreakdown {
  const PlateScoreBreakdown({
    required this.caloriePoints,
    required this.proteinPoints,
    required this.fiberPoints,
    required this.varietyPoints,
    required this.sugarPoints,
    required this.fatBalancePoints,
    required this.micronutrientPoints,
  });

  final int caloriePoints;      // out of 25
  final int proteinPoints;      // out of 20
  final int fiberPoints;        // out of 12
  final int varietyPoints;      // out of 10
  final int sugarPoints;        // out of 13
  final int fatBalancePoints;   // out of 10
  final int micronutrientPoints; // out of 10

  int get total =>
      caloriePoints + proteinPoints + fiberPoints + varietyPoints +
      sugarPoints + fatBalancePoints + micronutrientPoints;
}

/// Calculate plate score for a meal — professionally evaluated on a 0–100 scale.
///
/// Scoring breakdown (7 dimensions, 100 total):
///  • Calorie balance       (0–25): proximity to per-meal target (daily goal ÷ 3)
///  • Protein adequacy      (0–20): optimal 25–40g per meal with diminishing returns
///  • Dietary fiber          (0–12): aim for 8g+ per meal (WHO recommends 25–30g/day)
///  • Food variety           (0–10): 3+ distinct food groups/items
///  • Glycemic quality       (0–13): penalises high glycemic load meals
///  • Fat quality            (0–10): rewards balanced fat, penalises excess saturated fat
///  • Micronutrient density  (0–10): bonus for vitamin/mineral-rich meals
///
/// [mealCalories] — total kcal in this meal
/// [dailyGoal] — user's daily kcal goal
/// [proteinG] — grams of protein in this meal
/// [fiberG] — grams of fiber in this meal
/// [foodCount] — number of distinct food items detected
/// [totalGL] — total glycemic load of the meal
/// [fatG] — total fat grams (optional, for fat quality scoring)
/// [saturatedFatG] — saturated fat grams (optional)
/// [carbsG] — total carbohydrates (optional, for macro balance)
/// [sodiumMg] — sodium in mg (optional, for excess sodium penalty)
PlateScoreBreakdown calculatePlateScore({
  required double mealCalories,
  required int dailyGoal,
  required double proteinG,
  required double fiberG,
  required int foodCount,
  required double totalGL,
  double fatG = 0,
  double saturatedFatG = 0,
  double carbsG = 0,
  double sodiumMg = 0,
}) {
  // ── Calorie balance (25 pts) ────────────────────────────────────────
  // Perfect: exactly 1/3 of daily goal. Penalise both under- and over-eating.
  // Use a bell-curve-style scoring: within ±10% = full marks, degrades linearly.
  final mealTarget = dailyGoal / 3.0;
  double calScore;
  if (mealTarget <= 0) {
    calScore = 0.5;
  } else {
    final calRatio = mealCalories / mealTarget;
    final deviation = (calRatio - 1.0).abs();
    if (deviation <= 0.10) {
      calScore = 1.0; // within ±10% of target = perfect
    } else if (deviation <= 0.25) {
      calScore = 1.0 - (deviation - 0.10) / 0.15 * 0.3; // 1.0 → 0.7
    } else if (deviation <= 0.50) {
      calScore = 0.7 - (deviation - 0.25) / 0.25 * 0.4; // 0.7 → 0.3
    } else {
      calScore = (0.3 - (deviation - 0.50) * 0.4).clamp(0.0, 0.3);
    }
    // Extra penalty for extreme overconsumption (>2x target)
    if (calRatio > 2.0) calScore = 0.0;
  }
  final caloriePoints = (25 * calScore.clamp(0.0, 1.0)).round();

  // ── Protein adequacy (20 pts) ────────────────────────────────────────
  // Optimal range: 25–40g per meal for most adults.
  // Below 10g = poor. 10–25g = linear improvement. 25–40g = full marks.
  // Above 40g = slight diminishing (still good but no extra points).
  double proteinScore;
  if (proteinG >= 25) {
    proteinScore = 1.0;
  } else if (proteinG >= 15) {
    proteinScore = 0.6 + (proteinG - 15) / 10.0 * 0.4; // 0.6 → 1.0
  } else if (proteinG >= 5) {
    proteinScore = 0.2 + (proteinG - 5) / 10.0 * 0.4; // 0.2 → 0.6
  } else {
    proteinScore = proteinG / 5.0 * 0.2; // 0 → 0.2
  }
  final proteinPoints = (20 * proteinScore.clamp(0.0, 1.0)).round();

  // ── Dietary fiber (12 pts) ──────────────────────────────────────────
  // WHO recommends 25–30g/day ≈ 8–10g per meal.
  // Logarithmic curve: first few grams matter most.
  double fiberScore;
  if (fiberG >= 10) {
    fiberScore = 1.0;
  } else if (fiberG >= 5) {
    fiberScore = 0.6 + (fiberG - 5) / 5.0 * 0.4;
  } else if (fiberG >= 2) {
    fiberScore = 0.2 + (fiberG - 2) / 3.0 * 0.4;
  } else {
    fiberScore = fiberG / 2.0 * 0.2;
  }
  final fiberPoints = (12 * fiberScore.clamp(0.0, 1.0)).round();

  // ── Food variety (10 pts) ────────────────────────────────────────────
  // Diverse meals are associated with better micronutrient coverage.
  // 1 food = 25%, 2 = 50%, 3 = 75%, 4+ = 100%.
  double varietyScore;
  if (foodCount >= 4) {
    varietyScore = 1.0;
  } else if (foodCount == 3) {
    varietyScore = 0.75;
  } else if (foodCount == 2) {
    varietyScore = 0.50;
  } else if (foodCount == 1) {
    varietyScore = 0.25;
  } else {
    varietyScore = 0.0;
  }
  final varietyPoints = (10 * varietyScore).round();

  // ── Glycemic quality (13 pts) ────────────────────────────────────────
  // Low GL (<10) = excellent, moderate (10–20) = good, high (>20) = poor.
  // Uses a smooth curve rather than hard cutoffs.
  double glScore;
  if (totalGL <= 5) {
    glScore = 1.0;
  } else if (totalGL <= 10) {
    glScore = 1.0 - (totalGL - 5) / 5.0 * 0.15; // 1.0 → 0.85
  } else if (totalGL <= 15) {
    glScore = 0.85 - (totalGL - 10) / 5.0 * 0.25; // 0.85 → 0.60
  } else if (totalGL <= 25) {
    glScore = 0.60 - (totalGL - 15) / 10.0 * 0.35; // 0.60 → 0.25
  } else if (totalGL <= 40) {
    glScore = 0.25 - (totalGL - 25) / 15.0 * 0.20; // 0.25 → 0.05
  } else {
    glScore = 0.0;
  }
  final sugarPoints = (13 * glScore.clamp(0.0, 1.0)).round();

  // ── Fat quality (10 pts) ─────────────────────────────────────────────
  // Rewards meals with moderate total fat and low saturated fat ratio.
  // Penalises >15g sat fat per meal or >50% of fat from saturated sources.
  double fatScore = 0.7; // neutral default when fat data unavailable
  if (fatG > 0) {
    final satRatio = saturatedFatG / fatG;
    // Saturated fat should be <1/3 of total fat (AHA recommendation)
    if (satRatio <= 0.30) {
      fatScore = 1.0;
    } else if (satRatio <= 0.45) {
      fatScore = 1.0 - (satRatio - 0.30) / 0.15 * 0.4;
    } else {
      fatScore = 0.6 - ((satRatio - 0.45) * 2.0).clamp(0.0, 0.6);
    }
    // Absolute saturated fat penalty: >15g is concerning
    if (saturatedFatG > 15) {
      fatScore *= 0.5;
    } else if (saturatedFatG > 10) {
      fatScore *= 0.75;
    }
  }
  final fatBalancePoints = (10 * fatScore.clamp(0.0, 1.0)).round();

  // ── Micronutrient density (10 pts) ───────────────────────────────────
  // Proxy: meals with more variety, adequate protein, fiber, and moderate
  // sodium are more likely to be micronutrient-dense.
  double microScore = 0.5; // baseline
  // Bonus for high fiber (indicates whole foods)
  if (fiberG >= 5) microScore += 0.15;
  // Bonus for food variety (more foods = more micronutrients)
  if (foodCount >= 3) microScore += 0.15;
  if (foodCount >= 5) microScore += 0.10;
  // Penalty for excessive sodium (>800mg per meal)
  if (sodiumMg > 1200) {
    microScore -= 0.3;
  } else if (sodiumMg > 800) {
    microScore -= 0.15;
  }
  // Bonus for adequate protein (complete amino acids)
  if (proteinG >= 20) microScore += 0.10;
  final micronutrientPoints = (10 * microScore.clamp(0.0, 1.0)).round();

  return PlateScoreBreakdown(
    caloriePoints: caloriePoints,
    proteinPoints: proteinPoints,
    fiberPoints: fiberPoints,
    varietyPoints: varietyPoints,
    sugarPoints: sugarPoints,
    fatBalancePoints: fatBalancePoints,
    micronutrientPoints: micronutrientPoints,
  );
}
