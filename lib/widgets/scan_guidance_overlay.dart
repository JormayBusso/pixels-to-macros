import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/scan_state.dart';
import '../theme/app_theme.dart';

/// Camera guidance overlay shown during the scan flow.
///
/// Renders a professional viewfinder, distance hint, animated prompts, and
/// a real-time tilt-progress arc while recording.
class ScanGuidanceOverlay extends StatefulWidget {
  const ScanGuidanceOverlay({
    super.key,
    required this.scanState,
    this.currentPitch = 0.0,
  });
  final ScanState scanState;

  /// Current device pitch in radians: -pi/2 = pointing straight down, 0 = horizontal.
  final double currentPitch;

  @override
  State<ScanGuidanceOverlay> createState() => _ScanGuidanceOverlayState();
}

class _ScanGuidanceOverlayState extends State<ScanGuidanceOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.scanState;

    return IgnorePointer(
      child: Stack(
        children: [
          // Viewfinder reticle
          if (state == ScanState.waitingForTopView ||
              state == ScanState.readyToRecord ||
              state == ScanState.alignTop ||
              state == ScanState.moveSide)
            Center(child: _Reticle(pulse: _pulse, state: state)),

          // Tilt progress arc (shown during recording)
          if (state == ScanState.recording)
            Center(
              child: _TiltProgressArc(
                pitch: widget.currentPitch,
                pulse: _pulse,
              ),
            ),

          // Top banner instruction
          Positioned(
            top: 60,
            left: 24,
            right: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _InstructionBanner(
                key: ValueKey(state),
                state: state,
              ),
            ),
          ),

          // Distance hint (bottom)
          if (state == ScanState.waitingForTopView ||
              state == ScanState.readyToRecord ||
              state == ScanState.alignTop)
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _pulse,
                child: const Text(
                  'Hold 30-40 cm above the plate',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),

          // Side-move arrow hint
          if (state == ScanState.moveSide)
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: _AnimatedArrow(pulse: _pulse),
            ),
        ],
      ),
    );
  }
}

// Professional viewfinder reticle

class _Reticle extends StatelessWidget {
  const _Reticle({required this.pulse, required this.state});
  final Animation<double> pulse;
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final color = state == ScanState.waitingForTopView ||
            state == ScanState.readyToRecord ||
            state == ScanState.alignTop
        ? context.primary400
        : AppTheme.amber500;

    return _AnimBuilder(
      listenable: pulse,
      builder: (_, __) {
        final scale = 1.0 + pulse.value * 0.04;
        return Transform.scale(
          scale: scale,
          child: CustomPaint(
            size: const Size(240, 240),
            painter: _ViewfinderPainter(color: color),
          ),
        );
      },
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Subtle outer ring
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(cx, cy), r, outerPaint);

    // Corner brackets
    const bracketLen = 32.0;
    const bracketOffset = 4.0;
    final bracketPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) {
      final ox = cx + dx * (r - bracketOffset);
      final oy = cy + dy * (r - bracketOffset);
      canvas.drawLine(Offset(ox, oy), Offset(ox - dx * bracketLen, oy), bracketPaint);
      canvas.drawLine(Offset(ox, oy), Offset(ox, oy - dy * bracketLen), bracketPaint);
    }

    // Inner dashed circle (plate guide)
    final dashPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dashCount = 24;
    const dashAngle = (2 * math.pi) / dashCount;
    const gapRatio = 0.4;
    final innerR = r * 0.5;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle * (1 - gapRatio);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
        startAngle, sweepAngle, false, dashPaint,
      );
    }

    // Centre ring + dot
    final centrePaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), 8, centrePaint);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = color.withValues(alpha: 0.8));

    // Tick marks at cardinal positions
    final tickPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final angle in [0.0, math.pi / 2, math.pi, 3 * math.pi / 2]) {
      canvas.drawLine(
        Offset(cx + math.cos(angle) * (r - 8), cy + math.sin(angle) * (r - 8)),
        Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.color != color;
}

// Tilt progress arc (shown while recording)

class _TiltProgressArc extends StatelessWidget {
  const _TiltProgressArc({required this.pitch, required this.pulse});
  final double pitch;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    const startAngle = -1.396; // -80 degrees
    const endAngle = -0.175;   // -10 degrees
    final progress = ((pitch - startAngle) / (endAngle - startAngle)).clamp(0.0, 1.0);
    final progressColor = Color.lerp(AppTheme.amber500, const Color(0xFF4CAF50), progress)!;

    return _AnimBuilder(
      listenable: pulse,
      builder: (_, __) {
        return CustomPaint(
          size: const Size(260, 260),
          painter: _TiltArcPainter(
            progress: progress,
            color: progressColor,
            pulseValue: pulse.value,
          ),
        );
      },
    );
  }
}

