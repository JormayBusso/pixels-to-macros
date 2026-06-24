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

    // Flowing sweep of the theme colours around the border. Duplicate the first
    // colour at the end so the sweep wraps seamlessly.
    final shader = SweepGradient(
      colors: [...colors, colors.first],
      transform: GradientRotation(phase),
    ).createShader(rect);

    // Edge-hugging frame just inside the screen bounds.
    final inset = 1.5;
    final frame = RRect.fromRectAndRadius(
      rect.deflate(inset),
      const Radius.circular(34),
    );

    // Outer soft bloom — wide blurred stroke kept close to the edge so the glow
    // reads as an aura on the border rather than a wash over the whole screen.
    final bloom = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30 * intensity
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
      ..color = Colors.white.withValues(alpha: 0.42 * opacity * intensity);
    canvas.saveLayer(rect, Paint());
    canvas.drawRRect(frame, bloom);
    canvas.restore();

    // Crisp inner edge line for a defined, premium border.
    final line = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2)
      ..color = Colors.white.withValues(alpha: 0.85 * opacity);
    canvas.drawRRect(frame, line);

    // Subtle corner accents that brighten as the sweep passes — the part that
    // makes the effect feel "alive" like Siri without a gaming RGB look.
    final accent = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7 * intensity
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..color = Colors.white.withValues(alpha: 0.30 * opacity * intensity);
    for (var i = 0; i < 4; i++) {
      final a = phase + i * math.pi / 2;
      final pulse = 0.5 + 0.5 * math.sin(a);
      if (pulse < 0.55) continue;
      final corner = Offset(
        center.dx + (i == 0 || i == 3 ? 1 : -1) * (size.width / 2 - 20),
        center.dy + (i < 2 ? -1 : 1) * (size.height / 2 - 20),
      );
      canvas.drawCircle(corner, 26 * pulse * intensity, accent);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeGlowPainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.intensity != intensity ||
      old.colors != colors;
}
