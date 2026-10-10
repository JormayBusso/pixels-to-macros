import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_localizations.dart';
import '../core/scan_state.dart';
import '../theme/app_theme.dart';
import 'ai_scan_sweep_overlay.dart';

/// Shared geometry of the capture guide (the region of interest).
///
/// The guide is centred on the full-screen camera view. The TOP view uses a
/// circle; the SIDE view uses a wide, low rounded rectangle with the same width
/// as the circle's diameter, a height of [sideHeightFactor] × that width and a
/// corner radius of [sideCornerFactor] × its height. The native live-glow ROI
/// and the capture ROI use exactly this mapping.
class ScanGuideGeometry {
  const ScanGuideGeometry._();

  /// Mirrors the native capture ROI (`ScanMaskGeometry` in
  /// InferencePipeline.swift): the camera frame is cropped to its centred
  /// square (side S = short side); the TOP circle radius and the SIDE
  /// rectangle half-width are `roiRadiusFraction · S`, the rectangle
  /// half-height is `sideHeightFactor` × that, and its corner radius is
  /// `sideCornerFactor` × the full rectangle height.
  static const double roiRadiusFraction = 0.485;
  static const double sideHeightFactor = 0.55;
  static const double sideCornerFactor = 0.18;

  /// ARKit's default world-tracking video format (1920×1440) until native
  /// reports the real one.
  static const double defaultVideoAspect = 1920 / 1440;

  /// The camera image inside a full-screen preview of [size], matching the
  /// native `.resizeAspect` layout (the sensor's long side follows the
  /// screen's long side).
  static Rect videoRect(Size size, [double videoAspect = defaultVideoAspect]) {
    final aspect = videoAspect >= 1 ? videoAspect : 1 / videoAspect;
    final landscape = size.width >= size.height;
    final long = landscape ? size.width : size.height;
    final short = landscape ? size.height : size.width;
    final fitLong = math.min(long, short * aspect);
    final fitShort = fitLong / aspect;
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: landscape ? fitLong : fitShort,
      height: landscape ? fitShort : fitLong,
    );
  }

  /// Circle radius (= side rectangle half-width) in logical px.
  static double radius(Size size, [double videoAspect = defaultVideoAspect]) =>
      roiRadiusFraction * videoRect(size, videoAspect).shortestSide;

  /// Guide shape morphed between the circle (`t = 0`, top view) and the
  /// rounded rectangle (`t = 1`, side view, long side horizontal).
  static RRect guide(
    Size size,
    double t, [
    double videoAspect = defaultVideoAspect,
  ]) {
    final r = radius(size, videoAspect);
    final width = 2 * r;
    final sideHeight = width * sideHeightFactor;
    final height = ui.lerpDouble(width, sideHeight, t)!;
    final corner = ui.lerpDouble(r, sideHeight * sideCornerFactor, t)!;
    return RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: videoRect(size, videoAspect).center,
        width: width,
        height: height,
      ),
      Radius.circular(corner),
    );
  }

  /// Width of the aspect-fit camera image inside the view.
  static double previewWidth(
    Size size, [
    double videoAspect = defaultVideoAspect,
  ]) =>
      videoRect(size, videoAspect).width;

  /// Horizontal centre of the right-hand control rail (shutter / flash),
  /// placed in the letterbox bar beside the camera image when there is room.
  static double rightRailCenterX(
    Size size,
    EdgeInsets padding, [
    double videoAspect = defaultVideoAspect,
  ]) {
    final inner = math.max(
      size.width / 2 + radius(size, videoAspect) + 12,
      (size.width + previewWidth(size, videoAspect)) / 2,
    );
    final outer = size.width - padding.right;
    return outer - inner >= 80 ? (inner + outer) / 2 : outer - 44;
  }
}

/// Accent colours for the dark camera chrome. Default themes get a single,
/// restrained accent; premium themes get their full gradient. Very dark
/// accents (e.g. from premium light themes) are lifted so they stay readable
/// on the black camera UI.
@immutable
class ScanChromePalette {
  const ScanChromePalette({
    required this.premium,
    required this.accent,
    required this.secondary,
    required this.gradient,
  });

