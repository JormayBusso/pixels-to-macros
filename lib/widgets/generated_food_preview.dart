import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scan_result.dart';

class GeneratedFoodPreview extends StatefulWidget {
  const GeneratedFoodPreview({
    super.key,
    required this.foods,
    this.isBuilding = false,
    this.height = 220,
    this.title = 'Generated 3D food preview',
  });

  final List<DetectedFood> foods;
  final bool isBuilding;
  final double height;
  final String title;

  @override
  State<GeneratedFoodPreview> createState() => _GeneratedFoodPreviewState();
}

class _GeneratedFoodPreviewState extends State<GeneratedFoodPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (widget.isBuilding) {
      _controller.repeat();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant GeneratedFoodPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBuilding && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isBuilding) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = widget.isBuilding
            ? Curves.easeInOutCubic.transform(_controller.value)
            : 1.0;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF111827), Color(0xFF172033), Color(0xFF0B111C)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GeneratedFoodPainter(
                    foods: widget.foods,
                    progress: progress,
                    isBuilding: widget.isBuilding,
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 12,
                right: 14,
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.view_in_ar,
                        size: 17,
                        color: Color(0xFF86EFAC),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!widget.isBuilding && widget.foods.isNotEmpty)
                      _PreviewBadge(label: '${widget.foods.length} item${widget.foods.length == 1 ? '' : 's'}'),
                  ],
                ),
              ),
              if (widget.isBuilding)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _BuildSteps(progress: progress),
                ),
            ],
          ),
        );
      },
    );
  }
}

double _unit(double value) => value.clamp(0.0, 1.0).toDouble();

