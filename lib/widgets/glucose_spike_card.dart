import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/glucose_spike_model.dart';
import '../theme/app_theme.dart';

/// A card that shows the predicted blood glucose curve for a meal.
///
/// Displays:
/// - Spike curve (area chart)
/// - Peak time marker
/// - Severity badge
/// - Medical disclaimer
class GlucoseSpikeCard extends StatelessWidget {
  const GlucoseSpikeCard({
    super.key,
    required this.mealItems,
  });

  final List<MealItemInput> mealItems;

  @override
  Widget build(BuildContext context) {
    final curve = GlucoseSpikeModel.predict(mealItems);
    final summary = GlucoseSpikeModel.summarize(curve);

    if (summary.peakDeltaMgDl < 2) {
      return const SizedBox.shrink(); // No meaningful spike.
    }

    final severityColor = switch (summary.severity) {
      SpikeSeverity.low => Colors.green,
      SpikeSeverity.moderate => Colors.orange,
      SpikeSeverity.high => Colors.red,
    };
    final severityLabel = switch (summary.severity) {
      SpikeSeverity.low => 'Low spike',
      SpikeSeverity.moderate => 'Moderate spike',
      SpikeSeverity.high => 'High spike',
    };
    final severityEmoji = switch (summary.severity) {
      SpikeSeverity.low => '🧊',
      SpikeSeverity.moderate => '🌤',
      SpikeSeverity.high => '🌶️',
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(severityEmoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Predicted Glucose Spike',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severityLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: severityColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Spike chart
            AspectRatio(
              aspectRatio: 2.2,
              child: CustomPaint(
                painter: _SpikeChartPainter(
                  curve: curve,
                  peakMin: summary.peakAtMinute,
                  severityColor: severityColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Summary stats
            Row(
              children: [
                _SpikeStat(
                  icon: Icons.arrow_upward,
                  label: 'Peak',
                  value: '+${summary.peakDeltaMgDl.round()} mg/dL',
                  color: severityColor,
                ),
                const SizedBox(width: 16),
                _SpikeStat(
                  icon: Icons.timer_outlined,
                  label: 'Peak at',
                  value: summary.peakTimeLabel,
                  color: AppTheme.gray600,
                ),
                const SizedBox(width: 16),
                _SpikeStat(
                  icon: Icons.trending_down,
                  label: 'Duration',
                  value: summary.durationLabel,
                  color: AppTheme.gray600,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.gray100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: AppTheme.gray400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This is an educational estimate, not medical advice. '
                      'Individual glucose responses vary widely. '
                      'Always consult your healthcare provider.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.gray500,
                        height: 1.4,
                      ),
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

class _SpikeStat extends StatelessWidget {
  const _SpikeStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(fontSize: 10, color: AppTheme.gray400)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SpikeChartPainter extends CustomPainter {
  _SpikeChartPainter({
    required this.curve,
    required this.peakMin,
    required this.severityColor,
  });

  final List<double> curve;
  final int peakMin;
  final Color severityColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (curve.isEmpty) return;

    const padL = 30.0, padR = 8.0, padT = 8.0, padB = 20.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final maxVal = curve.fold<double>(0, math.max).clamp(10.0, 200.0);

    Offset point(int t) {
      final x = padL + w * t / 180;
      final y = padT + h * (1 - curve[t] / maxVal);
      return Offset(x, y);
    }

    // Grid lines
    final gridPaint = Paint()
      ..color = AppTheme.gray100
      ..strokeWidth = 0.5;
    for (int mg = 0; mg <= maxVal.round(); mg += 20) {
      final y = padT + h * (1 - mg / maxVal);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
      // Y-axis label
      final tp = TextPainter(
        text: TextSpan(
          text: '+$mg',
          style: const TextStyle(fontSize: 8, color: AppTheme.gray400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padL - tp.width - 4, y - tp.height / 2));
    }

    // X-axis labels
    for (int t in const [0, 30, 60, 90, 120, 150, 180]) {
      final x = padL + w * t / 180;
      final tp = TextPainter(
        text: TextSpan(
          text: '${t}m',
          style: const TextStyle(fontSize: 8, color: AppTheme.gray400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, padT + h + 4));
    }

    // Build path
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (int t = 1; t <= 180; t++) {
      path.lineTo(point(t).dx, point(t).dy);
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(point(180).dx, padT + h)
      ..lineTo(point(0).dx, padT + h)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          severityColor.withValues(alpha: 0.35),
          severityColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(padL, padT, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    canvas.drawPath(
      path,
      Paint()
        ..color = severityColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Peak marker
    final peakPt = point(peakMin);
    canvas.drawCircle(peakPt, 4, Paint()..color = severityColor);
    canvas.drawCircle(
      peakPt,
      7,
      Paint()..color = severityColor.withValues(alpha: 0.20),
    );
  }

  @override
  bool shouldRepaint(_SpikeChartPainter old) =>
      old.curve != curve || old.peakMin != peakMin;
}