  factory ScanChromePalette.of(BuildContext context) {
    final visual = context.visualTheme;
    if (!visual.premium) {
      final accent = onDark(context.primary400);
      return ScanChromePalette(
        premium: false,
        accent: accent,
        secondary: accent,
        gradient: [accent, accent],
      );
    }
    final raw = visual.gradient.length >= 2
        ? visual.gradient
        : [visual.primaryAccent, visual.secondaryAccent];
    return ScanChromePalette(
      premium: true,
      accent: onDark(visual.primaryAccent),
      secondary: onDark(visual.secondaryAccent),
      gradient: raw.map(onDark).toList(growable: false),
    );
  }

  final bool premium;
  final Color accent;
  final Color secondary;
  final List<Color> gradient;

  /// Foreground (white/black) that is readable on top of [accent].
  Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : Colors.black;

  /// ARGB ints for the native live glow.
  List<int> get nativeColors => premium
      ? [for (final c in gradient) c.toARGB32()]
      : [accent.toARGB32()];

  static Color onDark(Color c) {
    var hsl = HSLColor.fromColor(c);
    var out = c;
    for (var i = 0; i < 12 && out.computeLuminance() < 0.2; i++) {
      hsl = hsl.withLightness(math.min(1.0, hsl.lightness + 0.05));
      out = hsl.toColor();
    }
    return out;
  }

  @override
  bool operator ==(Object other) =>
      other is ScanChromePalette &&
      other.premium == premium &&
      other.accent == accent &&
      other.secondary == secondary &&
      _listEquals(other.gradient, gradient);

  @override
  int get hashCode =>
      Object.hash(premium, accent, secondary, Object.hashAll(gradient));

