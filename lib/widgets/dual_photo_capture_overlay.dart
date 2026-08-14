import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_localizations.dart';
import '../core/scan_state.dart';
import '../theme/app_theme.dart';
import 'premium_theme_effects.dart';

/// Guided dual-photo capture overlay (landscape).
///
/// Drives the two-step capture flow — **Top View** then **Side View** — with a
/// real-time alignment frame, directional guidance ("Aim down" / "Tilt up"), a
/// "hold steady" stability ring, and a capture-confirmation flash. The auto
/// shutter is owned by the scan screen; this widget is pure presentation plus
/// an optional manual-capture fallback.
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
    this.onManualCapture,
  });

  final ScanState scanState;

  /// Whether the device currently matches the active step's target orientation.
  final bool aligned;

  /// Target-orientation alignment score in 0…1, shown as the restored tilt
  /// percentage slider (Top view / Side view aligned).
  final double alignmentScore;

  /// Live motion stability 0…1 (1 = perfectly still).
  final double stability;

  /// Progress 0…1 of the aligned+stable hold before the auto shutter fires.
  final double holdProgress;

  /// True during the brief capture-confirmation flash.
  final bool capturing;

  /// Native capability mode (e.g. monocular_scale, lidar_mesh).
  final String scanMode;

  /// Manual-capture fallback, invoked if the user taps the shutter.
  final VoidCallback? onManualCapture;

  bool get _isTopStep =>
      scanState == ScanState.waitingForTopView ||
      scanState == ScanState.captureTop;

  bool get _isCapturingTop => scanState == ScanState.captureTop;
  bool get _isCapturingSide => scanState == ScanState.captureSide;

  @override
  State<DualPhotoCaptureOverlay> createState() =>
      _DualPhotoCaptureOverlayState();
}

class _DualPhotoCaptureOverlayState extends State<DualPhotoCaptureOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant DualPhotoCaptureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate = TickerMode.valuesOf(context).enabled && !reduceMotion;
    if (shouldAnimate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!shouldAnimate && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = widget._isTopStep;
    final confirming = widget._isCapturingTop || widget._isCapturingSide;
    final visualTheme = context.visualTheme;
    final successColor =
        visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500;
    final idleFrameColor =
        visualTheme.premium ? visualTheme.primaryAccent : Colors.white;
    final frameColor = confirming
        ? successColor
        : (widget.aligned ? successColor : idleFrameColor);

    return Stack(
      children: [
        // Capture flash.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.capturing ? 0.35 : 0.0,
              duration: const Duration(milliseconds: 120),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),

        // Centre framing guide. Sized to nearly the full screen HEIGHT while
        // leaving room on the left/right (landscape) so the side panels never
        // cross the circle.
        LayoutBuilder(
          builder: (context, constraints) {
            final diameter = math.min(
              constraints.maxHeight * 0.94,
              constraints.maxWidth * 0.6,
            );
            return Center(
              child: IgnorePointer(
                child: _AlignmentFrame(
                  pulse: _pulse,
                  color: frameColor,
                  isTop: top,
                  aligned: widget.aligned,
                  confirming: confirming,
                  alignmentScore: widget.alignmentScore,
                  diameter: diameter,
                ),
              ),
            );
          },
        ),

        // Which photo is being taken — a Top / Side showcase pinned to the LEFT
        // so it never crosses the framing circle. SafeArea keeps it clear of the
        // notch / Dynamic Island in landscape (and on smaller models).
        Positioned.fill(
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IgnorePointer(
                child: _ViewShowcase(topActive: top),
              ),
            ),
          ),
        ),

        // Guidance + capture — a compact card on the RIGHT (was a bottom bar
        // that touched the circle). SafeArea keeps its text clear of the notch.
        Positioned.fill(
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerRight,
              child: _SideGuidance(
                scanState: widget.scanState,
                aligned: widget.aligned,
                alignmentScore: widget.alignmentScore,
                holdProgress: widget.holdProgress,
                stability: widget.stability,
                confirming: confirming,
                onManualCapture: widget.onManualCapture,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Step header ──────────────────────────────────────────────────────────────

class _ViewShowcase extends StatelessWidget {
  const _ViewShowcase({required this.topActive});
  final bool topActive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewCard(
            isTop: true, label: 'Top', active: topActive, done: !topActive),
        const SizedBox(height: 12),
        _ViewCard(
            isTop: false, label: 'Side', active: !topActive, done: false),
      ],
    );
  }
}

class _ViewCard extends StatelessWidget {
  const _ViewCard({
    required this.isTop,
    required this.label,
    required this.active,
    required this.done,
  });
  final bool isTop;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final visualTheme = context.visualTheme;
    final accent =
        visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500;
    final borderColor = done ? accent : (active ? Colors.white : Colors.white30);
    final fg = (active || done) ? Colors.white : Colors.white54;
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: active ? 0.55 : 0.32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: active ? 2 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CustomPaint(
              painter: _MiniShapePainter(isTop: isTop, color: fg),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
                color: fg, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle, size: 14, color: accent),
            ),
        ],
      ),
    );
  }
}

