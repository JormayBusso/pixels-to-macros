import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dual_photo_capture_overlay.dart';

/// "AI is looking" sheen inside the capture guide.
///
/// While no food has been detected yet, a soft light band glides across the
/// region of interest (clipped to the guide, so it never implies analysis
/// outside it). It fades out as soon as the live detector finds food — the
/// native glow on the food itself then takes over. Default themes get a
/// faint neutral sheen; premium themes get a gradient band with a dot-matrix
/// reveal. Static (no sheen) when the user prefers reduced motion.
class AiScanSweepOverlay extends StatefulWidget {
  const AiScanSweepOverlay({
    super.key,
    required this.guide,
    required this.palette,
    this.active = true,
    this.searching = true,
    this.intensity = 1.0,
  });

  /// The capture guide (region of interest) in local coordinates.
  final RRect guide;

  final ScanChromePalette palette;

  /// When false nothing is painted.
  final bool active;

  /// True while no food has been detected yet; false fades the sheen out.
  final bool searching;

  /// 0…1 overall strength multiplier.
  final double intensity;

  @override
  State<AiScanSweepOverlay> createState() => _AiScanSweepOverlayState();
}

class _AiScanSweepOverlayState extends State<AiScanSweepOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this);
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
    final mq = MediaQuery.of(context);
    _reduceMotion = mq.disableAnimations || mq.accessibleNavigation;
    final period = Duration(
      milliseconds: widget.palette.premium ? 2600 : 3400,
    );
    if (_sweep.duration != period) {
      _sweep.duration = period;
      if (_sweep.isAnimating) _sweep.repeat();
    }
    final shouldAnimate = widget.active &&
        widget.searching &&
        !_reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (shouldAnimate && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!shouldAnimate && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _reduceMotion) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.searching ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _SheenPainter(
              animation: _sweep,
              guide: widget.guide,
              palette: widget.palette,
              intensity: widget.intensity.clamp(0.0, 1.0),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter({
    required this.animation,
    required this.guide,
    required this.palette,
    required this.intensity,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final RRect guide;
  final ScanChromePalette palette;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final g = guide;
    // One pass across the guide, then a short rest before the next pass.
    final raw = animation.value;
    const passPortion = 0.78;
    if (raw > passPortion) return;
    final t = Curves.easeInOutSine.transform(raw / passPortion);

    final band = g.width * 0.34;
    final x = g.left - band + (g.width + 2 * band) * t;
    final tilt = band * 0.35;

    canvas.save();
    canvas.clipRRect(g);

    final colors = palette.premium
        ? [
            Colors.transparent,
            palette.gradient.first.withValues(alpha: 0.16 * intensity),
            palette.gradient.last.withValues(alpha: 0.12 * intensity),
            Colors.transparent,
          ]
        : [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.075 * intensity),
            Colors.white.withValues(alpha: 0.05 * intensity),
            Colors.transparent,
          ];
    canvas.drawRect(
      g.outerRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - band / 2, g.top),
          Offset(x + band / 2, g.top + tilt),
          colors,
          const [0.0, 0.5, 0.62, 1.0],
        ),
    );

    // Premium: a fine dot matrix revealed under the band, like an analysis
    // grid locking onto the scene.
    if (palette.premium) {
      const step = 18.0;
      final points = <Offset>[];
      final x0 = (g.left / step).ceil() * step;
      final y0 = (g.top / step).ceil() * step;
      for (var px = x0; px < g.right; px += step) {
        final d = (px - x).abs();
        if (d > band * 0.5) continue;
        for (var py = y0; py < g.bottom; py += step) {
          points.add(Offset(px, py));
        }
      }
      if (points.isNotEmpty) {
        canvas.drawPoints(
          ui.PointMode.points,
          points,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.32 * intensity)
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round,
        );
      }
      // Crisp leading edge.
      final lead = x + band * 0.18;
      canvas.drawLine(
        Offset(lead, g.top),
        Offset(lead, g.bottom),
        Paint()
          ..strokeWidth = 1
          ..color = palette.gradient.first
              .withValues(alpha: 0.22 * intensity * (1 - (t - 0.5).abs())),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) =>
      old.guide != guide ||
      old.palette != palette ||
      old.intensity != intensity ||
      old.animation != animation;
}