  static bool _listEquals(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Guided dual-photo capture overlay (landscape).
///
/// Drives the two-step capture flow — **Top view** then **Side view** — with a
/// morphing framing guide (circle → rounded rectangle), a precise tilt gauge,
/// an alignment readout with directional guidance, a live "food detected"
/// tag, and an iOS-style shutter that traces the hold-steady progress. The
/// auto shutter is owned by the scan screen; this widget is pure presentation
/// plus an optional manual-capture fallback.
class DualPhotoCaptureOverlay extends StatefulWidget {
  const DualPhotoCaptureOverlay({
    super.key,
    required this.scanState,
    required this.aligned,
    required this.alignmentScore,
    required this.stability,
    required this.holdProgress,
    required this.capturing,
    required this.scanMode,
    this.tiltError = 0.0,
    this.foodDetected = false,
    this.liveDetectionAvailable = false,
    this.videoAspect = ScanGuideGeometry.defaultVideoAspect,
    this.onManualCapture,
  });

  final ScanState scanState;

  /// Whether the device currently matches the active step's target orientation.
  final bool aligned;

  /// Target-orientation alignment score in 0…1, shown as the tilt percentage.
  final double alignmentScore;

  /// Live motion stability 0…1 (1 = perfectly still).
  final double stability;

  /// Progress 0…1 of the aligned+stable hold before the auto shutter fires.
  final double holdProgress;

  /// True during the brief capture-confirmation flash.
  final bool capturing;

  /// Native capability mode (e.g. monocular_scale, lidar_mesh).
  final String scanMode;

  /// Signed pitch error (radians) of the camera vs. the active step's target.
  /// Positive = the camera points above the target (tilt down).
  final double tiltError;

  /// Whether the live detector currently sees food inside the guide.
  final bool foodDetected;

  /// Whether the native live detector is running (shows the status tag).
  final bool liveDetectionAvailable;

  /// Camera frame aspect ratio (long / short side) reported by native; the
  /// guide is laid out on the frame's centred square like the native ROI.
  final double videoAspect;

  /// Manual-capture fallback, invoked if the user taps the shutter.
  final VoidCallback? onManualCapture;

  /// Pitch error (radians) at which the tilt gauge pins to its end stop.
  static const double gaugeRangeRad = 0.384;

  bool get _isTopStep =>
      scanState == ScanState.waitingForTopView ||
      scanState == ScanState.captureTop;

  bool get _isConfirming =>
      scanState == ScanState.captureTop || scanState == ScanState.captureSide;

  @override
  State<DualPhotoCaptureOverlay> createState() =>
      _DualPhotoCaptureOverlayState();
}

class _DualPhotoCaptureOverlayState extends State<DualPhotoCaptureOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _morph;
  late final CurvedAnimation _morphCurve;
  late final AnimationController _align;
  late final AnimationController _ambient;
  DateTime _lastLevelHaptic = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _reduceMotion {
    final mq = MediaQuery.of(context);
    return mq.disableAnimations || mq.accessibleNavigation;
  }

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: widget._isTopStep ? 0.0 : 1.0,
    );
    _morphCurve =
        CurvedAnimation(parent: _morph, curve: Curves.easeInOutCubic);
    _align = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.aligned ? 1.0 : 0.0,
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAmbient();
  }

  @override
  void didUpdateWidget(covariant DualPhotoCaptureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final top = widget._isTopStep;
    if (top != oldWidget._isTopStep) {
      final target = top ? 0.0 : 1.0;
      if (_reduceMotion) {
        _morph.value = target;
      } else {
        _morph.animateTo(target);
      }
    }
    if (widget.aligned != oldWidget.aligned) {
      _align.animateTo(widget.aligned ? 1.0 : 0.0);
      // A light "detent" when the phone snaps level, like the iOS level.
      final now = DateTime.now();
      if (widget.aligned &&
          !widget._isConfirming &&
          now.difference(_lastLevelHaptic).inMilliseconds >= 600) {
        _lastLevelHaptic = now;
        HapticFeedback.selectionClick();
      }
    }
    _syncAmbient();
  }

  void _syncAmbient() {
    final premium = context.visualTheme.premium;
    final shouldAnimate =
        premium && !_reduceMotion && TickerMode.valuesOf(context).enabled;
    if (shouldAnimate && !_ambient.isAnimating) {
      _ambient.repeat();
    } else if (!shouldAnimate && _ambient.isAnimating) {
      _ambient.stop();
    }
  }

  @override
  void dispose() {
    _morphCurve.dispose();
    _morph.dispose();
    _align.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ScanChromePalette.of(context);
    final top = widget._isTopStep;
    final confirming = widget._isConfirming;
    final padding = MediaQuery.paddingOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final aspect = widget.videoAspect;
        final r = ScanGuideGeometry.radius(size, aspect);
        final panelLeft = padding.left + 12;
        final panelWidth =
            ((size.width / 2 - r - 44) - panelLeft).clamp(112.0, 176.0);
        final railX =
            ScanGuideGeometry.rightRailCenterX(size, padding, aspect);
        final gaugeHeight = math.min(r * 1.15, 170.0);
        final gaugeX = size.width / 2 - r - 26;
        final gaugeValue =
            (widget.tiltError / DualPhotoCaptureOverlay.gaugeRangeRad)
                .clamp(-1.0, 1.0);

        return Stack(
          children: [
            // Capture flash.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.capturing ? 0.32 : 0.0,
                  duration: const Duration(milliseconds: 120),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),

            // Framing guide (ROI), searching sheen and status tag — all
            // driven by the circle ↔ rounded-rectangle morph.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _morphCurve,
                  builder: (context, _) {
                    final guide = ScanGuideGeometry.guide(
                        size, _morphCurve.value, aspect);
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _GuidePainter(
                                guide: guide,
                                palette: palette,
                                ambient: _ambient,
                                align: _align,
                                holdProgress: widget.aligned
                                    ? widget.holdProgress
                                    : 0.0,
                                confirming: confirming,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: AiScanSweepOverlay(
                            guide: guide,
                            palette: palette,
                            active: !confirming,
                            searching: !widget.foodDetected,
                          ),
                        ),
                        if (widget.liveDetectionAvailable)
                          Positioned(
                            left: guide.left,
                            width: guide.width,
                            top: math.max(guide.top - 14, padding.top + 4),
                            height: 28,
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: confirming ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: _StatusTag(
                                  detected: widget.foodDetected,
                                  palette: palette,
                                  label: widget.foodDetected
                                      ? l10n.scanFoodDetected
                                      : l10n.scanLookingForFood,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // Capture confirmation badge in the centre of the guide.
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedScale(
                    scale: confirming ? 1.0 : 0.6,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    child: AnimatedOpacity(
                      opacity: confirming ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: _ConfirmBadge(palette: palette),
                    ),
                  ),
                ),
              ),
            ),

            // Precision tilt gauge, just left of the guide.
            Positioned(
              left: gaugeX - 11,
              top: size.height / 2 - gaugeHeight / 2,
              width: 22,
              height: gaugeHeight,
              child: IgnorePointer(
                child: _TiltGauge(
                  value: confirming ? 0.0 : gaugeValue,
                  aligned: widget.aligned || confirming,
                  palette: palette,
                ),
              ),
            ),

            // Guidance panel (step, alignment %, direction, ROI note).
            Positioned(
              left: panelLeft,
              width: panelWidth,
              top: padding.top + 60,
              bottom: padding.bottom + 12,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: panelWidth,
                      child: _GuidancePanel(
                        top: top,
                        aligned: widget.aligned,
                        alignmentScore: widget.alignmentScore,
                        stability: widget.stability,
                        confirming: confirming,
                        tiltError: widget.tiltError,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // iOS-style shutter on the right rail.
            Positioned(
              left: railX - 38,
              top: size.height / 2 - 38,
              width: 76,
              height: 76,
              child: _ShutterButton(
                holdProgress: widget.aligned ? widget.holdProgress : 0.0,
                aligned: widget.aligned,
                confirming: confirming,
                palette: palette,
                ambient: _ambient,
                semanticsLabel: l10n.scanTakePhoto,
                onTap: widget.onManualCapture,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Guide ────────────────────────────────────────────────────────────────────

/// Builds the guide outline starting at the top-centre and running clockwise,
/// so the hold-progress trace always begins at 12 o'clock.
Path _guidePath(RRect g) {
  final r = g.tlRadiusX;
  final rad = Radius.circular(r);
  return Path()
    ..moveTo(g.center.dx, g.top)
    ..lineTo(g.right - r, g.top)
    ..arcToPoint(Offset(g.right, g.top + r), radius: rad)
    ..lineTo(g.right, g.bottom - r)
    ..arcToPoint(Offset(g.right - r, g.bottom), radius: rad)
    ..lineTo(g.left + r, g.bottom)
    ..arcToPoint(Offset(g.left, g.bottom - r), radius: rad)
    ..lineTo(g.left, g.top + r)
    ..arcToPoint(Offset(g.left + r, g.top), radius: rad)
    ..close();
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.guide,
    required this.palette,
    required this.ambient,
    required this.align,
    required this.holdProgress,
    required this.confirming,
  }) : super(repaint: Listenable.merge([ambient, align]));

  final RRect guide;
  final ScanChromePalette palette;
  final Animation<double> ambient;
  final Animation<double> align;
  final double holdProgress;
  final bool confirming;

  @override
  void paint(Canvas canvas, Size size) {
    final alignT = Curves.easeOut.transform(align.value.clamp(0.0, 1.0));
    final outline = _guidePath(guide);

    // Gently dim everything outside the region of interest.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(guide),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.30),
    );

    if (confirming) {
      canvas.drawRRect(
        guide,
        Paint()..color = palette.accent.withValues(alpha: 0.12),
      );
    }

    final bounds = guide.outerRect.inflate(8);
    final Shader? gradientShader = palette.premium
        ? SweepGradient(
            colors: [...palette.gradient, palette.gradient.first],
            transform: GradientRotation(ambient.value * 2 * math.pi),
          ).createShader(bounds)
        : null;

    // Premium: soft bloom under the outline that strengthens when aligned.
    if (palette.premium) {
      canvas.drawPath(
        outline,
        Paint()
          ..shader = gradientShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..color = Colors.white
              .withValues(alpha: 0.30 + 0.35 * alignT + (confirming ? 0.2 : 0)),
      );
    }

    // Crisp outline. Default: neutral white that turns to the theme accent
    // once aligned. Premium: flowing theme gradient.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = palette.premium ? 2.2 : 2.0
      ..strokeJoin = StrokeJoin.round;
    if (gradientShader != null) {
      line.shader = gradientShader;
    } else {
      line.color = Color.lerp(
        Colors.white.withValues(alpha: 0.88),
        palette.accent,
        confirming ? 1.0 : alignT,
      )!;
    }
    canvas.drawPath(outline, line);

    // Mid-edge ticks (inward), like a camera framing reticle.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const len = 8.0;
    final c = guide.center;
    canvas.drawLine(Offset(c.dx, guide.bottom), Offset(c.dx, guide.bottom - len),
        tick);
    canvas.drawLine(
        Offset(guide.left, c.dy), Offset(guide.left + len, c.dy), tick);
    canvas.drawLine(
        Offset(guide.right, c.dy), Offset(guide.right - len, c.dy), tick);

    // Hold-steady progress traced along the outline from 12 o'clock.
    final p = holdProgress.clamp(0.0, 1.0);
    if (p > 0.001 && !confirming) {
      final metric = outline.computeMetrics().first;
      final trace = metric.extractPath(0, metric.length * p);
      final tracePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      if (gradientShader != null) {
        tracePaint.shader = gradientShader;
      } else {
        tracePaint.color = palette.accent;
      }
      canvas.drawPath(trace, tracePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.guide != guide ||
      old.palette != palette ||
      old.holdProgress != holdProgress ||
      old.confirming != confirming;
}

class _ConfirmBadge extends StatelessWidget {
  const _ConfirmBadge({required this.palette});
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.premium ? null : palette.accent,
        gradient: palette.premium
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: palette.gradient,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: palette.premium ? 0.55 : 0.3),
            blurRadius: palette.premium ? 24 : 12,
          ),
        ],
      ),
      child: Icon(Icons.check_rounded, size: 34, color: palette.onAccent),
    );
  }
}

