import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PremiumMotionSurface extends StatefulWidget {
  const PremiumMotionSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = EdgeInsets.zero,
    this.borderWidth = 1.5,
    this.glow = true,
    this.enabled = true,
    this.fillColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final double borderWidth;
  final bool glow;
  final bool enabled;
  final Color? fillColor;

  @override
  State<PremiumMotionSurface> createState() => _PremiumMotionSurfaceState();
}

class _PremiumMotionSurfaceState extends State<PremiumMotionSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant PremiumMotionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final visual = context.visualTheme;
    _controller.duration = visual.motionDuration;
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate = widget.enabled &&
        visual.premium &&
        TickerMode.valuesOf(context).enabled &&
        !reduceMotion;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    if (!widget.enabled || !visual.premium) return widget.child;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: Padding(padding: widget.padding, child: widget.child),
        builder: (context, child) {
          return CustomPaint(
            painter: _PremiumMotionPainter(
              visual: visual,
              progress: _controller.value,
              borderRadius: widget.borderRadius,
              borderWidth: widget.borderWidth,
              glow: widget.glow,
              fillColor: widget.fillColor,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class PremiumFocusRing extends StatelessWidget {
  const PremiumFocusRing({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = const EdgeInsets.all(3),
    this.enabled = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return PremiumMotionSurface(
      enabled: enabled,
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      borderWidth: 1.4,
      child: child,
    );
  }
}

class _PremiumMotionPainter extends CustomPainter {
  const _PremiumMotionPainter({
    required this.visual,
    required this.progress,
    required this.borderRadius,
    required this.borderWidth,
    required this.glow,
    required this.fillColor,
  });

  final AppVisualTheme visual;
  final double progress;
  final BorderRadius borderRadius;
  final double borderWidth;
  final bool glow;
  final Color? fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect.deflate(borderWidth / 2));

    if (fillColor != null) {
      canvas.drawRRect(rrect, Paint()..color = fillColor!);
    }

    if (glow) _paintGlow(canvas, rrect, rect);

    switch (visual.motionStyle) {
      case AppPremiumMotionStyle.aurora:
        _paintAurora(canvas, rrect, rect);
        break;
      case AppPremiumMotionStyle.glass:
        _paintGlass(canvas, rrect, rect);
        break;
      case AppPremiumMotionStyle.pulse:
        _paintPulse(canvas, rrect, rect);
        break;
      case AppPremiumMotionStyle.standard:
        break;
    }
  }

  void _paintGlow(Canvas canvas, RRect rrect, Rect rect) {
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final alpha = switch (visual.motionStyle) {
      AppPremiumMotionStyle.glass => 0.10 + pulse * 0.05,
      AppPremiumMotionStyle.pulse => 0.12 + pulse * 0.10,
      _ => 0.12 + pulse * 0.06,
    };
    final glowPaint = Paint()
      ..color = visual.glowColor.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(rrect, glowPaint);
  }

  void _paintAurora(Canvas canvas, RRect rrect, Rect rect) {
    final colors = [...visual.gradient, visual.gradient.first];
    final border = Paint()
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, border);

    _drawTrace(
      canvas,
      rrect,
      color: visual.secondaryAccent.withValues(alpha: 0.48),
      width: borderWidth + 0.8,
      phase: progress,
      fraction: 0.26,
    );
  }

  void _paintGlass(Canvas canvas, RRect rrect, Rect rect) {
    final base = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, base);

    final sweepRect = rect.inflate(rect.size.longestSide * 0.25);
    final shimmer = Paint()
      ..shader = LinearGradient(
        begin: Alignment(-1.0 + progress * 2.0, -1),
        end: Alignment(-0.2 + progress * 2.0, 1),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.58),
          visual.secondaryAccent.withValues(alpha: 0.20),
          Colors.transparent,
        ],
        stops: const [0.18, 0.46, 0.58, 0.82],
      ).createShader(sweepRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth + 0.7;
    canvas.drawRRect(rrect, shimmer);
  }

  void _paintPulse(Canvas canvas, RRect rrect, Rect rect) {
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final base = Paint()
      ..color = visual.primaryAccent.withValues(alpha: 0.25 + pulse * 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, base);

    _drawTrace(
      canvas,
      rrect,
      color: visual.gradient.last.withValues(alpha: 0.64),
      width: borderWidth + 0.6,
      phase: progress,
      fraction: 0.18,
    );
  }

  void _drawTrace(
    Canvas canvas,
    RRect rrect, {
    required Color color,
    required double width,
    required double phase,
    required double fraction,
  }) {
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;

    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      if (length <= 0) continue;
      final traceLength = length * fraction;
      final start = (length * phase) % length;
      final end = start + traceLength;
      if (end <= length) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, length), paint);
        canvas.drawPath(metric.extractPath(0, end - length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumMotionPainter oldDelegate) {
    return oldDelegate.visual != visual ||
        oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.glow != glow ||
        oldDelegate.fillColor != fillColor;
  }
}
