import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/scan_state.dart';
import '../theme/app_theme.dart';

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
    required this.stability,
    required this.holdProgress,
    required this.capturing,
    required this.scanMode,
    this.onManualCapture,
  });

  final ScanState scanState;

  /// Whether the device currently matches the active step's target orientation.
  final bool aligned;

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
    )..repeat(reverse: true);
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
    final frameColor = confirming
        ? AppTheme.green500
        : (widget.aligned ? AppTheme.green500 : Colors.white);

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
            child: _AlignmentFrame(
              pulse: _pulse,
              color: frameColor,
              isTop: top,
              aligned: widget.aligned,
              confirming: confirming,
            ),
          ),
        ),

        // Primary guidance + stability ring (bottom-center).
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: _GuidancePanel(
            scanState: widget.scanState,
            aligned: widget.aligned,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepPill(index: 1, label: 'Top View', active: topActive, done: !topActive),
        Container(
          width: 28,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: topActive ? Colors.white24 : AppTheme.green500,
        ),
        _StepPill(index: 2, label: 'Side View', active: !topActive, done: false),
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
    final Color bg = active
        ? context.primary400
        : (done ? AppTheme.green500 : Colors.black.withValues(alpha: 0.45));
    final Color fg = (active || done) ? Colors.white : Colors.white70;
    return Container(
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
                  const Icon(Icons.check_circle,
                      size: 64, color: AppTheme.green500)
                else if (!aligned)
                  Icon(
                    isTop ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.85),
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

    // Corner brackets.
    const len = 34.0;
    final bracket = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final corners = [
      (rect.topLeft, const Offset(1, 0), const Offset(0, 1)),
      (rect.topRight, const Offset(-1, 0), const Offset(0, 1)),
      (rect.bottomLeft, const Offset(1, 0), const Offset(0, -1)),
      (rect.bottomRight, const Offset(-1, 0), const Offset(0, -1)),
    ];
    for (final (corner, dx, dy) in corners) {
      canvas.drawLine(corner, corner + dx * len, bracket);
      canvas.drawLine(corner, corner + dy * len, bracket);
    }

    // Ghost guide: dashed plate circle (top) or horizon line (side).
    final ghost = Paint()
      ..color = color.withValues(alpha: 0.30)
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
    required this.holdProgress,
    required this.stability,
    required this.confirming,
    required this.scanMode,
    required this.onManualCapture,
  });
  final ScanState scanState;
  final bool aligned;
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
      return _isTop ? 'Aim straight down at the plate' : 'Tilt up to the side view';
    }
    return 'Hold steady…';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stability ring + center capture dot (tap = manual fallback).
        GestureDetector(
          onTap: confirming ? null : onManualCapture,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 76,
                  height: 76,
                  child: CircularProgressIndicator(
                    value: aligned ? holdProgress.clamp(0.0, 1.0) : null,
                    strokeWidth: 4,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(
                      aligned ? AppTheme.green500 : Colors.white54,
                    ),
                  ),
                ),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: aligned
                        ? AppTheme.green500.withValues(alpha: 0.9)
                        : Colors.white.withValues(alpha: 0.85),
                  ),
                  child: Icon(
                    confirming ? Icons.check : Icons.camera_alt,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Container(
            key: ValueKey(_primaryText),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              _primaryText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isTop
              ? 'Hold ~30 cm above • keep the whole plate framed'
              : 'Lower to plate level • keep food in the frame',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ],
    );
  }
}
