import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/mascot_type.dart';
import '../theme/app_theme.dart';

class PremiumMotionSurface extends StatefulWidget {
  const PremiumMotionSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding = EdgeInsets.zero,
    this.borderWidth = 1.4,
    this.glow = true,
    this.enabled = true,
    this.animate = false,
    this.fillColor,
    this.glowExtent,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final double borderWidth;
  final bool glow;
  final bool enabled;
  final bool animate;
  final Color? fillColor;
  final double? glowExtent;

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
        widget.animate &&
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
          // Tier 3 (AI-active) surfaces animate => render a bolder, glowing,
          // moving border. Static Tier 1/2 surfaces keep a subtle border.
          final intense = widget.animate;
          final glowExtent = widget.glow
              ? widget.glowExtent ??
                  (intense
                      ? _premiumGlowExtentIntense(visual)
                      : _premiumGlowExtent(visual))
              : 0.0;
          final effectiveBorderWidth = intense
              ? widget.borderWidth.clamp(1.6, 4.0).toDouble()
              : widget.borderWidth.clamp(0.8, 2.0).toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: -glowExtent,
                top: -glowExtent,
                right: -glowExtent,
                bottom: -glowExtent,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _PremiumMotionPainter(
                      visual: visual,
                      progress: _controller.value,
                      borderRadius: widget.borderRadius,
                      borderWidth: effectiveBorderWidth,
                      glow: widget.glow,
                      intense: intense,
                      fillColor: widget.fillColor,
                      contentInset: glowExtent,
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
      ),
    );
  }
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.borderWidth = 1.2,
    this.glow = true,
    this.enabled = true,
    this.animate = false,
    this.fillColor,
    this.onTap,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final BorderRadius borderRadius;
  final double borderWidth;
  final bool glow;
  final bool enabled;
  final bool animate;
  final Color? fillColor;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final radius = borderRadius;
    final content = Padding(padding: padding, child: child);

    if (!enabled || !visual.premium) {
      final card = Card(
        margin: margin,
        clipBehavior: clipBehavior,
        shape: RoundedRectangleBorder(borderRadius: radius),
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: radius.resolve(Directionality.of(context)),
                child: content,
              ),
      );
      return card;
    }

    Widget premiumChild = content;
    if (clipBehavior != Clip.none) {
      premiumChild = ClipRRect(
        borderRadius: radius.resolve(Directionality.of(context)),
        clipBehavior: clipBehavior,
        child: premiumChild,
      );
    }
    if (onTap != null) {
      premiumChild = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius.resolve(Directionality.of(context)),
          child: premiumChild,
        ),
      );
    }

    return Padding(
      padding: margin,
      child: PremiumMotionSurface(
        borderRadius: radius,
        borderWidth: borderWidth,
        glow: glow,
        animate: animate,
        fillColor: fillColor ?? visual.cardColor,
        child: premiumChild,
      ),
    );
  }
}

double _premiumGlowExtent(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 10;
    case AppColorSeed.geminiAI:
      return 9;
    case AppColorSeed.liquidGlass:
      return 7;
    default:
      return 8;
  }
}

// Larger (but still controlled) glow halo for Tier 3 AI-active surfaces.
double _premiumGlowExtentIntense(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 22;
    case AppColorSeed.geminiAI:
      return 20;
    case AppColorSeed.liquidGlass:
      return 16;
    default:
      return 18;
  }
}

double _premiumGlowBaseAlpha(AppVisualTheme visual, double pulse) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 0.20 + pulse * 0.04;
    case AppColorSeed.geminiAI:
      return 0.16 + pulse * 0.03;
    case AppColorSeed.liquidGlass:
      return 0.12 + pulse * 0.025;
    default:
      return 0.16 + pulse * 0.035;
  }
}

