import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/app_localizations.dart';
import 'dual_photo_capture_overlay.dart' show ScanChromePalette;

/// Processing card shown while the scan is reconstructed.
///
/// A wireframe food "dome" assembles from the plate up and then turns slowly,
/// framed by a thin indeterminate progress ring, with the pipeline stages
/// (Segmenting · Measuring · Building 3D model) underneath.
///   • Default themes: calm and minimal — neutral hairlines, no glow.
///   • Premium themes: theme-gradient mesh, a light sweep with depth scan
///     lines, gradient ring and a frosted-glass card.
///   • Reduced motion: static mesh; the ring shows stage progress instead.
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
  late final AnimationController _assemble;
  late final AnimationController _spin;
  late final AnimationController _ring;
  late final AnimationController _sweep;
  final List<Timer> _stageTimers = [];
  int _stage = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _assemble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    // Stages advance on a calm cadence; the last one stays active until the
    // result arrives (the view is removed then).
    _stageTimers
      ..add(Timer(const Duration(milliseconds: 1400), () => _advance(1)))
      ..add(Timer(const Duration(milliseconds: 3200), () => _advance(2)));
  }

  void _advance(int stage) {
    if (mounted && stage > _stage) setState(() => _stage = stage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    _reduceMotion = mq.disableAnimations || mq.accessibleNavigation;
    final premium = ScanChromePalette.of(context).premium;
    if (_reduceMotion) {
      _assemble.value = 1.0;
      _spin.stop();
      _ring.stop();
      _sweep.stop();
      return;
    }
    if (!_assemble.isAnimating && _assemble.value < 1.0) _assemble.forward();
    if (!_spin.isAnimating) _spin.repeat();
    if (!_ring.isAnimating) _ring.repeat();
    if (premium && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!premium && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    for (final t in _stageTimers) {
      t.cancel();
    }
    _assemble.dispose();
    _spin.dispose();
    _ring.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ScanChromePalette.of(context);
    final stages = [
      l10n.scanStageSegmenting,
      l10n.scanStageMeasuring,
      l10n.scanStageBuilding3d,
    ];
    final visualSize = math.min(widget.height * 0.5, 132.0);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: visualSize,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ProcessingPainter(
                  assemble: _assemble,
                  spin: _spin,
                  ring: _ring,
                  sweep: _sweep,
                  palette: palette,
                  reduceMotion: _reduceMotion,
                  stageProgress: (_stage + 1) / stages.length,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.label ?? l10n.scanStageBuilding3d,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),
          _StageRow(stages: stages, active: _stage, palette: palette),
        ],
      ),
    );

    const radius = BorderRadius.all(Radius.circular(24));
    if (!palette.premium) {
      return Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF141518),
          borderRadius: radius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: content,
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.gradient.first.withValues(alpha: 0.7),
            Colors.white.withValues(alpha: 0.06),
            palette.gradient.last.withValues(alpha: 0.6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.24),
            blurRadius: 32,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(23)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    palette.accent.withValues(alpha: 0.12),
                    const Color(0xE60E1015),
                  ),
                  const Color(0xF20A0B0F),
                ],
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stages,
    required this.active,
    required this.palette,
  });

  final List<String> stages;
  final int active;
  final ScanChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < stages.length; i++) {
      if (i > 0) {
        children.add(Text(
          '·',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 13,
          ),
        ));
      }
      final done = i < active;
      final current = i == active;
      Widget label = Text(
        stages[i],
        style: TextStyle(
          color: current
              ? (palette.premium ? Colors.white : palette.accent)
              : Colors.white.withValues(alpha: done ? 0.72 : 0.4),
          fontSize: 12,
          fontWeight: current ? FontWeight.w700 : FontWeight.w500,
        ),
      );
      if (current && palette.premium) {
        label = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) =>
              LinearGradient(colors: palette.gradient).createShader(rect),
          child: label,
        );
      }
      children.add(AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Row(
          key: ValueKey('$i-$done-$current'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (done) ...[
              Icon(Icons.check_rounded, size: 13, color: palette.accent),
              const SizedBox(width: 3),
            ],
            label,
          ],
        ),
      ));
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 7,
      runSpacing: 4,
      children: children,
    );
  }
}

class _ProcessingPainter extends CustomPainter {
  _ProcessingPainter({
    required this.assemble,
    required this.spin,
    required this.ring,
    required this.sweep,
    required this.palette,
    required this.reduceMotion,
    required this.stageProgress,
  }) : super(repaint: Listenable.merge([assemble, spin, ring, sweep]));

  final Animation<double> assemble;
  final Animation<double> spin;
  final Animation<double> ring;
  final Animation<double> sweep;
  final ScanChromePalette palette;
  final bool reduceMotion;
  final double stageProgress;