class _TiltArcPainter extends CustomPainter {
  _TiltArcPainter({required this.progress, required this.color, required this.pulseValue});
  final double progress;
  final Color color;
  final double pulseValue;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 4;

    // Background track
    const arcStart = 135 * math.pi / 180;
    const arcSweep = 270 * math.pi / 180;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      arcStart, arcSweep, false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      arcStart, arcSweep * progress, false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );

    // Knob
    final knobAngle = arcStart + arcSweep * progress;
    final kx = cx + math.cos(knobAngle) * r;
    final ky = cy + math.sin(knobAngle) * r;
    canvas.drawCircle(Offset(kx, ky), 4 + pulseValue * 3, Paint()..color = color.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(kx, ky), 5, Paint()..color = color);
    canvas.drawCircle(Offset(kx, ky), 2.5, Paint()..color = Colors.white);

    // Percentage text
    final pct = (progress * 100).round();
    final tp = TextPainter(
      text: TextSpan(
        text: '$pct%',
        style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 - 6));

    // Sub-label
    final lp = TextPainter(
      text: TextSpan(
        text: progress < 1.0 ? 'Tilt upright...' : 'Done!',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    lp.paint(canvas, Offset(cx - lp.width / 2, cy + tp.height / 2 - 4));
  }

  @override
  bool shouldRepaint(_TiltArcPainter old) => old.progress != progress || old.color != color;
}

// Instruction banner

class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner({super.key, required this.state});
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final (String text, IconData icon, Color bg) = switch (state) {
      ScanState.waitingForTopView => (
          'Point phone straight down at your food',
          Icons.phone_android,
          context.primary600,
        ),
      ScanState.readyToRecord => (
          'Centre the plate and press the button',
          Icons.crop_free,
          context.primary600,
        ),
      ScanState.recording => (
          'Slowly tilt your phone upright',
          Icons.videocam,
          AppTheme.amber600,
        ),
      ScanState.alignTop => (
          'Centre the plate in the viewfinder',
          Icons.crop_free,
          context.primary600,
        ),
      ScanState.captureTop => (
          'Capturing top view...',
          Icons.camera,
          context.primary500,
        ),
      ScanState.moveSide => (
          'Slowly tilt to a 45 degree side angle',
          Icons.rotate_90_degrees_cw,
          AppTheme.amber600,
        ),
      ScanState.captureSide => (
          'Capturing side view...',
          Icons.camera,
          AppTheme.amber500,
        ),
      ScanState.calculating => (
          'Building 3-D model...',
          Icons.auto_awesome,
          context.primary500,
        ),
      ScanState.done => (
          'Scan complete!',
          Icons.check_circle,
          context.primary600,
        ),
      _ => (
          state.label,
          Icons.error_outline,
          AppTheme.red500,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Animated side-move arrow

class _AnimatedArrow extends StatelessWidget {
  const _AnimatedArrow({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return _AnimBuilder(
      listenable: pulse,
      builder: (_, __) {
        final dx = pulse.value * 16 - 8;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: -math.pi / 6,
                child: const Icon(Icons.arrow_forward, size: 32, color: Colors.white70),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tilt to the side',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white70),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Convenience animated builder without a child parameter.
class _AnimBuilder extends AnimatedWidget {
  // ignore: unused_element_parameter
  const _AnimBuilder({super.key, required super.listenable, required this.builder});
  final Widget Function(BuildContext, Widget?) builder;

  @override
  Widget build(BuildContext context) => builder(context, null);
}
