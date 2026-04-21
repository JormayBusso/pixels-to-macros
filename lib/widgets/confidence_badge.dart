import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Displays an aggregate confidence score for a scan result.
///
/// The score is derived from the relative uncertainty of each food item.
/// Lower uncertainty → higher confidence → greener colour.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.caloriesMin,
    required this.caloriesMax,
  });

  final double caloriesMin;
  final double caloriesMax;

  /// Returns a 0–100 confidence score.
  ///
  /// 100 = min and max are identical (perfect certainty).
  ///   0 = range covers ≥100% of the average.
  int get score {
    final avg = (caloriesMin + caloriesMax) / 2;
    if (avg <= 0) return 0;
    final spread = (caloriesMax - caloriesMin) / avg; // 0 = certain, 1 = ±50%
    return (100 * (1 - spread).clamp(0.0, 1.0)).round();
  }

  Color get _color {
    if (score >= 80) return AppTheme.green600;
    if (score >= 60) return AppTheme.green400;
    if (score >= 40) return AppTheme.amber500;
    return AppTheme.red500;
  }

  String get _label {
    if (score >= 80) return 'High';
    if (score >= 60) return 'Good';
    if (score >= 40) return 'Fair';
    return 'Low';
  }

  IconData get _icon {
    if (score >= 80) return Icons.verified;
    if (score >= 60) return Icons.check_circle_outline;
    if (score >= 40) return Icons.info_outline;
    return Icons.warning_amber_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 6),
          Text(
            '$_label confidence ($score%)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Larger card variant showing a confidence ring for the scan detail screen.
class ConfidenceRingCard extends StatelessWidget {
  const ConfidenceRingCard({
    super.key,
    required this.caloriesMin,
    required this.caloriesMax,
  });

  final double caloriesMin;
  final double caloriesMax;

  @override
  Widget build(BuildContext context) {
    final badge = ConfidenceBadge(
      caloriesMin: caloriesMin,
      caloriesMax: caloriesMax,
    );
    final score = badge.score;
    final color = badge._color;
    final label = badge._label;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Mini ring
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 5,
                    backgroundColor: AppTheme.gray100,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label Confidence',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Based on calorie range uncertainty',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