  static const int _rings = 4;
  static const int _segments = 12;
  static const double _viewTilt = 0.48;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 2;
    _paintRing(canvas, c, outer);
    _paintMesh(canvas, c, outer * 0.62);
  }

  void _paintRing(Canvas canvas, Offset c, double r) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final double start;
    final double sweepAngle;
    if (reduceMotion) {
      start = -math.pi / 2;
      sweepAngle = 2 * math.pi * stageProgress.clamp(0.0, 1.0);
    } else {
      final t = ring.value;
      start = -math.pi / 2 + t * 2 * math.pi;
      sweepAngle = 0.9 + 0.5 * math.sin(t * 2 * math.pi).abs();
    }

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = palette.premium ? 2.6 : 2;
    if (palette.premium) {
      final shader = SweepGradient(
        colors: [
          palette.gradient.first.withValues(alpha: 0.0),
          ...palette.gradient,
        ],
        transform: GradientRotation(start),
      ).createShader(rect);
      canvas.drawArc(
        rect,
        start,
        sweepAngle,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      arc.shader = shader;
    } else {
      arc.color = Colors.white.withValues(alpha: 0.85);
    }
    canvas.drawArc(rect, start, sweepAngle, false, arc);
  }

  /// Unit-dome vertex (ring 0 = base … ring _rings = apex).
  List<double> _vertex(int ringIndex, int segment) {
    if (ringIndex >= _rings) return const [0, 1, 0];
    final el = (ringIndex / _rings) * (math.pi / 2) * 0.92;
    final az = segment / _segments * 2 * math.pi;
    return [math.cos(el) * math.cos(az), math.sin(el), math.cos(el) * math.sin(az)];
  }

  void _paintMesh(Canvas canvas, Offset c, double radius) {
    final angle = reduceMotion ? 0.6 : spin.value * 2 * math.pi;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    final cosT = math.cos(_viewTilt);
    final sinT = math.sin(_viewTilt);
    final centre = c + Offset(0, radius * 0.38);

    // Project to screen; returns (point, depth 0 = back … 1 = front).
    (Offset, double) project(List<double> v) {
      final x = v[0] * cosA - v[2] * sinA;
      final z = v[0] * sinA + v[2] * cosA;
      final y = v[1] * 0.82;
      final yr = y * cosT - z * sinT;
      final zr = y * sinT + z * cosT;
      return (
        Offset(centre.dx + x * radius, centre.dy - yr * radius),
        ((zr + 1) / 2).clamp(0.0, 1.0),
      );
    }

    // Edges ordered bottom-up so the mesh "assembles" from the plate.
    final edges = <(List<double>, List<double>)>[];
    for (var r = 0; r < _rings; r++) {
      for (var s = 0; s < _segments; s++) {
        edges.add((_vertex(r, s), _vertex(r, s + 1)));
      }
      for (var s = 0; s < _segments; s++) {
        edges.add((_vertex(r, s), _vertex(r + 1, s)));
        if (r < _rings - 1) edges.add((_vertex(r, s), _vertex(r + 1, s + 1)));
      }
    }

    final build = Curves.easeOutCubic.transform(assemble.value);
    final visible = build * edges.length;

    // Plate ellipse.
    final plate = Rect.fromCenter(
      center: centre,
      width: radius * 2.5,
      height: radius * 2.5 * sinT,
    );
    canvas.drawOval(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.14),
    );

    final meshBounds = Rect.fromCircle(center: c, radius: radius * 1.3);
    final Shader? gradient = palette.premium
        ? LinearGradient(
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            colors: palette.gradient,
          ).createShader(meshBounds)
        : null;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < edges.length && i < visible; i++) {
      final (a, da) = project(edges[i].$1);
      final (b0, db) = project(edges[i].$2);
      final partial = (visible - i).clamp(0.0, 1.0);
      final b = Offset.lerp(a, b0, partial)!;
      final depth = (da + db) / 2;
      line
        ..strokeWidth = 0.8 + 0.5 * depth
        ..shader = gradient
        ..color = Colors.white.withValues(
          alpha: palette.premium
              ? 0.25 + 0.65 * depth
              : 0.12 + 0.48 * depth,
        );
      canvas.drawLine(a, b, line);
    }

    // Vertices on the front face.
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: palette.premium ? 0.85 : 0.6);
    final vertexCount = ((_rings * _segments) * build).floor();
    for (var i = 0; i < vertexCount; i++) {
      final (p, d) = project(_vertex(i ~/ _segments, i % _segments));
      if (d < 0.5) continue;
      canvas.drawCircle(p, 0.8 + 0.8 * d, dot);
    }

    // Premium: light sweep with trailing depth scan lines across the dome.
    if (palette.premium && !reduceMotion) {
      final top = centre.dy - radius * 0.95;
      final bottom = centre.dy + radius * 0.35;
      final y = top + (bottom - top) * Curves.easeInOut.transform(sweep.value);
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(
          centre.dx - radius * 1.3, top - 4, centre.dx + radius * 1.3, bottom + 4));
      canvas.drawRect(
        Rect.fromLTRB(centre.dx - radius * 1.2, y - 16, centre.dx + radius * 1.2,
            y + 16),
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              palette.accent.withValues(alpha: 0.0),
              palette.accent.withValues(alpha: 0.28),
              palette.accent.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTRB(0, y - 16, 1, y + 16)),
      );
      for (var k = 0; k < 3; k++) {
        final ly = y - k * 9.0;
        canvas.drawLine(
          Offset(centre.dx - radius * 1.05, ly),
          Offset(centre.dx + radius * 1.05, ly),
          Paint()
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.32 / (k + 1)),
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ProcessingPainter old) =>
      old.palette != palette ||
      old.reduceMotion != reduceMotion ||
      old.stageProgress != stageProgress;
}
