import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A themed, bounded "AI is analysing" indicator over the live camera.
///
/// The effect is deliberately limited to the same central circular framing
/// area as the capture guide. It uses a pulsing halo, orbiting arc segments,
/// and an inner analysis ring rather than implying detection across unrelated
/// areas of the camera preview. Colours follow the active premium theme's
/// [AppVisualTheme.gradient]; non-premium themes get a neutral cyan treatment.
class AiScanSweepOverlay extends StatefulWidget {
  const AiScanSweepOverlay({
    super.key,
    this.active = true,
    this.intensity = 1.0,
  });

  /// When false the overlay eases out.
  final bool active;

  /// 0…1 overall strength multiplier (e.g. stronger during reconstruction).
  final double intensity;

  @override
  State<AiScanSweepOverlay> createState() => _AiScanSweepOverlayState();
}

class _AiScanSweepOverlayState extends State<AiScanSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _analysis;

  @override
  void initState() {
    super.initState();
    _analysis = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AiScanSweepOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate = widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !reduceMotion;
    if (shouldAnimate && !_analysis.isAnimating) {
      _analysis.repeat();
    } else if (!shouldAnimate && _analysis.isAnimating) {
      _analysis.stop();
    }
    if (!shouldAnimate) {
      _analysis.value = 0;
    }
  }

  @override
  void dispose() {
    _analysis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    // Premium themes drive their own gradient; non-premium gets a neutral,
    // still-high-tech cyan so the scan always looks like an AI is at work.
    final colors = visual.premium && visual.gradient.length >= 2
        ? visual.gradient
        : const [Color(0xFF35E1D6), Color(0xFF3D8BFF), Color(0xFF9B5CFF)];

    if (!widget.active) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AnalysisPainter(
            animation: _analysis,
            colors: colors,
            intensity: widget.intensity.clamp(0.0, 1.0),
          ),
        ),
      ),
    );
  }
}

class _AnalysisPainter extends CustomPainter {
  _AnalysisPainter({
    required this.animation,
    required this.colors,
    required this.intensity,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<Color> colors;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value;
    final primary = colors.first;
    final accent = colors.length >= 3 ? colors[2] : colors.last;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide * 0.28).clamp(104.0, 120.0).toDouble();
    final pulse = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
    final analysisRect = Rect.fromCircle(center: center, radius: radius);

    // Keep the ambient light strictly within the capture guide: this signals
    // focused analysis without pretending that a live food mask is available.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.11 * intensity),
            accent.withValues(alpha: 0.035 * intensity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.68, 1.0],
        ).createShader(analysisRect),
    );

    final haloRadius = radius * (0.92 + 0.05 * pulse);
    final haloPaint = Paint()
      ..color = primary.withValues(alpha: (0.18 + 0.12 * pulse) * intensity)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, haloRadius, haloPaint);

    final arcPaint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      arcPaint.color = (i.isEven ? primary : accent).withValues(
        alpha: (0.5 + 0.25 * pulse) * intensity,
      );
      canvas.drawArc(
        analysisRect.deflate(5),
        phase * 2 * math.pi + i * 2.1,
        0.56,
        false,
        arcPaint,
      );
    }

    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: (0.2 + 0.14 * pulse) * intensity)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    const segments = 16;
    const segmentAngle = (2 * math.pi) / segments;
    final innerRect = Rect.fromCircle(center: center, radius: radius * 0.59);
    for (int i = 0; i < segments; i++) {
      final intensityShift = (math.sin(phase * 2 * math.pi + i * 0.8) + 1) / 2;
      innerPaint.color = primary.withValues(
        alpha: (0.15 + 0.25 * intensityShift) * intensity,
      );
      canvas.drawArc(
        innerRect,
        i * segmentAngle,
        segmentAngle * 0.54,
        false,
        innerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnalysisPainter old) =>
      old.intensity != intensity ||
      old.colors != colors;
}