class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BuildSteps extends StatelessWidget {
  const _BuildSteps({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    const steps = [
      (0.12, Icons.crop_free, 'Lock plate'),
      (0.34, Icons.blur_on, 'Trace food'),
      (0.58, Icons.grid_4x4, 'Build mesh'),
      (0.82, Icons.restaurant, 'Estimate weight'),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: progress >= steps[i].$1
                    ? const Color(0xFF86EFAC)
                    : Colors.white.withValues(alpha: 0.16),
              ),
            ),
          _StepPill(
            icon: steps[i].$2,
            label: steps[i].$3,
            active: progress >= steps[i].$1,
          ),
        ],
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  const _StepPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF86EFAC) : Colors.white38;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF22C55E).withValues(alpha: 0.20)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: active ? 0.7 : 0.35)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 58,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GeneratedFoodPainter extends CustomPainter {
  const _GeneratedFoodPainter({
    required this.foods,
    required this.progress,
    required this.isBuilding,
  });

  final List<DetectedFood> foods;
  final double progress;
  final bool isBuilding;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size);

    final center = Offset(size.width * 0.50, size.height * 0.60);
    final plateWidth = size.width * 0.70;
    final plateHeight = size.height * 0.34;

    final plateProgress = _unit((progress - 0.06) / 0.18);
    _drawPlate(canvas, center, plateWidth, plateHeight, plateProgress);

    final previewFoods = foods.isEmpty ? _placeholderFoods : foods;
    final visibleCount = math.min(previewFoods.length, 5);
    for (var i = 0; i < visibleCount; i++) {
      final food = previewFoods[i];
      final itemProgress = _unit((progress - 0.22 - i * 0.08) / 0.44);
      if (itemProgress <= 0) continue;
      final offset = _portionOffset(i, visibleCount, plateWidth, plateHeight);
      final volumeScale = (food.volumeCm3 / 180.0).clamp(0.72, 1.34).toDouble();
      final baseWidth = plateWidth * 0.20 * volumeScale;
      final baseHeight = plateHeight * 0.42 * volumeScale;
      final color = _colorForLabel(food.label);
      _drawFoodMound(
        canvas,
        center + offset,
        baseWidth,
        baseHeight,
        color,
        itemProgress,
      );
    }

    if (progress > 0.72) {
      _drawHighlights(canvas, size, _unit((progress - 0.72) / 0.24));
    }
  }

  void _drawBackdrop(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width + size.height; x += 28) {
      canvas.drawLine(
        Offset(x.toDouble(), size.height),
        Offset(x + size.height * 0.75, 0),
        gridPaint,
      );
    }
    for (var x = 0.0; x < size.width + size.height; x += 30) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height * 0.75, size.height),
        gridPaint,
      );
    }
  }

  void _drawPlate(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    double progress,
  ) {
    if (progress <= 0) return;
    final eased = Curves.easeOutCubic.transform(progress);
    final plateRect = Rect.fromCenter(
      center: center,
      width: width * eased,
      height: height * eased,
    );

    canvas.drawOval(
      plateRect.shift(const Offset(0, 14)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30 * eased)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawOval(
      plateRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAFC), Color(0xFFCBD5E1)],
        ).createShader(plateRect),
    );
    canvas.drawOval(
      plateRect.deflate(width * 0.055),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF64748B).withValues(alpha: 0.22 * eased),
    );
    canvas.drawOval(
      plateRect.deflate(width * 0.12),
      Paint()..color = Colors.white.withValues(alpha: 0.28 * eased),
    );
  }

  void _drawFoodMound(
    Canvas canvas,
    Offset center,
    double width,
    double height,
    Color color,
    double progress,
  ) {
    final eased = Curves.easeOutBack.transform(_unit(progress));
    final moundHeight = height * 0.78 * eased;

    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, height * 0.24),
        width: width * 0.92,
        height: height * 0.35,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final bodyRect = Rect.fromCenter(
      center: center.translate(0, -moundHeight * 0.18),
      width: width,
      height: height * 0.78,
    );
    final bodyPath = Path()
      ..moveTo(bodyRect.left, center.dy + height * 0.16)
      ..cubicTo(
        bodyRect.left + width * 0.08,
        center.dy - moundHeight * 0.68,
        bodyRect.left + width * 0.33,
        center.dy - moundHeight,
        center.dx,
        center.dy - moundHeight,
      )
      ..cubicTo(
        bodyRect.right - width * 0.33,
        center.dy - moundHeight,
        bodyRect.right - width * 0.08,
        center.dy - moundHeight * 0.68,
        bodyRect.right,
        center.dy + height * 0.16,
      )
      ..cubicTo(
        bodyRect.right - width * 0.18,
        center.dy + height * 0.38,
        bodyRect.left + width * 0.18,
        center.dy + height * 0.38,
        bodyRect.left,
        center.dy + height * 0.16,
      )
      ..close();
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.22)!
                .withValues(alpha: 0.96 * progress),
            color.withValues(alpha: 0.94 * progress),
            Color.lerp(color, Colors.black, 0.18)!
                .withValues(alpha: 0.92 * progress),
          ],
        ).createShader(bodyRect),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(0, height * 0.12),
        width: width * 0.94,
        height: height * 0.34,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.12 * progress),
    );

    final highlightRect = Rect.fromCenter(
      center: center.translate(-width * 0.15, -moundHeight * 0.32),
      width: width * 0.34,
      height: height * 0.14,
    );
    canvas.drawOval(
      highlightRect,
      Paint()..color = Colors.white.withValues(alpha: 0.20 * progress),
    );
  }

  void _drawHighlights(Canvas canvas, Size size, double progress) {
    final paint = Paint()
      ..color = const Color(0xFF86EFAC).withValues(alpha: 0.32 * progress)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * 0.50, size.height * 0.60);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (0.20 + i * 0.08) * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi * 0.88,
        math.pi * 0.34,
        false,
        paint,
      );
    }
  }

  Offset _portionOffset(int index, int count, double plateWidth, double plateHeight) {
    if (count == 1) return Offset.zero;
    const positions = [
      Offset(-0.18, -0.04),
      Offset(0.18, 0.02),
      Offset(0.00, -0.18),
      Offset(-0.04, 0.16),
      Offset(0.28, -0.13),
    ];
    final p = positions[index % positions.length];
    return Offset(p.dx * plateWidth, p.dy * plateHeight);
  }

  Color _colorForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('rice') || lower.contains('egg')) return const Color(0xFFFDE68A);
    if (lower.contains('bread') || lower.contains('pasta') || lower.contains('potato')) {
      return const Color(0xFFD97706);
    }
    if (lower.contains('chicken') || lower.contains('fish') || lower.contains('steak')) {
      return const Color(0xFFFCA5A5);
    }
    if (lower.contains('salad') || lower.contains('broccoli') || lower.contains('cucumber')) {
      return const Color(0xFF22C55E);
    }
    if (lower.contains('tomato') || lower.contains('apple') || lower.contains('berry')) {
      return const Color(0xFFEF4444);
    }
    if (lower.contains('banana') || lower.contains('corn')) return const Color(0xFFFACC15);
    const palette = [
      Color(0xFF38BDF8),
      Color(0xFFF97316),
      Color(0xFFA78BFA),
      Color(0xFF14B8A6),
      Color(0xFFFB7185),
    ];
    return palette[label.hashCode.abs() % palette.length];
  }

  List<DetectedFood> get _placeholderFoods => const [
        DetectedFood(
          label: 'plate mesh',
          volumeCm3: 150,
          caloriesMin: 0,
          caloriesMax: 0,
        ),
        DetectedFood(
          label: 'food surface',
          volumeCm3: 110,
          caloriesMin: 0,
          caloriesMax: 0,
        ),
        DetectedFood(
          label: 'depth layer',
          volumeCm3: 90,
          caloriesMin: 0,
          caloriesMax: 0,
        ),
      ];

  @override
  bool shouldRepaint(_GeneratedFoodPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.foods != foods ||
        oldDelegate.isBuilding != isBuilding;
  }
}