// Stronger, pulsing glow alpha for Tier 3 AI-active surfaces.
double _premiumGlowBaseAlphaIntense(AppVisualTheme visual, double pulse) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 0.42 + pulse * 0.12;
    case AppColorSeed.geminiAI:
      return 0.34 + pulse * 0.10;
    case AppColorSeed.liquidGlass:
      return 0.26 + pulse * 0.08;
    default:
      return 0.34 + pulse * 0.10;
  }
}

class _GlowLayer {
  const _GlowLayer({
    required this.inflate,
    required this.strokeExtra,
    required this.blur,
    required this.alphaScale,
  });

  final double inflate;
  final double strokeExtra;
  final double blur;
  final double alphaScale;
}

const List<_GlowLayer> _glowLayers = [
  _GlowLayer(inflate: 3.2, strokeExtra: 1.0, blur: 10, alphaScale: 0.28),
  _GlowLayer(inflate: 1.2, strokeExtra: 0.5, blur: 5, alphaScale: 0.38),
];

// Richer bloom (more layers, wider blur) for Tier 3 AI-active surfaces.
const List<_GlowLayer> _glowLayersIntense = [
  _GlowLayer(inflate: 11, strokeExtra: 2.6, blur: 30, alphaScale: 0.34),
  _GlowLayer(inflate: 6, strokeExtra: 1.6, blur: 18, alphaScale: 0.50),
  _GlowLayer(inflate: 2.6, strokeExtra: 0.9, blur: 10, alphaScale: 0.70),
];

class PremiumFocusRing extends StatelessWidget {
  const PremiumFocusRing({
    super.key,
    required this.child,
    this.radius = 21,
    this.padding = const EdgeInsets.all(4),
    this.enabled = true,
    this.animate = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final bool enabled;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final visual = context.visualTheme;
    if (!visual.premium) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: child,
      );
    }
    return PremiumMotionSurface(
      enabled: true,
      animate: animate,
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      borderWidth: animate ? 2.8 : 1.6,
      child: child,
    );
  }
}

class PremiumGradientText extends StatefulWidget {
  const PremiumGradientText({
    super.key,
    required this.text,
    required this.style,
    this.enabled = true,
    this.animate = false,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final bool enabled;
  final bool animate;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  State<PremiumGradientText> createState() => _PremiumGradientTextState();
}

class _PremiumGradientTextState extends State<PremiumGradientText>
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
  void didUpdateWidget(covariant PremiumGradientText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final visual = context.visualTheme;
    _controller.duration = visual.motionDuration;
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate = widget.enabled &&
        widget.animate &&
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
    if (!widget.enabled || !visual.premium) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return _premiumLinearShader(
                visual,
                bounds,
                _premiumMotionPhase(visual, _controller.value),
              );
            },
            child: Text(
              widget.text,
              style: widget.style.copyWith(color: Colors.white),
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              textAlign: widget.textAlign,
            ),
          );
        },
      ),
    );
  }
}

int _premiumGradientSamples(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 192;
    case AppColorSeed.geminiAI:
      return 160;
    case AppColorSeed.liquidGlass:
      return 144;
    default:
      return 128;
  }
}

double _premiumMotionPhase(AppVisualTheme visual, double progress) {
  final phase = progress % 1.0;
  return phase < 0 ? phase + 1 : phase;
}

List<double> _premiumGradientStops(AppVisualTheme visual) {
  final samples = _premiumGradientSamples(visual);
  return List<double>.generate(
    samples + 1,
    (index) => index / samples,
    growable: false,
  );
}

List<Color> _premiumGradientColors(
  AppVisualTheme visual, {
  double alpha = 1,
}) {
  final anchors = _premiumColorAnchors(visual);
  final saturationScale = _premiumSaturationScale(visual);
  final lightnessScale = _premiumLightnessScale(visual);
  final samples = _premiumGradientSamples(visual);
  final drift = _premiumColorDrift(visual);
  return List<Color>.generate(samples + 1, (index) {
    final t = index / samples;
    return _samplePremiumColor(
      anchors,
      t + drift,
      alpha: alpha,
      saturationScale: saturationScale,
      lightnessScale: lightnessScale,
    );
  }, growable: false);
}

