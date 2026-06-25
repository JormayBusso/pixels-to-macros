import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Apple-Intelligence / Siri-inspired edge effect for the AI scan screen.
///
/// Renders a soft, animated colour glow that hugs the screen edges to signal
/// that on-device intelligence is active. Design constraints:
///   • Theme-aware — colours follow the active premium theme's [gradient].
///   • Animated — colours flow slowly around the border.
///   • Edge-contained — the glow stays near the edges (no centre wash, no
///     oversized bloom).
///   • Cheap — a single blurred [SweepGradient] stroke inside a
///     [RepaintBoundary]; no per-frame allocations beyond the shader.
///   • Respectful — renders nothing for non-premium themes and falls back to a
///     static glow when the user has reduced motion enabled.
class AiScanEdgeGlow extends StatefulWidget {
  const AiScanEdgeGlow({
    super.key,
    this.active = true,
    this.intensity = 1.0,
  });

  /// When false the glow eases out (used between scan phases).
  final bool active;

  /// 0…1 overall strength multiplier.
  final double intensity;

  @override
  State<AiScanEdgeGlow> createState() => _AiScanEdgeGlowState();
}

class _AiScanEdgeGlowState extends State<AiScanEdgeGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: widget.active ? 1.0 : 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AiScanEdgeGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final visual = context.visualTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldFlow = visual.premium &&
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !reduceMotion;
    if (shouldFlow && !_flow.isAnimating) {
      _flow.repeat();
    } else if (!shouldFlow && _flow.isAnimating) {
      _flow.stop();
    }
    if (widget.active) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    if (!visual.premium) return const SizedBox.shrink();

    final colors = visual.gradient.length >= 2
        ? visual.gradient
        : [visual.primaryAccent, visual.secondaryAccent, visual.primaryAccent];

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_flow, _fade]),
          builder: (context, _) {
            final opacity = Curves.easeInOut.transform(_fade.value);
            if (opacity <= 0.001) return const SizedBox.shrink();
            return CustomPaint(
              size: Size.infinite,
              painter: _EdgeGlowPainter(
                colors: colors,
                progress: _flow.value,
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

class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter({
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
    final rect = Offset.zero & size;
    final center = rect.center;
    final phase = progress * 2 * math.pi;
    final i = intensity.clamp(0.0, 1.0);

    // Flowing sweep of the theme colours around the border. Duplicate the first
    // colour at the end so the sweep wraps seamlessly.
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(phase),
    ).createShader(rect);

    // Clip to the screen so nothing can ever bleed past the edges.
    canvas.save();
    canvas.clipRect(rect);

    // Inset the frame well inside the screen edges. Devices have rounded
    // display corners, so a frame flush to the edge gets visually "cut" at the
    // corners and looks like it spills off-screen. Sitting it ~14px in with a
    // generous corner radius keeps the whole band visible and contained.
    const margin = 0.0;
    final frame = RRect.fromRectAndRadius(
      rect.deflate(margin),
      const Radius.circular(52),
    );

    // Layered inward bloom: wide & soft → dense & bright → hot core band. The
    // strokes are centred on the inset frame so the glow spreads inward; the
    // outward half stays within the margin and is clipped flush.
    canvas.saveLayer(rect, Paint());
    const blooms = <({double width, double blur, double alpha})>[
      (width: 30, blur: 8, alpha: 0.30),
      (width: 20, blur: 6, alpha: 0.55),
      (width: 10, blur: 4, alpha: 0.85),
    ];
    for (final b in blooms) {
      final paint = Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.width * i
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.blur)
        ..color = Colors.white.withValues(alpha: b.alpha * opacity);
      canvas.drawRRect(frame, paint);
    }
    canvas.restore();

    // Crisp, vivid inner edge line for a defined premium border.
    final line = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0)
      ..color = Colors.white.withValues(alpha: 0.96 * opacity);
    canvas.drawRRect(frame, line);

    // Gentle pulsing corner accents (additive) that brighten as the sweep
    // passes — kept small and inset so they read as energy, not stray blobs.
    final accent = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12 * i
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
      ..blendMode = BlendMode.plus
      ..color = Colors.white.withValues(alpha: 0.22 * opacity * i);
    for (var c = 0; c < 4; c++) {
      final a = phase + c * math.pi / 2;
      final pulse = 0.5 + 0.5 * math.sin(a);
      if (pulse < 0.5) continue;
      final corner = Offset(
        center.dx + (c == 0 || c == 3 ? 1 : -1) * (size.width / 2 - margin - 6),
        center.dy + (c < 2 ? -1 : 1) * (size.height / 2 - margin - 6),
      );
      canvas.drawCircle(corner, 44 * pulse * i, accent);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EdgeGlowPainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.intensity != intensity ||
      old.colors != colors;
}