// ── Status tag ("Food detected") ─────────────────────────────────────────────

class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.detected,
    required this.palette,
    required this.label,
  });

  final bool detected;
  final ScanChromePalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: detected
              ? palette.accent.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.16),
        ),
        boxShadow: detected && palette.premium
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.45),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: detected
                  ? palette.accent
                  : Colors.white.withValues(alpha: 0.5),
              boxShadow: detected
                  ? [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 7),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              label,
              key: ValueKey(label),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tilt gauge ───────────────────────────────────────────────────────────────

/// Vertical precision level. The indicator shows where the camera points
/// relative to the target (centre line) and snaps onto it when level.
class _TiltGauge extends StatelessWidget {
  const _TiltGauge({
    required this.value,
    required this.aligned,
    required this.palette,
  });

  /// −1…1, positive = camera above target.
  final double value;
  final bool aligned;
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: aligned ? 0.0 : value),
      duration: Duration(milliseconds: aligned ? 300 : 140),
      curve: aligned ? Curves.easeOutBack : Curves.easeOut,
      builder: (context, v, _) => CustomPaint(
        size: Size.infinite,
        painter: _GaugePainter(value: v, aligned: aligned, palette: palette),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.aligned,
    required this.palette,
  });

  final double value;
  final bool aligned;
  final ScanChromePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final half = size.height / 2 - 4;

    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx, 4), Offset(cx, size.height - 4), track);

    final tick = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 8; i++) {
      final y = 4 + (size.height - 8) * i / 8;
      final major = i == 0 || i == 8;
      final l = major ? 4.5 : 2.5;
      canvas.drawLine(Offset(cx - l, y), Offset(cx + l, y), tick);
    }

    final accent = aligned ? palette.accent : Colors.white;
    final y = cy - value.clamp(-1.2, 1.2) * half;

    // Distance from target, so the needed correction reads at a glance.
    if ((y - cy).abs() > 1) {
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }

    // Target line.
    canvas.drawLine(
      Offset(cx - 10, cy),
      Offset(cx + 10, cy),
      Paint()
        ..color = aligned ? palette.accent : Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Indicator.
    final indicator = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: 16, height: 5),
      const Radius.circular(2.5),
    );
    if (aligned && palette.premium) {
      canvas.drawRRect(
        indicator.inflate(2),
        Paint()
          ..color = palette.accent.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(indicator, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.aligned != aligned || old.palette != palette;
}

// ── Guidance panel ───────────────────────────────────────────────────────────

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({
    required this.top,
    required this.aligned,
    required this.alignmentScore,
    required this.stability,
    required this.confirming,
    required this.tiltError,
    required this.palette,
  });

  final bool top;
  final bool aligned;
  final double alignmentScore;
  final double stability;
  final bool confirming;
  final double tiltError;
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = (alignmentScore.clamp(0.0, 1.0) * 100).round();
    final level = aligned || confirming;

    final IconData directionIcon;
    final String direction;
    if (confirming) {
      directionIcon = Icons.check_circle_rounded;
      direction = l10n.scanCaptured;
    } else if (aligned) {
      directionIcon = Icons.center_focus_strong_rounded;
      direction =
          stability >= 0.35 ? l10n.scanHoldSteady : l10n.scanAlmostThere;
    } else if (top) {
      directionIcon = Icons.arrow_downward_rounded;
      direction = l10n.scanAimStraightDown;
    } else if (tiltError < 0) {
      directionIcon = Icons.arrow_upward_rounded;
      direction = l10n.scanTiltUp;
    } else {
      directionIcon = Icons.arrow_downward_rounded;
      direction = l10n.scanTiltDown;
    }

    final percentStyle = TextStyle(
      color: level && !palette.premium ? palette.accent : Colors.white,
      fontSize: 34,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    Widget percentText = Text('$percent%', style: percentStyle);
    if (level && palette.premium) {
      percentText = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) =>
            LinearGradient(colors: palette.gradient).createShader(rect),
        child: percentText,
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepSegmented(topActive: top, palette: palette),
        const SizedBox(height: 16),
        percentText,
        const SizedBox(height: 4),
        Text(
          l10n.scanAlignment.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Row(
            key: ValueKey(direction),
            children: [
              Icon(
                directionIcon,
                size: 17,
                color: level ? palette.accent : Colors.white,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  direction,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          top ? l10n.scanTopHint : l10n.scanSideHint,
          maxLines: 3,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
        const SizedBox(height: 9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 14,
                height: 12,
                child: CustomPaint(
                  painter: _GuideGlyphPainter(
                    isTop: top,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                top ? l10n.scanCircleInstruction : l10n.scanFrameInstruction,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return _GlassPanel(palette: palette, child: body);
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.palette, required this.child});
  final ScanChromePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(22));
    if (!palette.premium) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.46),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: child,
      );
    }
    // Premium: frosted glass with a gradient hairline and a soft accent glow.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.gradient.first.withValues(alpha: 0.65),
            Colors.white.withValues(alpha: 0.08),
            palette.gradient.last.withValues(alpha: 0.55),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.22),
            blurRadius: 26,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(21)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 11, 11, 13),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      palette.accent.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0.52),
                    ),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepSegmented extends StatelessWidget {
  const _StepSegmented({required this.topActive, required this.palette});
  final bool topActive;
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const segment = 34.0;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SizedBox(
        height: segment * 2,
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                alignment:
                    topActive ? Alignment.topCenter : Alignment.bottomCenter,
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                child: FractionallySizedBox(
                  heightFactor: 0.5,
                  widthFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: palette.premium
                          ? null
                          : Colors.white.withValues(alpha: 0.18),
                      gradient: palette.premium
                          ? LinearGradient(
                              colors: [
                                palette.gradient.first.withValues(alpha: 0.55),
                                palette.gradient.last.withValues(alpha: 0.40),
                              ],
                            )
                          : null,
                      boxShadow: palette.premium
                          ? [
                              BoxShadow(
                                color: palette.accent.withValues(alpha: 0.35),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _segmentRow(
                  isTop: true,
                  label: l10n.scanTopView,
                  active: topActive,
                  done: !topActive,
                  height: segment,
                ),
                _segmentRow(
                  isTop: false,
                  label: l10n.scanSideView,
                  active: !topActive,
                  done: false,
                  height: segment,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segmentRow({
    required bool isTop,
    required String label,
    required bool active,
    required bool done,
    required double height,
  }) {
    final fg = active ? Colors.white : Colors.white.withValues(alpha: 0.6);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 12,
              child: CustomPaint(
                painter: _GuideGlyphPainter(isTop: isTop, color: fg),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (done)
              Icon(Icons.check_rounded, size: 15, color: palette.accent),
          ],
        ),
      ),
    );
  }
}

/// Tiny glyph of the step's guide shape: circle (top) / rounded rect (side).
class _GuideGlyphPainter extends CustomPainter {
  _GuideGlyphPainter({required this.isTop, required this.color});
  final bool isTop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final c = size.center(Offset.zero);
    if (isTop) {
      canvas.drawCircle(c, math.min(size.width, size.height) / 2 - 0.75, paint);
    } else {
      final w = size.width - 1.5;
      final h = w * ScanGuideGeometry.sideHeightFactor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: w, height: h),
          Radius.circular(h * 0.3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuideGlyphPainter old) =>
      old.isTop != isTop || old.color != color;
}

// ── Shutter ──────────────────────────────────────────────────────────────────

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.holdProgress,
    required this.aligned,
    required this.confirming,
    required this.palette,
    required this.ambient,
    required this.semanticsLabel,
    required this.onTap,
  });

  final double holdProgress;
  final bool aligned;
  final bool confirming;
  final ScanChromePalette palette;
  final Animation<double> ambient;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: confirming ? null : onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ShutterRingPainter(
                    progress: holdProgress,
                    aligned: aligned,
                    palette: palette,
                    ambient: ambient,
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: confirming ? 50 : 60,
              height: confirming ? 50 : 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: AnimatedOpacity(
                opacity: confirming ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                child: const Icon(
                  Icons.check_rounded,
                  size: 26,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterRingPainter extends CustomPainter {
  _ShutterRingPainter({
    required this.progress,
    required this.aligned,
    required this.palette,
    required this.ambient,
  }) : super(repaint: ambient);

  final double progress;
  final bool aligned;
  final ScanChromePalette palette;
  final Animation<double> ambient;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    final Shader? gradient = palette.premium
        ? SweepGradient(
            colors: [...palette.gradient, palette.gradient.first],
            transform: GradientRotation(ambient.value * 2 * math.pi),
          ).createShader(rect)
        : null;

    if (palette.premium) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = gradient
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = Colors.white.withValues(alpha: aligned ? 0.75 : 0.4),
      );
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    if (gradient != null) {
      ring.shader = gradient;
    } else {
      ring.color = Colors.white;
    }
    canvas.drawCircle(c, r, ring);

    final p = progress.clamp(0.0, 1.0);
    if (p > 0.001) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * p,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = palette.premium ? Colors.white : palette.accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShutterRingPainter old) =>
      old.progress != progress ||
      old.aligned != aligned ||
      old.palette != palette;
}
