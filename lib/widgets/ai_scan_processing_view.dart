import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// AI-themed processing visualization shown while a scan is being reconstructed.
///
/// Replaces the previous "food on a plate" placeholder with an abstract
/// intelligence / computation visual: a softly pulsing gradient core, rotating
/// reconstruction arcs and orbiting particles. Theme-aware (uses the active
/// premium [AppVisualTheme.gradient]) and contained inside a rounded card so it
/// reads as "the scan is being computed", never as food imagery.
class AiScanProcessingView extends StatefulWidget {
  const AiScanProcessingView({
    super.key,
    this.height = 250,
    this.label,
  });

  final double height;
  final String? label;

  @override
  State<AiScanProcessingView> createState() => _AiScanProcessingViewState();
}

class _AiScanProcessingViewState extends State<AiScanProcessingView>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final colors = visual.gradient.length >= 3
        ? visual.gradient
        : [visual.primaryAccent, visual.secondaryAccent, visual.primaryAccent];

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.first.withValues(alpha: 0.32),
          width: 1.2,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1018), Color(0xFF121A2B), Color(0xFF090D15)],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_spin, _pulse]),
                builder: (context, _) => CustomPaint(
                  painter: _AiProcessingPainter(
                    colors: colors,
                    spin: _spin.value,
                    pulse: Curves.easeInOut.transform(_pulse.value),
                  ),
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(_pulse.value);
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.first.withValues(alpha: 0.55 + 0.25 * t),
                          colors.first.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 26 + 2 * t,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                widget.label ?? 'Reconstructing 3D model',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              _ProcessingDots(controller: _pulse, color: colors.last),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProcessingDots extends StatelessWidget {
  const _ProcessingDots({required this.controller, required this.color});

  final Animation<double> controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.value * 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final active = (phase.floor() % 3) == i;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: active ? 0.95 : 0.30),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _AiProcessingPainter extends CustomPainter {
  _AiProcessingPainter({
    required this.colors,
    required this.spin,
    required this.pulse,
  });

  final List<Color> colors;
  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height) / 2;
    final angle = spin * 2 * math.pi;

    // Soft pulsing core glow.
    final coreRadius = base * (0.7 + 0.08 * pulse);
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors.first.withValues(alpha: 0.22 + 0.10 * pulse),
            colors.first.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: coreRadius)),
    );

    // Rotating "scan sweep" beam — a soft conic wedge that reads as an active
    // sensor sweeping the reconstruction volume.
    final sweepRect = Rect.fromCircle(center: center, radius: base * 0.9);
    canvas.drawCircle(
      center,
      base * 0.9,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = SweepGradient(
          startAngle: angle,
          endAngle: angle + 2 * math.pi,
          colors: [
            colors.last.withValues(alpha: 0.0),
            colors.last.withValues(alpha: 0.0),
            colors[1 % colors.length].withValues(alpha: 0.10 + 0.08 * pulse),
            colors.first.withValues(alpha: 0.20 + 0.10 * pulse),
            colors.last.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.62, 0.80, 0.94, 1.0],
        ).createShader(sweepRect),
    );

    // Forming 3-D reconstruction point cloud: points distributed on a sphere
    // (golden-spiral), rotated about the vertical axis. Front points are larger
    // and brighter, back points dim — so it reads as a rotating volume being
    // assembled, not a flat spinner.
    _drawPointCloud(canvas, center, base * 0.60, angle);

    // Concentric reconstruction arcs rotating at different speeds/directions.
    final arcSpecs = <({double r, double sweep, int dir, double width})>[
      (r: base * 0.42, sweep: 2.1, dir: 1, width: 3.0),
      (r: base * 0.58, sweep: 1.5, dir: -1, width: 2.4),
      (r: base * 0.74, sweep: 2.6, dir: 1, width: 1.8),
    ];
    for (var i = 0; i < arcSpecs.length; i++) {
      final spec = arcSpecs[i];
      final color = colors[i % colors.length];
      final start = angle * spec.dir + i * 1.3;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = spec.width
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + spec.sweep,
          colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.95)],
        ).createShader(Rect.fromCircle(center: center, radius: spec.r));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: spec.r),
        start,
        spec.sweep,
        false,
        paint,
      );
    }

    // Orbiting particles with soft trailing glow.
    for (var i = 0; i < 6; i++) {
      final t = angle * (i.isEven ? 1 : -1) + i * (2 * math.pi / 6);
      final r = base * (0.46 + 0.30 * (i / 6));
      final p = center + Offset(math.cos(t) * r, math.sin(t) * r);
      final color = colors[i % colors.length];
      // Trailing streak.
      final trail = center +
          Offset(math.cos(t - 0.22 * (i.isEven ? 1 : -1)) * r,
              math.sin(t - 0.22 * (i.isEven ? 1 : -1)) * r);
      canvas.drawLine(
        trail,
        p,
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        p,
        2.6 + 1.4 * pulse,
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  /// Draws a rotating golden-spiral sphere of points, depth-shaded so it reads
  /// as a 3-D volume being reconstructed.
  void _drawPointCloud(Canvas canvas, Offset center, double radius, double a) {
    const count = 64;
    const goldenAngle = math.pi * (3.0 - 2.23606797749979); // π(3−√5)
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    for (var i = 0; i < count; i++) {
      final y = 1.0 - (i / (count - 1)) * 2.0; // 1 → −1
      final ring = math.sqrt(math.max(0.0, 1.0 - y * y));
      final theta = goldenAngle * i;
      final x = math.cos(theta) * ring;
      final z = math.sin(theta) * ring;
      // Rotate about the vertical (Y) axis.
      final xr = x * cosA - z * sinA;
      final zr = x * sinA + z * cosA;
      final sx = center.dx + xr * radius;
      final sy = center.dy + y * radius * 0.92;
      final depth = (zr + 1.0) / 2.0; // 0 (back) → 1 (front)
      final color = colors[i % colors.length];
      canvas.drawCircle(
        Offset(sx, sy),
        1.0 + 2.0 * depth,
        Paint()
          ..color = color.withValues(alpha: 0.18 + 0.62 * depth)
          ..maskFilter = depth > 0.6
              ? const MaskFilter.blur(BlurStyle.normal, 1.2)
              : null,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AiProcessingPainter old) =>
      old.spin != spin || old.pulse != pulse || old.colors != colors;
}