double _premiumColorDrift(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 0.035;
    case AppColorSeed.geminiAI:
      return 0.012;
    default:
      return 0;
  }
}

List<Color> _premiumColorAnchors(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return const [
        Color(0xFF74A9FF),
        Color(0xFF9BC8FF),
        Color(0xFFC4B5FD),
        Color(0xFFFFA8DD),
        Color(0xFFA5F3FC),
        Color(0xFFB8D8FF),
      ];
    case AppColorSeed.geminiAI:
      return const [
        Color(0xFF4F8CFF),
        Color(0xFF38BDF8),
        Color(0xFF22D3EE),
        Color(0xFF60A5FA),
        Color(0xFF8B5CF6),
        Color(0xFFB8C7FF),
      ];
    case AppColorSeed.liquidGlass:
      return const [
        Color(0xFFF8FAFC),
        Color(0xFFE5E7EB),
        Color(0xFFB8C0CC),
        Color(0xFF8B95A5),
        Color(0xFFEFF3F8),
      ];
    default:
      return visual.gradient.length >= 3
          ? visual.gradient
          : [
              visual.primaryAccent,
              visual.secondaryAccent,
              visual.primaryAccent
            ];
  }
}

double _premiumSaturationScale(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.geminiAI:
      return 0.96;
    case AppColorSeed.liquidGlass:
      return 0.44;
    case AppColorSeed.aiAurora:
      return 1.08;
    default:
      return 1.04;
  }
}

double _premiumLightnessScale(AppVisualTheme visual) {
  switch (visual.seed) {
    case AppColorSeed.aiAurora:
      return 1.05;
    case AppColorSeed.geminiAI:
      return 1.02;
    case AppColorSeed.liquidGlass:
      return 1.08;
    default:
      return 1.0;
  }
}

Color _samplePremiumColor(
  List<Color> anchors,
  double t, {
  required double alpha,
  required double saturationScale,
  required double lightnessScale,
}) {
  if (anchors.isEmpty) return Colors.transparent;
  if (anchors.length == 1) return anchors.first.withValues(alpha: alpha);

  final unit = t - t.floorToDouble();
  final scaled = unit * anchors.length;
  final index = scaled.floor() % anchors.length;
  final next = (index + 1) % anchors.length;
  final local = scaled - index;
  final eased = _smootherStep(local);
  final from = HSLColor.fromColor(anchors[index]);
  final to = HSLColor.fromColor(anchors[next]);
  final hue = _lerpHue(from.hue, to.hue, eased);
  final saturation =
      _lerpDouble(from.saturation, to.saturation, eased) * saturationScale;
  final lightness =
      _lerpDouble(from.lightness, to.lightness, eased) * lightnessScale;
  final mixedAlpha = _lerpDouble(from.alpha, to.alpha, eased) * alpha;
  return HSLColor.fromAHSL(
    mixedAlpha.clamp(0.0, 1.0),
    hue,
    saturation.clamp(0.0, 1.0),
    lightness.clamp(0.0, 1.0),
  ).toColor();
}

