import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    final frameColor = confirming
        ? successColor
        : (widget.aligned ? successColor : Colors.white);

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

        // Step header (top-center).
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: IgnorePointer(child: _StepHeader(topActive: top)),
        ),

        // Alignment frame + ghost guide.
        Center(
          child: IgnorePointer(
            child: PremiumMotionSurface(
              enabled: visualTheme.premium,
              borderRadius: BorderRadius.circular(top ? 130 : 44),
              padding: const EdgeInsets.all(5),
              borderWidth: widget.aligned ? 3.4 : 2.4,
              animate: true,
              child: _AlignmentFrame(
                pulse: _pulse,
                color: frameColor,
                isTop: top,
                aligned: widget.aligned,
                confirming: confirming,
              ),
            ),
          ),
        ),

        // Primary guidance + stability ring (bottom-center).
        Positioned(
          bottom: 20,
          left: 24,
          right: 24,
          child: _GuidancePanel(
            scanState: widget.scanState,
            aligned: widget.aligned,
            alignmentScore: widget.alignmentScore,
            holdProgress: widget.holdProgress,
            stability: widget.stability,
            confirming: confirming,
            scanMode: widget.scanMode,
            onManualCapture: widget.onManualCapture,
          ),
        ),
      ],
    );
  }
}

// ── Step header ──────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.topActive});
  final bool topActive;

  @override
  Widget build(BuildContext context) {
    final visualTheme = context.visualTheme;
    final successColor =
        visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepPill(
            index: 1, label: 'Top View', active: topActive, done: !topActive),
        Container(
          width: 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: topActive ? Colors.white24 : successColor,
        ),
        _StepPill(
            index: 2, label: 'Side View', active: !topActive, done: false),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.index,
    required this.label,
    required this.active,
    required this.done,
  });
  final int index;
  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final visualTheme = context.visualTheme;
    final successColor =
        visualTheme.premium ? visualTheme.primaryAccent : AppTheme.green500;
    final Color bg = active
        ? context.primary400
        : (done ? successColor : Colors.black.withValues(alpha: 0.45));
    final Color fg = (active || done) ? Colors.white : Colors.white70;
    return PremiumMotionSurface(
      enabled: visualTheme.premium && active,
      borderRadius: BorderRadius.circular(20),
      borderWidth: 2.8,
      animate: active,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.white : Colors.white24,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done)
              const Icon(Icons.check, size: 15, color: Colors.white)
            else
              Text('$index',
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ── Alignment frame ──────────────────────────────────────────────────────────

class _AlignmentFrame extends StatelessWidget {
  const _AlignmentFrame({
    required this.pulse,
    required this.color,
    required this.isTop,
    required this.aligned,
    required this.confirming,
  });
  final Animation<double> pulse;
  final Color color;
  final bool isTop;
  final bool aligned;
  final bool confirming;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final scale = aligned ? 1.0 : 1.0 + pulse.value * 0.03;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 230,
            height: 230,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(230, 230),
                  painter: _FramePainter(color: color, isTop: isTop),
                ),
                if (confirming)
                  Icon(Icons.check_circle, size: 64, color: color)
                else if (!aligned)
                  Icon(
                    isTop ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 48,
                    color: color.withValues(alpha: 0.88),
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
  _FramePainter({required this.color, required this.isTop});
  final Color color;
  final bool isTop;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final guide = Paint()
      ..color = color.withValues(alpha: 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (isTop) {
      canvas.drawCircle(Offset(cx, cy), size.width * 0.43, guide);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.deflate(18),
          const Radius.circular(38),
        ),
        guide,
      );
    }

    // Ghost guide: dashed plate circle (top) or horizon line (side).
    final ghost = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (isTop) {
      _drawDashedCircle(canvas, Offset(cx, cy), size.width * 0.34, ghost);
    } else {
      _drawDashedLine(
          canvas, Offset(28, cy), Offset(size.width - 28, cy), ghost);
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    const dashes = 28;
    const sweep = (2 * math.pi) / dashes;
    for (var i = 0; i < dashes; i += 2) {
      final start = i * sweep;
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), start, sweep, false, p);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 8.0;
    const gap = 6.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.color != color || old.isTop != isTop;
}

// ── Guidance + stability ─────────────────────────────────────────────────────

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({
    required this.scanState,
    required this.aligned,
    required this.alignmentScore,
    required this.holdProgress,
    required this.stability,
    required this.confirming,
    required this.scanMode,
    required this.onManualCapture,
  });
  final ScanState scanState;
  final bool aligned;
  final double alignmentScore;
  final double holdProgress;
  final double stability;
  final bool confirming;
  final String scanMode;
  final VoidCallback? onManualCapture;

  bool get _isTop =>
      scanState == ScanState.waitingForTopView ||
      scanState == ScanState.captureTop;

  String get _primaryText {
    if (confirming) return 'Captured';
    if (!aligned) {
      return _isTop
          ? 'Aim straight down at the plate'
          : 'Tilt up to the side view';
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: PremiumMotionSurface(
          enabled: visualTheme.premium,
          borderRadius: BorderRadius.circular(22),
          borderWidth: 3.0,
          animate: aligned && !confirming,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: confirming ? null : onManualCapture,
                  child: PremiumFocusRing(
                    enabled: visualTheme.premium,
                    animate: visualTheme.premium && !confirming,
                    radius: 36,
                    padding: const EdgeInsets.all(3),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              value:
                                  aligned ? holdProgress.clamp(0.0, 1.0) : null,
                              strokeWidth: 4,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(
                                aligned ? accentColor : Colors.white54,
                              ),
                            ),
                          ),
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: aligned
                                  ? accentColor.withValues(alpha: 0.92)
                                  : Colors.white.withValues(alpha: 0.88),
                            ),
                            child: Icon(
                              confirming ? Icons.check : Icons.camera_alt,
                              color: Colors.black87,
                              size: 21,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                _primaryText,
                                key: ValueKey(_primaryText),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_isTop ? 'Top view' : 'Side view'}: $percent% aligned',
                            style: TextStyle(
                              color: aligned ? accentColor : Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _TiltPercentBar(value: score, aligned: aligned),
                      const SizedBox(height: 8),
                      Text(
                        _isTop
                            ? 'Frame the full food area from above'
                            : 'Keep the camera near plate level',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
