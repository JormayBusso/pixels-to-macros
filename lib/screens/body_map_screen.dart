import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrient_data.dart';
import '../models/user_preferences.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// 2D interactive body map — anatomy style.
///
/// Shows a greyed-out human silhouette with body regions colored directly
/// on the figure (no emojis).  Text labels with lines point to each area.
class BodyMapScreen extends ConsumerWidget {
  const BodyMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(dailyIntakeProvider);
    final prefs = ref.watch(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final totals = intake.nutrientTotals;

    final regions = _buildRegions(totals, isMale);

    return Scaffold(
      appBar: AppBar(title: const Text('Body Map')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          // The body image is centered at 60% width, 82% height
          final imgW = w * 0.60;
          final imgH = h * 0.82;
          final imgLeft = (w - imgW) / 2;
          final imgTop = (h - imgH) / 2;

          return Stack(
            children: [
              // ── Background anatomy image (greyscale) ──────────────
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    width: imgW,
                    height: imgH,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: Image.asset(
                        'assets/anatomy_body.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                left: imgLeft,
                top: imgTop,
                width: imgW,
                height: imgH,
                child: _AnatomyOverlay(
                  regions: regions,
                  onTapRegion: (region) => _showDetail(context, region),
                ),
              ),

              // ── Text labels with lines ────────────────────────────
              ...regions.map((r) {
                final sx = imgLeft + r.cx * imgW;
                final sy = imgTop + r.cy * imgH;
                final color = _scoreColor(r.score);
                // Labels on the left side if cx < 0.5, else right
                final isLeft = r.cx < 0.50;

                return Positioned(
                  left: isLeft ? 4 : (sx + 8),
                  top: sy - 10,
                  width: isLeft ? (sx - 16) : (w - sx - 16),
                  child: GestureDetector(
                    onTap: () => _showDetail(context, r),
                    child: CustomPaint(
                      painter: _LineLabelPainter(
                        color: color,
                        isLeft: isLeft,
                        label: r.label,
                      ),
                      size: Size(isLeft ? (sx - 16) : (w - sx - 16), 20),
                    ),
                  ),
                );
              }),

              // ── Legend ───────────────────────────────────────────
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _LegendDot(
                            color: Colors.red.shade700, label: 'Low / Over'),
                        _LegendDot(color: Colors.orange, label: 'Moderate'),
                        _LegendDot(
                            color: Colors.yellow.shade700, label: 'Good'),
                        _LegendDot(color: Colors.green, label: 'Great'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext context, _BodyRegion region) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CustomPaint(
                    painter: _RegionSwatchPainter(region: region),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        region.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${(region.score * 100).round()}% nourished',
                        style: TextStyle(
                          fontSize: 13,
                          color: _scoreColor(region.score),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              region.explanation,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.gray600, height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Key nutrients:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 6),
            ...region.nutrients.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(n.name,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.gray600)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: n.ratio.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                            valueColor:
                                AlwaysStoppedAnimation(_scoreColor(n.ratio)),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${(n.ratio * 100).round().clamp(0, 999)}%',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AnatomyOverlay extends StatelessWidget {
  const _AnatomyOverlay({required this.regions, required this.onTapRegion});

  final List<_BodyRegion> regions;
  final ValueChanged<_BodyRegion> onTapRegion;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.globalPosition);
        final hit = _hitTestRegion(regions, local, box.size);
        if (hit != null) onTapRegion(hit);
      },
      child: CustomPaint(
        painter: _AnatomyPainter(regions: regions),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AnatomyPainter extends CustomPainter {
  const _AnatomyPainter({required this.regions});

  final List<_BodyRegion> regions;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = [...regions]
      ..sort((a, b) => _paintLayer(a.shape).compareTo(_paintLayer(b.shape)));

    for (final region in ordered) {
      _drawRegion(canvas, size, region);
    }
  }

  @override
  bool shouldRepaint(_AnatomyPainter oldDelegate) =>
      oldDelegate.regions != regions;
}

class _RegionSwatchPainter extends CustomPainter {
  const _RegionSwatchPainter({required this.region});

  final _BodyRegion region;

  @override
  void paint(Canvas canvas, Size size) {
    final color = _scoreColor(region.score);
    final path = _regionPath(region.shape, size);
    final bounds = path.getBounds();
    if (bounds.isEmpty) return;

    final scale = 0.76 / (bounds.longestSide / size.shortestSide);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);
    _drawRegion(canvas, size, region, swatch: true, overrideColor: color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RegionSwatchPainter oldDelegate) =>
      oldDelegate.region != region;
}

_BodyRegion? _hitTestRegion(
  List<_BodyRegion> regions,
  Offset point,
  Size size,
) {
  final ordered = [...regions]
    ..sort((a, b) => _paintLayer(b.shape).compareTo(_paintLayer(a.shape)));

  for (final region in ordered) {
    final path = _regionPath(region.shape, size);
    if (_isStrokeRegion(region.shape)) {
      if (path.getBounds().inflate(22).contains(point)) return region;
    } else if (path.contains(point)) {
      return region;
    }
  }
  return null;
}

int _paintLayer(_RegionShape shape) {
  switch (shape) {
    case _RegionShape.skin:
      return 0;
    case _RegionShape.bones:
      return 1;
    case _RegionShape.muscles:
      return 2;
    case _RegionShape.blood:
      return 3;
    case _RegionShape.lungs:
    case _RegionShape.liver:
    case _RegionShape.gut:
      return 4;
    case _RegionShape.heart:
    case _RegionShape.eyes:
    case _RegionShape.brain:
    case _RegionShape.immune:
      return 5;
  }
}

bool _isStrokeRegion(_RegionShape shape) =>
    shape == _RegionShape.bones ||
    shape == _RegionShape.muscles ||
    shape == _RegionShape.blood;

void _drawRegion(
  Canvas canvas,
  Size size,
  _BodyRegion region, {
  bool swatch = false,
  Color? overrideColor,
}) {
  final color = overrideColor ?? _scoreColor(region.score);
  final path = _regionPath(region.shape, size);
  final glow = color.withValues(alpha: swatch ? 0.14 : 0.20);

  if (_isStrokeRegion(region.shape)) {
    final halo = Paint()
      ..color = glow
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * (swatch ? 0.075 : 0.034)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final stroke = Paint()
      ..color = color.withValues(alpha: swatch ? 0.92 : 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * (swatch ? 0.038 : 0.017)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, halo);
    canvas.drawPath(path, stroke);
    return;
  }

  final fill = Paint()
    ..color =
        color.withValues(alpha: region.shape == _RegionShape.skin ? 0.18 : 0.70)
    ..style = PaintingStyle.fill;
  final border = Paint()
    ..color = color.withValues(alpha: swatch ? 0.95 : 0.88)
    ..style = PaintingStyle.stroke
    ..strokeWidth = size.shortestSide * (swatch ? 0.018 : 0.005)
    ..strokeJoin = StrokeJoin.round;

  canvas.drawShadow(path, color.withValues(alpha: 0.18), swatch ? 2 : 5, false);
  canvas.drawPath(path, fill);
  canvas.drawPath(path, border);

  if (region.shape == _RegionShape.gut) {
    _drawGutDetail(canvas, size, color, swatch: swatch);
  }
}

Path _regionPath(_RegionShape shape, Size size) {
  switch (shape) {
    case _RegionShape.brain:
      return _brainPath(size);
    case _RegionShape.eyes:
      return _eyesPath(size);
    case _RegionShape.heart:
      return _heartPath(size);
    case _RegionShape.lungs:
      return _lungsPath(size);
    case _RegionShape.liver:
      return _liverPath(size);
    case _RegionShape.gut:
      return _gutPath(size);
    case _RegionShape.bones:
      return _bonesPath(size);
    case _RegionShape.muscles:
      return _musclesPath(size);
    case _RegionShape.skin:
      return _skinPath(size);
    case _RegionShape.blood:
      return _veinsPath(size);
    case _RegionShape.immune:
      return _immunePath(size);
  }
}

Offset _pt(Size size, double x, double y) =>
    Offset(size.width * x, size.height * y);

Rect _rect(Size size, double cx, double cy, double w, double h) =>
    Rect.fromCenter(
      center: _pt(size, cx, cy),
      width: size.width * w,
      height: size.height * h,
    );

Path _brainPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.42, size.height * 0.092);
  path.cubicTo(size.width * 0.39, size.height * 0.060, size.width * 0.44,
      size.height * 0.032, size.width * 0.49, size.height * 0.046);
  path.cubicTo(size.width * 0.52, size.height * 0.028, size.width * 0.60,
      size.height * 0.050, size.width * 0.58, size.height * 0.090);
  path.cubicTo(size.width * 0.62, size.height * 0.116, size.width * 0.57,
      size.height * 0.150, size.width * 0.51, size.height * 0.138);
  path.cubicTo(size.width * 0.47, size.height * 0.154, size.width * 0.39,
      size.height * 0.132, size.width * 0.42, size.height * 0.092);
  path.close();
  return path;
}

Path _eyesPath(Size size) {
  Path almond(Rect rect) {
    final path = Path();
    path.moveTo(rect.left, rect.center.dy);
    path.quadraticBezierTo(
        rect.center.dx, rect.top, rect.right, rect.center.dy);
    path.quadraticBezierTo(
        rect.center.dx, rect.bottom, rect.left, rect.center.dy);
    path.close();
    return path;
  }

  final path = Path();
  path.addPath(almond(_rect(size, 0.455, 0.136, 0.055, 0.024)), Offset.zero);
  path.addPath(almond(_rect(size, 0.545, 0.136, 0.055, 0.024)), Offset.zero);
  return path;
}

Path _heartPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.53, size.height * 0.345);
  path.cubicTo(size.width * 0.48, size.height * 0.315, size.width * 0.49,
      size.height * 0.270, size.width * 0.53, size.height * 0.285);
  path.cubicTo(size.width * 0.56, size.height * 0.255, size.width * 0.62,
      size.height * 0.286, size.width * 0.59, size.height * 0.330);
  path.cubicTo(size.width * 0.575, size.height * 0.354, size.width * 0.55,
      size.height * 0.370, size.width * 0.53, size.height * 0.392);
  path.cubicTo(size.width * 0.515, size.height * 0.374, size.width * 0.50,
      size.height * 0.360, size.width * 0.53, size.height * 0.345);
  path.close();
  return path;
}

Path _lungsPath(Size size) {
  final left = Path();
  left.moveTo(size.width * 0.485, size.height * 0.230);
  left.cubicTo(size.width * 0.410, size.height * 0.225, size.width * 0.355,
      size.height * 0.292, size.width * 0.372, size.height * 0.395);
  left.cubicTo(size.width * 0.385, size.height * 0.462, size.width * 0.465,
      size.height * 0.442, size.width * 0.488, size.height * 0.372);
  left.cubicTo(size.width * 0.505, size.height * 0.317, size.width * 0.502,
      size.height * 0.262, size.width * 0.485, size.height * 0.230);
  left.close();

  final right = Path();
  right.moveTo(size.width * 0.515, size.height * 0.230);
  right.cubicTo(size.width * 0.590, size.height * 0.225, size.width * 0.645,
      size.height * 0.292, size.width * 0.628, size.height * 0.395);
  right.cubicTo(size.width * 0.615, size.height * 0.462, size.width * 0.535,
      size.height * 0.442, size.width * 0.512, size.height * 0.372);
  right.cubicTo(size.width * 0.495, size.height * 0.317, size.width * 0.498,
      size.height * 0.262, size.width * 0.515, size.height * 0.230);
  right.close();

  final path = Path()
    ..addPath(left, Offset.zero)
    ..addPath(right, Offset.zero);
  return path;
}

Path _liverPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.392, size.height * 0.405);
  path.cubicTo(size.width * 0.420, size.height * 0.360, size.width * 0.548,
      size.height * 0.358, size.width * 0.603, size.height * 0.395);
  path.cubicTo(size.width * 0.570, size.height * 0.445, size.width * 0.478,
      size.height * 0.468, size.width * 0.384, size.height * 0.438);
  path.cubicTo(size.width * 0.365, size.height * 0.432, size.width * 0.370,
      size.height * 0.413, size.width * 0.392, size.height * 0.405);
  path.close();
  return path;
}