double _smootherStep(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

double _lerpHue(double a, double b, double t) {
  final delta = ((b - a + 540) % 360) - 180;
  final hue = (a + delta * t) % 360;
  return hue < 0 ? hue + 360 : hue;
}

Shader _premiumSweepShader(
  AppVisualTheme visual,
  Rect rect,
  double phase, {
  required double alpha,
}) {
  return SweepGradient(
    colors: _premiumGradientColors(visual, alpha: alpha),
    stops: _premiumGradientStops(visual),
    transform: GradientRotation(phase * math.pi * 2),
  ).createShader(rect);
}

Shader _premiumLinearShader(
  AppVisualTheme visual,
  Rect rect,
  double phase, {
  double alpha = 1,
}) {
  final slide = phase * 2.0;
  final shaderRect = rect.inflate(rect.size.longestSide * 0.35);
  return LinearGradient(
    begin: Alignment(-1.35 + slide, -0.85),
    end: Alignment(0.65 + slide, 0.95),
    colors: _premiumGradientColors(visual, alpha: alpha),
    stops: _premiumGradientStops(visual),
    tileMode: TileMode.mirror,
  ).createShader(shaderRect);
}

class _PremiumMotionPainter extends CustomPainter {
  const _PremiumMotionPainter({
    required this.visual,
    required this.progress,
    required this.borderRadius,
    required this.borderWidth,
    required this.glow,
    required this.intense,
    required this.fillColor,
    required this.contentInset,
  });

  final AppVisualTheme visual;
  final double progress;
  final BorderRadius borderRadius;
  final double borderWidth;
  final bool glow;
  final bool intense;
  final Color? fillColor;
  final double contentInset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Rect.fromLTWH(
      contentInset,
      contentInset,
      math.max(0, size.width - contentInset * 2),
      math.max(0, size.height - contentInset * 2),
    );
    if (rect.isEmpty) return;
    final rrect = borderRadius.toRRect(rect.deflate(borderWidth / 2));
    final phase = _premiumMotionPhase(visual, progress);

    if (fillColor != null) {
      canvas.drawRRect(rrect, Paint()..color = fillColor!);
    }

    if (glow) _paintGlow(canvas, rrect, rect, phase);

    switch (visual.motionStyle) {
      case AppPremiumMotionStyle.aurora:
        _paintAurora(canvas, rrect, rect, phase);
        break;
      case AppPremiumMotionStyle.glass:
        _paintGlass(canvas, rrect, rect, phase);
        break;
      case AppPremiumMotionStyle.pulse:
        _paintPulse(canvas, rrect, rect, phase);
        break;
      case AppPremiumMotionStyle.standard:
        break;
    }
  }

  void _paintGlow(Canvas canvas, RRect rrect, Rect rect, double phase) {
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final alpha = intense
        ? _premiumGlowBaseAlphaIntense(visual, pulse)
        : _premiumGlowBaseAlpha(visual, pulse);
    final shaderRect = rect.inflate(contentInset + (intense ? 16 : 8));
    final layers = intense ? _glowLayersIntense : _glowLayers;

    for (final layer in layers) {
      final bloom = Paint()
        ..shader = _premiumSweepShader(
          visual,
          shaderRect,
          phase,
          alpha: alpha * layer.alphaScale,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth + layer.strokeExtra
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, layer.blur);
      canvas.drawRRect(
        borderRadius.toRRect(rect.inflate(layer.inflate)),
        bloom,
      );
    }
  }

  void _paintAurora(Canvas canvas, RRect rrect, Rect rect, double phase) {
    final borderAlpha = visual.seed == AppColorSeed.geminiAI ? 0.84 : 0.96;
    _paintBorder(canvas, rrect, rect, phase, alpha: borderAlpha);
  }

  void _paintGlass(Canvas canvas, RRect rrect, Rect rect, double phase) {
    _paintBorder(canvas, rrect, rect, phase, alpha: 0.68);
  }

  void _paintPulse(Canvas canvas, RRect rrect, Rect rect, double phase) {
    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    _paintBorder(
      canvas,
      rrect,
      rect,
      phase,
      alpha: 0.54 + pulse * 0.18,
    );
  }

  void _paintBorder(
    Canvas canvas,
    RRect rrect,
    Rect rect,
    double phase, {
    required double alpha,
  }) {
    final border = Paint()
      ..shader = _premiumSweepShader(
        visual,
        rect.inflate(4),
        phase,
        alpha: alpha,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, border);
  }

  @override
  bool shouldRepaint(covariant _PremiumMotionPainter oldDelegate) {
    return oldDelegate.visual != visual ||
        oldDelegate.progress != progress ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.glow != glow ||
        oldDelegate.intense != intense ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.contentInset != contentInset;
  }
}
