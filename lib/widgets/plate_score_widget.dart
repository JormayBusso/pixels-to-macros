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
                max: 30),
            _BreakdownRow(
                label: 'Protein',
                points: widget.breakdown.proteinPoints,
                max: 25),
            _BreakdownRow(
                label: 'Fiber',
                points: widget.breakdown.fiberPoints,
                max: 15),
            _BreakdownRow(
                label: 'Variety',
                points: widget.breakdown.varietyPoints,
                max: 15),
            _BreakdownRow(
                label: 'Low sugar',
                points: widget.breakdown.sugarPoints,
                max: 15),
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
  });

  final int caloriePoints; // out of 30
  final int proteinPoints; // out of 25
  final int fiberPoints; // out of 15
  final int varietyPoints; // out of 15
  final int sugarPoints; // out of 15

  int get total =>
      caloriePoints + proteinPoints + fiberPoints + varietyPoints + sugarPoints;
}

/// Calculate plate score for a meal.
///
/// [mealCalories] — total kcal in this meal
/// [dailyGoal] — user's daily kcal goal (divide by 3 for per-meal target)
/// [proteinG] — grams of protein in this meal
/// [fiberG] — grams of fiber in this meal
/// [foodCount] — number of distinct food items detected
/// [totalGL] — total glycemic load of the meal
PlateScoreBreakdown calculatePlateScore({
  required double mealCalories,
  required int dailyGoal,
  required double proteinG,
  required double fiberG,
  required int foodCount,
  required double totalGL,
}) {
  // Calorie balance (30 pts): how close to 1/3 of daily goal
  final mealTarget = dailyGoal / 3.0;
  final calRatio = mealTarget > 0 ? mealCalories / mealTarget : 0.0;
  final calDeviation = (calRatio - 1.0).abs(); // 0 = perfect
  final caloriePoints = (30 * (1 - calDeviation).clamp(0.0, 1.0)).round();

  // Protein (25 pts): aim for ~25g+ per meal
  final proteinPoints = (25 * (proteinG / 25.0).clamp(0.0, 1.0)).round();

  // Fiber (15 pts): aim for ~8g+ per meal
  final fiberPoints = (15 * (fiberG / 8.0).clamp(0.0, 1.0)).round();

  // Variety (15 pts): more distinct foods = better
  final varietyPoints = (15 * (foodCount / 4.0).clamp(0.0, 1.0)).round();

  // Sugar/GL (15 pts): lower GL = better
  final glScore = totalGL <= 10
      ? 1.0
      : totalGL <= 20
          ? 0.6
          : totalGL <= 30
              ? 0.3
              : 0.0;
  final sugarPoints = (15 * glScore).round();

  return PlateScoreBreakdown(
    caloriePoints: caloriePoints,
    proteinPoints: proteinPoints,
    fiberPoints: fiberPoints,
    varietyPoints: varietyPoints,
    sugarPoints: sugarPoints,
  );
}