Path _gutPath(Size size) {
  return Path()
    ..addRRect(RRect.fromRectAndRadius(
      _rect(size, 0.50, 0.515, 0.190, 0.120),
      Radius.circular(size.shortestSide * 0.055),
    ));
}

void _drawGutDetail(Canvas canvas, Size size, Color color,
    {required bool swatch}) {
  final paint = Paint()
    ..color = color.withValues(alpha: 0.58)
    ..style = PaintingStyle.stroke
    ..strokeWidth = size.shortestSide * (swatch ? 0.015 : 0.006)
    ..strokeCap = StrokeCap.round;
  final path = Path();
  path.moveTo(size.width * 0.43, size.height * 0.500);
  path.cubicTo(size.width * 0.47, size.height * 0.470, size.width * 0.53,
      size.height * 0.470, size.width * 0.57, size.height * 0.500);
  path.cubicTo(size.width * 0.53, size.height * 0.525, size.width * 0.47,
      size.height * 0.525, size.width * 0.43, size.height * 0.550);
  path.cubicTo(size.width * 0.47, size.height * 0.575, size.width * 0.53,
      size.height * 0.575, size.width * 0.57, size.height * 0.550);
  canvas.drawPath(path, paint);
}

Path _bonesPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.50, size.height * 0.200);
  path.lineTo(size.width * 0.50, size.height * 0.675);
  path.moveTo(size.width * 0.435, size.height * 0.240);
  path.quadraticBezierTo(size.width * 0.50, size.height * 0.220,
      size.width * 0.565, size.height * 0.240);
  path.moveTo(size.width * 0.425, size.height * 0.675);
  path.quadraticBezierTo(size.width * 0.50, size.height * 0.705,
      size.width * 0.575, size.height * 0.675);
  path.moveTo(size.width * 0.455, size.height * 0.705);
  path.lineTo(size.width * 0.425, size.height * 0.880);
  path.moveTo(size.width * 0.545, size.height * 0.705);
  path.lineTo(size.width * 0.575, size.height * 0.880);
  path.moveTo(size.width * 0.395, size.height * 0.300);
  path.quadraticBezierTo(size.width * 0.330, size.height * 0.440,
      size.width * 0.340, size.height * 0.590);
  path.moveTo(size.width * 0.605, size.height * 0.300);
  path.quadraticBezierTo(size.width * 0.670, size.height * 0.440,
      size.width * 0.660, size.height * 0.590);
  return path;
}

