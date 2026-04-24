import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/scan_state.dart';
import '../theme/app_theme.dart';

/// Camera guidance overlay shown during the scan flow.
///
/// Renders a reticle, distance hint, and animated prompts that change
/// based on the current [ScanState].
class ScanGuidanceOverlay extends StatefulWidget {
  const ScanGuidanceOverlay({super.key, required this.scanState});
  final ScanState scanState;

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
          // ── Reticle (centre crosshair) ─────────────────────────────────
          if (state == ScanState.readyToRecord ||
              state == ScanState.alignTop ||
              state == ScanState.moveSide)
            Center(child: _Reticle(pulse: _pulse, state: state)),

          // ── Top banner instruction ─────────────────────────────────────
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

          // ── Distance hint (bottom) ─────────────────────────────────────
          if (state == ScanState.readyToRecord ||
              state == ScanState.alignTop)
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _pulse,
                child: const Text(
                  'Hold 30–40 cm above the plate',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),

          // ── Side-move arrow hint ───────────────────────────────────────
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

// ── Reticle ─────────────────────────────────────────────────────────────────

class _Reticle extends StatelessWidget {
  const _Reticle({required this.pulse, required this.state});
  final Animation<double> pulse;
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final color = state == ScanState.readyToRecord ||
            state == ScanState.alignTop
        ? AppTheme.green400
        : AppTheme.amber500;

    return _AnimBuilder(
      listenable: pulse,
      builder: (_, __) {
        final scale = 1.0 + pulse.value * 0.08;
        return Transform.scale(
          scale: scale,
          child: CustomPaint(
            size: const Size(200, 200),
            painter: _ReticlePainter(color: color),
          ),
        );
      },
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Outer circle
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Inner circle (plate guide)
    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), r * 0.5, innerPaint);

    // Corner brackets
    const bracketLen = 24.0;
    final bracketPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]) {
      final ox = cx + dx * r;
      final oy = cy + dy * r;
      canvas.drawLine(
        Offset(ox, oy),
        Offset(ox - dx * bracketLen, oy),
        bracketPaint,
      );
      canvas.drawLine(
        Offset(ox, oy),
        Offset(ox, oy - dy * bracketLen),
        bracketPaint,
      );
    }

    // Crosshair centre dot
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, cy), 4, dotPaint);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.color != color;
}

// ── Instruction banner ──────────────────────────────────────────────────────

class _InstructionBanner extends StatelessWidget {
  const _InstructionBanner({super.key, required this.state});
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final (String text, IconData icon, Color bg) = switch (state) {
      ScanState.readyToRecord => (
          'Centre the plate and press the button',
          Icons.crop_free,
          AppTheme.green600,
        ),
      ScanState.recording => (
          'Sweep slowly from above to side view',
          Icons.videocam,
          AppTheme.amber600,
        ),
      ScanState.alignTop => (
          'Centre the plate in the reticle',
          Icons.crop_free,
          AppTheme.green600,
        ),
      ScanState.captureTop => (
          'Capturing top view…',
          Icons.camera,
          AppTheme.green500,
        ),
      ScanState.moveSide => (
          'Slowly tilt to a 45° side angle',
          Icons.rotate_90_degrees_cw,
          AppTheme.amber600,
        ),
      ScanState.captureSide => (
          'Capturing side view…',
          Icons.camera,
          AppTheme.amber500,
        ),
      ScanState.calculating => (
          'Building 3-D model…',
          Icons.auto_awesome,
          AppTheme.green500,
        ),
      ScanState.done => (
          'Scan complete!',
          Icons.check_circle,
          AppTheme.green600,
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

// ── Animated side-move arrow ────────────────────────────────────────────────

class _AnimatedArrow extends StatelessWidget {
  const _AnimatedArrow({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return _AnimBuilder(
      listenable: pulse,
      builder: (_, __) {
        final dx = pulse.value * 16 - 8; // slides ±8px
        return Transform.translate(
          offset: Offset(dx, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: -math.pi / 6,
                child: const Icon(
                  Icons.arrow_forward,
                  size: 32,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tilt to the side',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
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
  const _AnimBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  final Widget Function(BuildContext, Widget?) builder;

  @override
  Widget build(BuildContext context) => builder(context, null);
}