/// Mini diagram of the framing shape for each step: a full circle for the top
/// view (round plate) and a flat-bottom "D" for the side view (food resting on
/// a flat surface — no round plate from the side).
class _MiniShapePainter extends CustomPainter {
  _MiniShapePainter({required this.isTop, required this.color});
  final bool isTop;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (isTop) {
      canvas.drawCircle(center, r, paint);
    } else {
      _drawArch(canvas, center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniShapePainter old) =>
      old.isTop != isTop || old.color != color;
}

/// Shared side-view guide: half a circle on top over a straight-sided "cube"
/// (the corners go straight up from a flat bottom). From the side the food
/// rests on a flat surface, so this reads more truthfully than a full circle.
void _drawArch(Canvas canvas, Offset center, double r, Paint paint) {
  final path = Path()
    ..moveTo(center.dx - r, center.dy + r) // bottom-left
    ..lineTo(center.dx - r, center.dy) // straight up the left side
    ..arcTo(
      Rect.fromCircle(center: center, radius: r),
      math.pi,
      math.pi,
      false,
    ) // semicircle over the top to the right side
    ..lineTo(center.dx + r, center.dy + r) // straight down the right side
    ..close(); // flat bottom
  canvas.drawPath(path, paint);
}

// ── Alignment frame ──────────────────────────────────────────────────────────

class _AlignmentFrame extends StatelessWidget {
  const _AlignmentFrame({
    required this.pulse,
    required this.color,
    required this.isTop,
    required this.aligned,
    required this.confirming,
    required this.alignmentScore,
    required this.diameter,
  });
  final Animation<double> pulse;
  final Color color;
  final bool isTop;
  final bool aligned;
  final bool confirming;
  final double alignmentScore;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final scale = aligned ? 1.0 : 1.0 + pulse.value * 0.03;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(diameter),
                  painter: _FramePainter(
                    color: color,
                    progress: alignmentScore,
                    isTop: isTop,
                  ),
                ),
                if (confirming)
                  Icon(Icons.check_circle, size: 64, color: color)
                else if (!aligned)
                  // Directional tilt cue: which way to move the phone to reach
                  // this step's angle — down for the top view, up for the side
                  // view. It bobs with the pulse so it reads as motion.
                  Transform.translate(
                    offset: Offset(
                      0,
                      (isTop ? 1 : -1) * (diameter * 0.12 + pulse.value * 8),
                    ),
                    child: Icon(
                      isTop
                          ? Icons.keyboard_double_arrow_down_rounded
                          : Icons.keyboard_double_arrow_up_rounded,
                      size: diameter * 0.16,
                      color: color.withValues(alpha: 0.92),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter({
    required this.color,
    required this.progress,
    required this.isTop,
  });
  final Color color;
  final double progress;
  final bool isTop;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.46;

    // ONE framing shape. A faint full outline (visible even at 0% so the user
    // can aim) plus a single bright arc on the SAME circle that fills to a
    // complete ring at 100% = the tilt percentage. Circle for the top view;
    // for the side view an arch (a semicircle over a straight-sided "cube").
    final guide = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    if (isTop) {
      canvas.drawCircle(center, r, guide);
    } else {
      _drawArch(canvas, center, r, guide);
    }

    final progressPaint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );

    final tick = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final a in [0.0, math.pi / 2, math.pi, 3 * math.pi / 2]) {
      final outer =
          Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r);
      final inner = Offset(
          center.dx + math.cos(a) * (r - 9), center.dy + math.sin(a) * (r - 9));
      canvas.drawLine(inner, outer, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.color != color || old.progress != progress || old.isTop != isTop;
}

// ── Guidance + stability ─────────────────────────────────────────────────────

class _SideGuidance extends StatelessWidget {
  const _SideGuidance({
    required this.scanState,
    required this.aligned,
    required this.alignmentScore,
    required this.holdProgress,
    required this.stability,
    required this.confirming,
    required this.onManualCapture,
  });
  final ScanState scanState;
  final bool aligned;
  final double alignmentScore;
  final double holdProgress;
  final double stability;
  final bool confirming;
  final VoidCallback? onManualCapture;

  bool get _isTop =>
      scanState == ScanState.waitingForTopView ||
      scanState == ScanState.captureTop;

  String get _primaryText {
    if (confirming) return 'Captured';
    if (!aligned) {
      return _isTop ? 'Aim straight down' : 'Tilt up to the side';
    }
    return stability >= 0.35 ? 'Hold steady…' : 'Almost there';
  }

  @override
  Widget build(BuildContext context) {
    final score = alignmentScore.clamp(0.0, 1.0);
    final percent = (score * 100).round().clamp(0, 100);
    final visualTheme = context.visualTheme;
    final accentColor =
        visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: confirming ? null : onManualCapture,
                child: PremiumFocusRing(
                  enabled: visualTheme.premium,
                  animate: visualTheme.premium && !confirming,
                  radius: 34,
                  padding: const EdgeInsets.all(3),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(
                            value: aligned ? holdProgress.clamp(0.0, 1.0) : null,
                            strokeWidth: 4,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation(
                              aligned ? accentColor : Colors.white54,
                            ),
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withValues(
                                alpha: aligned ? 0.95 : 0.82),
                          ),
                          child: Icon(
                            confirming ? Icons.check : Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$percent%',
                style: TextStyle(
                  color: aligned ? accentColor : Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                _isTop ? 'Top view aligned' : 'Side view aligned',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 10),
              _TiltPercentBar(value: score, aligned: aligned),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _primaryText,
                  key: ValueKey(_primaryText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).scanCircleInstruction,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
      ),
    );
  }
}

class _TiltPercentBar extends StatelessWidget {
  const _TiltPercentBar({required this.value, required this.aligned});
  final double value;
  final bool aligned;

  @override
  Widget build(BuildContext context) {
    final visualTheme = context.visualTheme;
    final color = aligned
        ? (visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500)
        : context.primary400;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