Path _musclesPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.382, size.height * 0.285);
  path.cubicTo(size.width * 0.315, size.height * 0.365, size.width * 0.305,
      size.height * 0.520, size.width * 0.350, size.height * 0.650);
  path.moveTo(size.width * 0.618, size.height * 0.285);
  path.cubicTo(size.width * 0.685, size.height * 0.365, size.width * 0.695,
      size.height * 0.520, size.width * 0.650, size.height * 0.650);
  path.moveTo(size.width * 0.450, size.height * 0.438);
  path.quadraticBezierTo(size.width * 0.500, size.height * 0.470,
      size.width * 0.550, size.height * 0.438);
  path.moveTo(size.width * 0.435, size.height * 0.625);
  path.cubicTo(size.width * 0.390, size.height * 0.725, size.width * 0.395,
      size.height * 0.835, size.width * 0.430, size.height * 0.905);
  path.moveTo(size.width * 0.565, size.height * 0.625);
  path.cubicTo(size.width * 0.610, size.height * 0.725, size.width * 0.605,
      size.height * 0.835, size.width * 0.570, size.height * 0.905);
  return path;
}

Path _skinPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.50, size.height * 0.035);
  path.cubicTo(size.width * 0.60, size.height * 0.040, size.width * 0.63,
      size.height * 0.155, size.width * 0.565, size.height * 0.205);
  path.cubicTo(size.width * 0.690, size.height * 0.245, size.width * 0.728,
      size.height * 0.525, size.width * 0.652, size.height * 0.655);
  path.cubicTo(size.width * 0.605, size.height * 0.730, size.width * 0.620,
      size.height * 0.955, size.width * 0.555, size.height * 0.965);
  path.cubicTo(size.width * 0.520, size.height * 0.840, size.width * 0.515,
      size.height * 0.700, size.width * 0.500, size.height * 0.665);
  path.cubicTo(size.width * 0.485, size.height * 0.700, size.width * 0.480,
      size.height * 0.840, size.width * 0.445, size.height * 0.965);
  path.cubicTo(size.width * 0.380, size.height * 0.955, size.width * 0.395,
      size.height * 0.730, size.width * 0.348, size.height * 0.655);
  path.cubicTo(size.width * 0.272, size.height * 0.525, size.width * 0.310,
      size.height * 0.245, size.width * 0.435, size.height * 0.205);
  path.cubicTo(size.width * 0.370, size.height * 0.155, size.width * 0.400,
      size.height * 0.040, size.width * 0.50, size.height * 0.035);
  path.close();
  return path;
}

