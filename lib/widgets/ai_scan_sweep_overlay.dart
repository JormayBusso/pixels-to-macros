import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A themed "AI is scanning" sweep drawn over the live camera during the scan.
///
/// It layers three cheap, GPU-friendly effects that together read as
/// on-device intelligence analysing the food:
///   • a travelling **scan line** with a soft leading glow,
///   • a faint **reconstruction grid** that the sweep reveals, and
///   • animated **corner reticles** that lock onto the frame.
///
/// Colours follow the active premium theme's [AppVisualTheme.gradient] so each
/// premium theme gets its own distinctive look; non-premium themes get a clean
/// neutral cyan so the scan still looks high-tech. Contained in a
/// [RepaintBoundary] with a single controller, and falls back to a static
/// frame when the user has reduced motion enabled.
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
  late final AnimationController _sweep;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: widget.active ? 1.0 : 0.0,
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
    if (shouldAnimate && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!shouldAnimate && _sweep.isAnimating) {
      _sweep.stop();
    }
    if (widget.active) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _fade.dispose();
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

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_sweep, _fade]),
          builder: (context, _) {
            final opacity = Curves.easeInOut.transform(_fade.value);
            if (opacity <= 0.001) return const SizedBox.shrink();
            return CustomPaint(
              size: Size.infinite,
              painter: _SweepPainter(
                colors: colors,
                progress: _sweep.value,
                opacity: opacity,
                intensity: widget.intensity.clamp(0.0, 1.0),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.colors,
    required this.progress,
    required this.opacity,
    required this.intensity,
  });

  final List<Color> colors;
  final double progress;
  final double opacity;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final primary = colors.first;
    final accent = colors.length >= 3 ? colors[2] : colors.last;
    final a = opacity * intensity;

    // ── Reconstruction grid (revealed near the sweep line) ───────────────
    // A faint mesh that suggests the scene is being reconstructed. Vertical
    // lines fade with distance from the sweep so the grid appears to "build".
    final sweepX = progress * w;
    const gridSpacing = 46.0;
    final gridPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (double x = 0; x <= w; x += gridSpacing) {
      final d = (x - sweepX).abs() / w;
      final fade = (1.0 - d).clamp(0.0, 1.0);
      gridPaint.color = primary.withValues(alpha: 0.10 * fade * a);
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y <= h; y += gridSpacing) {
      gridPaint.color = primary.withValues(alpha: 0.05 * a);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // ── Travelling scan line with a soft leading glow ────────────────────
    final glowRect = Rect.fromLTWH(sweepX - 70, 0, 140, h);
    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.28 * a),
          primary.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, glowPaint);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85 * a)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(sweepX, 0), Offset(sweepX, h), linePaint);
    final lineCore = Paint()
      ..color = primary.withValues(alpha: 0.9 * a)
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawLine(Offset(sweepX, 0), Offset(sweepX, h), lineCore);

    // ── Corner reticles that "lock on" to the frame ──────────────────────
    final pulse = 0.5 + 0.5 * math.sin(progress * 2 * math.pi);
    const inset = 26.0;
    final bracket = 34.0 + 6.0 * pulse;
    final reticle = Paint()
      ..color = primary.withValues(alpha: (0.55 + 0.35 * pulse) * a)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void corner(double cx, double cy, double sx, double sy) {
      canvas.drawLine(
          Offset(cx, cy), Offset(cx + bracket * sx, cy), reticle);
      canvas.drawLine(
          Offset(cx, cy), Offset(cx, cy + bracket * sy), reticle);
    }

    corner(inset, inset, 1, 1);
    corner(w - inset, inset, -1, 1);
    corner(inset, h - inset, 1, -1);
    corner(w - inset, h - inset, -1, -1);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.intensity != intensity ||
      old.colors != colors;
}
