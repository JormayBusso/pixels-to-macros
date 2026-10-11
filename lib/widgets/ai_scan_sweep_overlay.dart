import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dual_photo_capture_overlay.dart';

/// Translucent fill and sweep inside current food support, never the guide.
/// The native preview owns the production mask; absent support paints nothing.
class AiScanSweepOverlay extends StatefulWidget {
  const AiScanSweepOverlay({
    super.key,
    required this.guide,
    required this.palette,
    this.active = true,
    this.searching = true,
    this.intensity = 1.0,
    this.foodMask,
  });

  /// The capture guide (region of interest) in local coordinates.
  final RRect guide;

  final ScanChromePalette palette;

  /// When false nothing is painted.
  final bool active;

  /// Legacy caller hint; never permits painting without [foodMask].
  final bool searching;

  /// Local-coordinate exact support, including holes and all components.
  final ui.Path? foodMask;

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
        widget.foodMask != null &&
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
    final mask = widget.foodMask;
    if (!widget.active || mask == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SheenPainter(
            animation: _sweep,
            guide: widget.guide,
            foodMask: mask,
            reduceMotion: _reduceMotion,
            palette: widget.palette,
            intensity: widget.intensity.clamp(0.0, 1.0),
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
    required this.foodMask,
    required this.reduceMotion,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final RRect guide;
  final ScanChromePalette palette;
  final double intensity;
  final ui.Path foodMask;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final g = foodMask.getBounds();
    if (g.isEmpty) return;
    canvas.save();
    canvas.clipPath(foodMask, doAntiAlias: false);
    canvas.drawRect(
      g,
      Paint()
        ..color = palette.gradient.first.withValues(alpha: 0.20 * intensity),
    );
    if (reduceMotion) {
      canvas.restore();
      return;
    }
    // One pass across the food, then a short rest before the next pass.
    final raw = animation.value;
    const passPortion = 0.78;
    if (raw > passPortion) {
      canvas.restore();
      return;
    }
    final t = Curves.easeInOutSine.transform(raw / passPortion);

    final band = g.width * 0.34;
    final x = g.left - band + (g.width + 2 * band) * t;
    final tilt = band * 0.35;

    final colors = [
      Colors.transparent,
      palette.gradient.first.withValues(alpha: 0.16 * intensity),
      palette.gradient.last.withValues(alpha: 0.12 * intensity),
      Colors.transparent,
    ];
    canvas.drawRect(
      g,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - band / 2, g.top),
          Offset(x + band / 2, g.top + tilt),
          colors,
          const [0.0, 0.5, 0.62, 1.0],
        ),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) =>
      old.guide != guide ||
      old.foodMask != foodMask ||
      old.reduceMotion != reduceMotion ||
      old.palette != palette ||
      old.intensity != intensity ||
      old.animation != animation;
}