Path _veinsPath(Size size) {
  final path = Path();
  path.moveTo(size.width * 0.452, size.height * 0.575);
  path.cubicTo(size.width * 0.420, size.height * 0.650, size.width * 0.455,
      size.height * 0.715, size.width * 0.425, size.height * 0.795);
  path.cubicTo(size.width * 0.405, size.height * 0.845, size.width * 0.430,
      size.height * 0.890, size.width * 0.410, size.height * 0.940);
  path.moveTo(size.width * 0.548, size.height * 0.575);
  path.cubicTo(size.width * 0.580, size.height * 0.650, size.width * 0.545,
      size.height * 0.715, size.width * 0.575, size.height * 0.795);
  path.cubicTo(size.width * 0.595, size.height * 0.845, size.width * 0.570,
      size.height * 0.890, size.width * 0.590, size.height * 0.940);
  path.moveTo(size.width * 0.425, size.height * 0.740);
  path.lineTo(size.width * 0.390, size.height * 0.765);
  path.moveTo(size.width * 0.575, size.height * 0.740);
  path.lineTo(size.width * 0.610, size.height * 0.765);
  return path;
}

Path _immunePath(Size size) {
  final path = Path();
  for (final rect in [
    _rect(size, 0.470, 0.205, 0.035, 0.025),
    _rect(size, 0.530, 0.205, 0.035, 0.025),
    _rect(size, 0.388, 0.285, 0.040, 0.030),
    _rect(size, 0.612, 0.285, 0.040, 0.030),
    _rect(size, 0.442, 0.610, 0.038, 0.028),
    _rect(size, 0.558, 0.610, 0.038, 0.028),
  ]) {
    path.addOval(rect);
  }
  return path;
}

