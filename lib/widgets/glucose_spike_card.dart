import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/glucose_spike_model.dart';
import '../theme/app_theme.dart';
import 'premium_theme_effects.dart';

/// A card that shows the predicted blood glucose curve for a meal.
///
/// Displays:
/// - Spike curve (area chart)
/// - Peak time marker
/// - Severity badge
/// - Insulin pre-bolus timing guidance
/// - A dismissable "covers the meal only" insulin warning
/// - Medical disclaimer
class GlucoseSpikeCard extends StatefulWidget {
  const GlucoseSpikeCard({
    super.key,
    required this.mealItems,
  });

  final List<MealItemInput> mealItems;

  @override
  State<GlucoseSpikeCard> createState() => _GlucoseSpikeCardState();
}

class _GlucoseSpikeCardState extends State<GlucoseSpikeCard> {
  // Persisted so a dismissal survives restarts. The warning re-appears once
  // the stored timestamp passes (~1 month later).
  static const _dismissKey = 'glucose_meal_warning_dismissed_until';
  bool _warningHidden = false;

  @override
  void initState() {
    super.initState();
    _loadDismiss();
  }

  Future<void> _loadDismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_dismissKey) ?? 0;
      if (mounted && DateTime.now().millisecondsSinceEpoch < until) {
        setState(() => _warningHidden = true);
      }
    } catch (_) {}
  }

  Future<void> _dismissForMonth() async {
    setState(() => _warningHidden = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = DateTime.now().add(const Duration(days: 30));
      await prefs.setInt(_dismissKey, until.millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final mealItems = widget.mealItems;
    final curve = GlucoseSpikeModel.predict(mealItems);
    final summary = GlucoseSpikeModel.summarize(curve);

    // Only suppress the card for a meal with no carbohydrate at all (a pure
    // protein/fat meal produces no glucose rise). For ANY carb-containing meal
    // we always render the prediction, so the diabetes insight never silently
    // disappears for the low-carb meals diabetes users typically eat.
    final totalNetCarbs =
        mealItems.fold<double>(0, (sum, m) => sum + m.netCarbsG);
    if (totalNetCarbs <= 0 || summary.peakDeltaMgDl < 0.5) {
      return const SizedBox.shrink();
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

    return PremiumSurface(
      // Tier 3 AI-active treatment: this is an on-demand medical insight that
      // only renders when the user is in diabetes mode and a meal is present.
      animate: true,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(14),
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
                    color: context.appTextColor,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                color: context.appMutedTextColor,
              ),
              const SizedBox(width: 16),
              _SpikeStat(
                icon: Icons.trending_down,
                label: 'Duration',
                value: summary.durationLabel,
                color: context.appMutedTextColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Insulin pre-bolus timing guidance ───────────────────────
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.primary500.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: context.primary500.withValues(alpha: 0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 15, color: context.primary600),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'When to take insulin',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: context.appTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Glucose is expected to peak about '
                        '${summary.peakAtMinute} min after eating. '
                        'Rapid-acting insulin (e.g. aspart/lispro) usually '
                        'starts working in ~15 min and peaks around 1–2 h, so '
                        'many people inject ~15 min before a carb-rich meal so '
                        'it lines up with the rise. Always use the timing your '
                        'clinician set for you.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: context.appMutedTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!_warningHidden) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              decoration: BoxDecoration(
                color: AppTheme.amber100
                    .withValues(alpha: context.isPremiumTheme ? 0.16 : 1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.amber500.withValues(alpha: 0.42)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Any insulin amount here covers only the carbs in '
                          'this meal. It does NOT account for your current '
                          'blood sugar — measure your glucose and adjust your '
                          'dose accordingly. Never dose from this estimate '
                          'alone.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: context.appTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _dismissForMonth,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        foregroundColor: Colors.amber.shade900,
                      ),
                      child: const Text(
                        "Don't show for a month",
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Disclaimer
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.appSubtleFillColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: context.appMutedTextColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This is an educational estimate, not medical advice. '
                    'Individual glucose responses vary widely. '
                    'Always consult your healthcare provider.',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.appMutedTextColor,
                      height: 1.4,
                    ),
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