/// Draws a short horizontal line + label text.
/// [isLeft] — line goes right-to-left (label on left, line to right toward body).
class _LineLabelPainter extends CustomPainter {
  final Color color;
  final bool isLeft;
  final String label;

  _LineLabelPainter({
    required this.color,
    required this.isLeft,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final lineY = size.height / 2;
    if (isLeft) {
      // Line from right edge (body) toward the label text on the left
      canvas.drawLine(
          Offset(size.width, lineY), Offset(size.width - 20, lineY), paint);
    } else {
      // Line from left edge (body) toward label on the right
      canvas.drawLine(Offset(0, lineY), Offset(20, lineY), paint);
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: isLeft ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    );
    tp.layout(maxWidth: size.width - 24);

    final textX = isLeft ? (size.width - 24 - tp.width) : 24.0;
    tp.paint(canvas, Offset(textX, lineY - tp.height / 2));
  }

  @override
  bool shouldRepaint(_LineLabelPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.label != label;
}

Color _scoreColor(double score) {
  // Transitions: red (low) → orange → yellow → green (good)
  // then back to red if way over the daily dose (>1.6)
  if (score > 1.6) return const Color(0xFFB71C1C); // way over → deep red
  if (score >= 1.0) return const Color(0xFF4CAF50); // ≥100%  → green
  if (score >= 0.7) return const Color(0xFF9CCC65); // 70-99% → light green
  if (score >= 0.4) return const Color(0xFFFF9800); // 40-69% → orange
  return const Color(0xFFE53935); // <40%   → red
}

// ── Region definitions ───────────────────────────────────────────────────────

class _NutrientRatio {
  final String name;
  final double ratio;
  const _NutrientRatio(this.name, this.ratio);
}

enum _RegionShape {
  brain,
  eyes,
  heart,
  lungs,
  liver,
  gut,
  bones,
  muscles,
  skin,
  blood,
  immune,
}

class _BodyRegion {
  final String label;
  final _RegionShape shape;
  final double cx; // normalised x (0-1)
  final double cy; // normalised y (0-1)
  final double size;
  final double score; // 0-1 average of nutrient ratios
  final String explanation;
  final List<_NutrientRatio> nutrients;

  const _BodyRegion({
    required this.label,
    required this.shape,
    required this.cx,
    required this.cy,
    this.size = 48,
    required this.score,
    required this.explanation,
    required this.nutrients,
  });
}

List<_BodyRegion> _buildRegions(NutrientTotals t, bool isMale) {
  double r(double current, double drv) => drv > 0 ? (current / drv) : 0;

  final vitA = r(t.vitaminAUg,
      isMale ? NutrientDRV.vitaminAUg_male : NutrientDRV.vitaminAUg_female);
  final vitC = r(t.vitaminCMg,
      isMale ? NutrientDRV.vitaminCMg_male : NutrientDRV.vitaminCMg_female);
  final vitD = r(t.vitaminDUg, NutrientDRV.vitaminDUg);
  final vitE = r(t.vitaminEMg, NutrientDRV.vitaminEMg);
  final vitK = r(t.vitaminKUg,
      isMale ? NutrientDRV.vitaminKUg_male : NutrientDRV.vitaminKUg_female);
  final folate = r(t.folateMcg, NutrientDRV.folateMcg);
  final b12 = r(t.b12Mcg, NutrientDRV.b12Mcg);
  final calcium = r(t.calciumMg,
      isMale ? NutrientDRV.calciumMg_male : NutrientDRV.calciumMg_female);
  final iron =
      r(t.ironMg, isMale ? NutrientDRV.ironMg_male : NutrientDRV.ironMg_female);
  final mag = r(t.magnesiumMg,
      isMale ? NutrientDRV.magnesiumMg_male : NutrientDRV.magnesiumMg_female);
  final potassium = r(t.potassiumMg,
      isMale ? NutrientDRV.potassiumMg_male : NutrientDRV.potassiumMg_female);
  final zinc =
      r(t.zincMg, isMale ? NutrientDRV.zincMg_male : NutrientDRV.zincMg_female);
  final fiber = r(t.fiberG, NutrientDRV.fiberG);

  double avg(List<double> vals) =>
      vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

  return [
    _BodyRegion(
      label: 'Brain',
      shape: _RegionShape.brain,
      cx: 0.50,
      cy: 0.08,
      score: avg([b12, folate, iron]).clamp(0.0, 2.0),
      explanation:
          'B12 and folate support nerve function and cognitive health. Iron carries oxygen to the brain.',
      nutrients: [
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
        _NutrientRatio('Iron', iron),
      ],
    ),
    _BodyRegion(
      label: 'Eyes',
      shape: _RegionShape.eyes,
      cx: 0.38,
      cy: 0.12,
      size: 40,
      score: avg([vitA, vitC, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin A is essential for vision. Vitamin C and zinc protect against age-related macular degeneration.',
      nutrients: [
        _NutrientRatio('Vitamin A', vitA),
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Heart',
      shape: _RegionShape.heart,
      cx: 0.56,
      cy: 0.30,
      score: avg([potassium, mag, vitE]).clamp(0.0, 2.0),
      explanation:
          'Potassium regulates heartbeat. Magnesium relaxes blood vessels. Vitamin E prevents oxidative damage to cells.',
      nutrients: [
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Vitamin E', vitE),
      ],
    ),
    _BodyRegion(
      label: 'Lungs',
      shape: _RegionShape.lungs,
      cx: 0.44,
      cy: 0.30,
      size: 44,
      score: avg([vitC, vitE, vitA]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C protects lung tissue. Vitamin E and A are antioxidants that defend against inflammation.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin A', vitA),
      ],
    ),
    _BodyRegion(
      label: 'Liver',
      shape: _RegionShape.liver,
      cx: 0.40,
      cy: 0.40,
      size: 42,
      score: avg([vitE, vitK, b12]).clamp(0.0, 2.0),
      explanation:
          'The liver stores vitamins and detoxifies the body. Vitamin K is synthesised here and supports blood clotting.',
      nutrients: [
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Vitamin K', vitK),
        _NutrientRatio('B12', b12),
      ],
    ),
    _BodyRegion(
      label: 'Gut',
      shape: _RegionShape.gut,
      cx: 0.50,
      cy: 0.50,
      score: avg([fiber, mag, potassium]).clamp(0.0, 2.0),
      explanation:
          'Dietary fiber feeds healthy gut bacteria and aids digestion. Magnesium helps with muscle contractions in the intestines.',
      nutrients: [
        _NutrientRatio('Fiber', fiber),
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
      ],
    ),
    _BodyRegion(
      label: 'Bones',
      shape: _RegionShape.bones,
      cx: 0.60,
      cy: 0.60,
      score: avg([calcium, vitD, vitK]).clamp(0.0, 2.0),
      explanation:
          'Calcium builds bone density. Vitamin D helps absorb calcium. Vitamin K directs calcium to bones instead of arteries.',
      nutrients: [
        _NutrientRatio('Calcium', calcium),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Vitamin K', vitK),
      ],
    ),
    _BodyRegion(
      label: 'Muscles',
      shape: _RegionShape.muscles,
      cx: 0.32,
      cy: 0.55,
      score: avg([mag, potassium, calcium]).clamp(0.0, 2.0),
      explanation:
          'Magnesium and potassium prevent cramps and support muscle contraction. Calcium triggers muscle fibers.',
      nutrients: [
        _NutrientRatio('Magnesium', mag),
        _NutrientRatio('Potassium', potassium),
        _NutrientRatio('Calcium', calcium),
      ],
    ),
    _BodyRegion(
      label: 'Skin',
      shape: _RegionShape.skin,
      cx: 0.68,
      cy: 0.42,
      size: 40,
      score: avg([vitC, vitE, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C produces collagen for skin elasticity. Vitamin E protects against UV damage. Zinc helps wound healing.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin E', vitE),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
    _BodyRegion(
      label: 'Blood',
      shape: _RegionShape.blood,
      cx: 0.38,
      cy: 0.68,
      size: 40,
      score: avg([iron, b12, folate]).clamp(0.0, 2.0),
      explanation:
          'Iron is the core of haemoglobin. B12 and folate are needed to produce healthy red blood cells.',
      nutrients: [
        _NutrientRatio('Iron', iron),
        _NutrientRatio('B12', b12),
        _NutrientRatio('Folate', folate),
      ],
    ),
    _BodyRegion(
      label: 'Immune System',
      shape: _RegionShape.immune,
      cx: 0.62,
      cy: 0.20,
      size: 40,
      score: avg([vitC, vitD, zinc]).clamp(0.0, 2.0),
      explanation:
          'Vitamin C, D, and zinc are the big three for immune defence. They help white blood cells fight infections.',
      nutrients: [
        _NutrientRatio('Vitamin C', vitC),
        _NutrientRatio('Vitamin D', vitD),
        _NutrientRatio('Zinc', zinc),
      ],
    ),
  ];
}

// ── Legend dot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppTheme.gray600)),
      ],
    );
  }
}
