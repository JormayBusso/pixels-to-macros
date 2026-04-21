import 'package:flutter/material.dart';

import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';

// ── Public entry point ───────────────────────────────────────────────────────

/// Displays an animated mascot for the user's nutrition goal.
///
/// [progress]       — calories consumed / calorie goal  (0.0 – 1.0+)
/// [stressLevel]    — carbs consumed / carb limit       (0.0 – 1.0+)
/// [mascotOverride] — when non-auto, shows this mascot regardless of goalType.
class GoalMascotWidget extends StatelessWidget {
  final NutritionGoalType goalType;
  final double progress;
  final double stressLevel;
  final MascotType mascotOverride;

  const GoalMascotWidget({
    super.key,
    required this.goalType,
    required this.progress,
    this.stressLevel = 0,
    this.mascotOverride = MascotType.auto,
  });

  MascotType get _effectiveMascot {
    if (mascotOverride != MascotType.auto) return mascotOverride;
    switch (goalType) {
      case NutritionGoalType.muscleGrowth: return MascotType.gorilla;
      case NutritionGoalType.vegan:        return MascotType.plant;
      case NutritionGoalType.keto:         return MascotType.flame;
      case NutritionGoalType.weightLoss:   return MascotType.flame;
      case NutritionGoalType.diabetes:     return MascotType.pancreas;
      case NutritionGoalType.maintain:     return MascotType.plant;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_effectiveMascot) {
      case MascotType.gorilla:
        return _ImageMascot(
          stages: const _MascotStages.gorilla(),
          progress: progress,
        );
      case MascotType.plant:
        return _ImageMascot(
          stages: const _MascotStages.plant(),
          progress: progress,
        );
      case MascotType.flame:
        return _ImageMascot(
          stages: const _MascotStages.flame(),
          progress: progress,
        );
      case MascotType.pancreas:
        return _ImageMascot(
          stages: const _MascotStages.pancreas(),
          progress: stressLevel,
          invertStage: true,
        );
      case MascotType.auto:
        return _ImageMascot(
          stages: const _MascotStages.plant(),
          progress: progress,
        );
    }
  }
}

// ── Mascot stage data ────────────────────────────────────────────────────────

class _MascotStages {
  final List<String> imagePaths; // 4 entries: index 0 = earliest/worst stage
  final List<String> labels;
  final List<Color> bgColors;

  const _MascotStages({
    required this.imagePaths,
    required this.labels,
    required this.bgColors,
  });

  const _MascotStages.gorilla()
      : imagePaths = const [
          'assets/mascots/baby_gorilla.png',
          'assets/mascots/young_gorilla.png',
          'assets/mascots/normal_gorilla.png',
          'assets/mascots/strong_gorilla.png',
        ],
        labels = const [
          'Baby Gorilla 🐒',
          'Growing Strong 🦍',
          'Mighty Gorilla 🦍',
          'Champion! 🦍💪',
        ],
        bgColors = const [
          Color(0xFFDCFCE7),
          Color(0xFF86EFAC),
          Color(0xFF4ADE80),
          Color(0xFFFEF3C7),
        ];

  const _MascotStages.plant()
      : imagePaths = const [
          'assets/mascots/tiny_plant.png',
          'assets/mascots/regular_plant.png',
          'assets/mascots/small_tree.png',
          'assets/mascots/big_tree.png',
        ],
        labels = const [
          'Seedling 🌱',
          'Sprouting 🌿',
          'Growing Strong 🌳',
          'In Full Bloom 🌸',
        ],
        bgColors = const [
          Color(0xFFF0FDF4),
          Color(0xFFDCFCE7),
          Color(0xFFBBF7D0),
          Color(0xFF86EFAC),
        ];

  const _MascotStages.flame()
      : imagePaths = const [
          'assets/mascots/no_fat_burning.png',
          'assets/mascots/little_fat_burning.png',
          'assets/mascots/fat_burning.png',
          'assets/mascots/extreme_fat_burning.png',
        ],
        labels = const [
          'No Burn Yet',
          'Warming Up 🔥',
          'Fat Burning! 🔥🔥',
          'Extreme Burn! 🔥🔥🔥',
        ],
        bgColors = const [
          Color(0xFFFFF7ED),
          Color(0xFFFED7AA),
          Color(0xFFFB923C),
          Color(0xFFEA580C),
        ];

  const _MascotStages.pancreas()
      : imagePaths = const [
          'assets/mascots/unhealthy_pancreas.png',
          'assets/mascots/little_unhealthy_pancreas.png',
          'assets/mascots/healthy_pancreas.png',
          'assets/mascots/very_healthy_pancreas.png',
        ],
        labels = const [
          'Overloaded! ❌',
          'Under Stress ⚠️',
          'Healthy 🩺',
          'Perfect Control ✅',
        ],
        bgColors = const [
          Color(0xFFFEE2E2),
          Color(0xFFFEF3C7),
          Color(0xFFDCFCE7),
          Color(0xFFBBF7D0),
        ];
}

// ── Shared image mascot widget ────────────────────────────────────────────────

class _ImageMascot extends StatelessWidget {
  final _MascotStages stages;
  final double progress; // 0.0 – 1.0+
  /// When true, high progress = lower stage (e.g. pancreas: high stress → worse).
  final bool invertStage;

  const _ImageMascot({
    required this.stages,
    required this.progress,
    this.invertStage = false,
  });

  int get _stage {
    int s;
    if (progress >= 0.75) {
      s = 3;
    } else if (progress >= 0.50) {
      s = 2;
    } else if (progress >= 0.25) {
      s = 1;
    } else {
      s = 0;
    }
    return invertStage ? (3 - s) : s;
  }

  @override
  Widget build(BuildContext context) {
    final s = _stage;
    final bgColor = stages.bgColors[s];
    final isBest = s == 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: bgColor.withValues(alpha: 0.8),
              width: isBest ? 3 : 1.5,
            ),
            boxShadow: isBest
                ? [
                    BoxShadow(
                      color: bgColor.withValues(alpha: 0.6),
                      blurRadius: 16,
                      spreadRadius: 4,
                    )
                  ]
                : [],
          ),
          child: ClipOval(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Image.asset(
                stages.imagePaths[s],
                key: ValueKey(s),
                fit: BoxFit.contain,
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            stages.labels[s],
            key: ValueKey(s),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isBest
                  ? const Color(0xFF15803D) // green-700
                  : const Color(0xFF374151), // gray-700
            ),
          ),
        ),
      ],
    );
  }
}

  final double progress;
  const _GorillaMascot({required this.progress});

  int get _stage {
    if (progress >= 1.0) return 3;
    return (progress * 3).clamp(0, 2).floor();
  }

  @override
  Widget build(BuildContext context) {
    const emojis     = ['🐒', '🦍', '🦍', '🦍'];
    const stageLabel = ['Baby Gorilla', 'Growing Strong', 'Mighty Gorilla', 'Champion! 💪'];
    const sizes      = [52.0, 64.0, 78.0, 92.0];
    final bgColors   = [
      Colors.green.shade100,
      Colors.green.shade300,
      Colors.green.shade500,
      Colors.amber.shade300,
    ];
    final borderColors = [
      Colors.green.shade300,
      Colors.green.shade500,
      Colors.green.shade700,
      Colors.amber.shade600,
    ];
    final s = _stage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: bgColors[s],
            shape: BoxShape.circle,
            border: Border.all(color: borderColors[s], width: s == 3 ? 4 : 2),
            boxShadow: s == 3
                ? [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 4,
                    )
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              s == 3 ? '🦍\n💪' : emojis[s],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: sizes[s],
                height: s == 3 ? 1.1 : 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            stageLabel[s],
            key: ValueKey(s),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: s == 3 ? Colors.amber.shade700 : Colors.green.shade800,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pancreas — Diabetes ──────────────────────────────────────────────────────

class _PancreasMascot extends StatelessWidget {
  final double stressLevel; // 0 = healthy, 1+ = rotten
  const _PancreasMascot({required this.stressLevel});

  String get _label {
    if (stressLevel < 0.5) return 'Healthy Pancreas 🩺';
    if (stressLevel < 0.8) return 'Slightly Stressed';
    if (stressLevel < 1.0) return 'Under Pressure ⚠️';
    return 'Overloaded! ❌';
  }

  Color get _labelColor {
    if (stressLevel < 0.5) return Colors.green.shade700;
    if (stressLevel < 0.8) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 100,
          child: CustomPaint(
            painter: _PancreasCustomPainter(stressLevel: stressLevel.clamp(0, 1.5)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: _labelColor,
          ),
        ),
      ],
    );
  }
}

class _PancreasCustomPainter extends CustomPainter {
  final double stressLevel;
  _PancreasCustomPainter({required this.stressLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Color based on stress ─────────────────────────────────────────────
    final Color bodyColor;
    if (stressLevel < 0.5) {
      bodyColor = Color.lerp(
        const Color(0xFFFFCDD2),
        const Color(0xFFF48FB1),
        stressLevel * 2,
      )!;
    } else if (stressLevel < 0.8) {
      bodyColor = Color.lerp(
        const Color(0xFFFFF9C4),
        const Color(0xFFFFCC02),
        (stressLevel - 0.5) / 0.3,
      )!;
    } else if (stressLevel < 1.0) {
      bodyColor = Color.lerp(
        const Color(0xFFFFCC02),
        const Color(0xFFE65100),
        (stressLevel - 0.8) / 0.2,
      )!;
    } else {
      bodyColor = Color.lerp(
        const Color(0xFFE65100),
        const Color(0xFF4E342E),
        ((stressLevel - 1.0) / 0.5).clamp(0, 1),
      )!;
    }

    final paint = Paint()..color = bodyColor;
    final outlinePaint = Paint()
      ..color = bodyColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // ── Pancreas path (elongated bean) ────────────────────────────────────
    final path = Path();
    // Head (left, large lobe)
    path.addOval(Rect.fromCenter(
        center: Offset(w * 0.28, h * 0.52),
        width: w * 0.40,
        height: h * 0.72));
    // Body+tail blending into head via a broader oval
    path.addOval(Rect.fromCenter(
        center: Offset(w * 0.60, h * 0.50),
        width: w * 0.60,
        height: h * 0.52));
    // Tail tip
    path.addOval(Rect.fromCenter(
        center: Offset(w * 0.88, h * 0.40),
        width: w * 0.18,
        height: h * 0.28));

    canvas.drawPath(path, paint);
    canvas.drawPath(path, outlinePaint);

    // ── Highlight (healthy shine) ─────────────────────────────────────────
    if (stressLevel < 0.6) {
      final shinePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(w * 0.25, h * 0.38),
            width: w * 0.14,
            height: h * 0.18),
        shinePaint,
      );
    }

    // ── Damage spots (appear > 60% stress) ───────────────────────────────
    if (stressLevel > 0.6) {
      final spotCount = ((stressLevel - 0.6) * 20).round().clamp(0, 10);
      final spotPaint = Paint()
        ..color = Colors.brown.shade800.withValues(alpha: 0.7);
      // Fixed positions so it looks deterministic
      const positions = [
        (0.45, 0.45), (0.60, 0.55), (0.72, 0.42), (0.55, 0.35),
        (0.38, 0.60), (0.68, 0.60), (0.80, 0.50), (0.50, 0.65),
        (0.63, 0.38), (0.42, 0.40),
      ];
      for (int i = 0; i < spotCount && i < positions.length; i++) {
        canvas.drawCircle(
          Offset(w * positions[i].$1, h * positions[i].$2),
          3.0 + i * 0.4,
          spotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PancreasCustomPainter old) =>
      old.stressLevel != stressLevel;
}

// ── Plant — Vegan ────────────────────────────────────────────────────────────

class _PlantMascot extends StatelessWidget {
  final double progress;
  const _PlantMascot({required this.progress});

  int get _stage {
    if (progress >= 0.75) return 3;
    if (progress >= 0.50) return 2;
    if (progress >= 0.25) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    const stageEmoji = ['🌱', '🌿', '🌳', '🌸'];
    const stageLabel = ['Seedling', 'Sprouting', 'Growing', 'In Full Bloom'];
    const stageSizes = [52.0, 64.0, 78.0, 88.0];
    final bgColors = [
      Colors.green.shade50,
      Colors.green.shade100,
      Colors.green.shade200,
      Colors.green.shade300,
    ];
    final s = _stage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: bgColors[s],
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.green.shade400,
              width: s == 3 ? 3 : 1.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s == 3) ...[
                  const Text('🌱', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                ],
                Text(stageEmoji[s],
                    style: TextStyle(fontSize: stageSizes[s])),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          stageLabel[s],
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Colors.green.shade800,
          ),
        ),
      ],
    );
  }
}

// ── Scale — Weight Loss ──────────────────────────────────────────────────────

class _ScaleMascot extends StatelessWidget {
  final double progress; // 0 = just started, 1 = goal reached
  const _ScaleMascot({required this.progress});

  String get _label {
    if (progress >= 1.0) return 'Goal Reached! 🎉';
    if (progress >= 0.66) return 'Almost There!';
    if (progress >= 0.33) return 'Making Progress';
    return 'Just Started';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 150,
          height: 130,
          child: CustomPaint(
            painter: _ScaleCustomPainter(progress: progress.clamp(0, 1.2)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: progress >= 1.0
                ? Colors.green.shade700
                : Colors.orange.shade800,
          ),
        ),
      ],
    );
  }
}

class _ScaleCustomPainter extends CustomPainter {
  final double progress;
  _ScaleCustomPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;
    final r  = size.width * 0.40;

    // ── Scale arc (semicircle) ────────────────────────────────────────────
    final arcPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi, math.pi, false, arcPaint);

    // ── Coloured zones ────────────────────────────────────────────────────
    final greenPaint = Paint()
      ..color = Colors.green.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    // Green = left half of arc
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi, math.pi / 2, false, greenPaint);

    final redPaint = Paint()
      ..color = Colors.red.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    // Red = right half of arc
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi * 1.5, math.pi / 2, false, redPaint);

    // ── Needle ────────────────────────────────────────────────────────────
    // progress=0 → needle far right (over-eating), progress=1 → far left (goal)
    // Map: 0 → 0° (right), 1 → 180° (left), mid=0.5 → 90° (center bottom)
    final angle = math.pi * (1.0 - progress.clamp(0, 1));
    final needleEnd = Offset(
      cx + r * 0.75 * math.cos(math.pi + angle),
      cy + r * 0.75 * math.sin(math.pi + angle),
    );
    final needlePaint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, cy), needleEnd, needlePaint);

    // Centre dot
    canvas.drawCircle(Offset(cx, cy), 6,
        Paint()..color = Colors.grey.shade700);

    // ── Base ──────────────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(cx - r * 0.6, cy),
      Offset(cx + r * 0.6, cy),
      Paint()
        ..color = Colors.grey.shade500
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // ── Labels ────────────────────────────────────────────────────────────
    _drawText(canvas, '🟢', Offset(cx - r * 0.85, cy - 6), 14);
    _drawText(canvas, '🔴', Offset(cx + r * 0.70, cy - 6), 14);
  }

  void _drawText(Canvas canvas, String text, Offset offset, double size) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_ScaleCustomPainter old) => old.progress != progress;
}

// ── Flame — Keto ─────────────────────────────────────────────────────────────

class _FlameMascot extends StatelessWidget {
  final double carbProgress; // 0 = no carbs (big flame), 1+ = over limit (extinguished)
  const _FlameMascot({required this.carbProgress});

  String get _label {
    if (carbProgress < 0.4) return '🔥 Deep Ketosis';
    if (carbProgress < 0.7) return '🔥 In Ketosis';
    if (carbProgress < 1.0) return '⚠️ Near Limit';
    return '❌ Ketosis Broken';
  }

  Color get _labelColor {
    if (carbProgress < 0.7) return Colors.deepOrange.shade700;
    return carbProgress < 1.0 ? Colors.orange.shade800 : Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 120,
          height: 150,
          child: CustomPaint(
            painter: _FlameCustomPainter(
                intensity: (1.0 - carbProgress.clamp(0, 1))),
          ),
        ),
        Text(
          _label,
          style: TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: _labelColor),
        ),
      ],
    );
  }
}

class _FlameCustomPainter extends CustomPainter {
  final double intensity; // 1 = full flame, 0 = extinguished
  _FlameCustomPainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.05) {
      // Draw smoke
      final smokePaint = Paint()..color = Colors.grey.shade400;
      for (int i = 0; i < 3; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width / 2 + (i - 1) * 8,
                size.height * 0.5 - i * 20),
            width: 12 + i * 4,
            height: 20,
          ),
          smokePaint,
        );
      }
      return;
    }

    final cx = size.width / 2;
    final baseY = size.height * 0.92;
    final flameH = size.height * intensity;

    // Outer flame (orange-red)
    final outerFlame = Path()
      ..moveTo(cx, baseY)
      ..cubicTo(
          cx - size.width * 0.35, baseY - flameH * 0.4,
          cx - size.width * 0.20, baseY - flameH * 0.7,
          cx, baseY - flameH)
      ..cubicTo(
          cx + size.width * 0.20, baseY - flameH * 0.7,
          cx + size.width * 0.35, baseY - flameH * 0.4,
          cx, baseY)
      ..close();

    final outerColor = Color.lerp(
        Colors.red.shade700, Colors.orange.shade400, intensity)!;
    canvas.drawPath(outerFlame, Paint()..color = outerColor);

    // Inner flame (yellow/white core)
    final innerFlame = Path()
      ..moveTo(cx, baseY)
      ..cubicTo(
          cx - size.width * 0.18, baseY - flameH * 0.35,
          cx - size.width * 0.10, baseY - flameH * 0.60,
          cx, baseY - flameH * 0.75)
      ..cubicTo(
          cx + size.width * 0.10, baseY - flameH * 0.60,
          cx + size.width * 0.18, baseY - flameH * 0.35,
          cx, baseY)
      ..close();

    canvas.drawPath(
        innerFlame,
        Paint()
          ..color = Color.lerp(Colors.yellow.shade300,
              Colors.white.withValues(alpha: 0.9), intensity * 0.5)!);

    // Base glow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, baseY),
          width: size.width * 0.5 * intensity,
          height: 10),
      Paint()..color = Colors.orange.withValues(alpha: 0.4 * intensity),
    );
  }

  @override
  bool shouldRepaint(_FlameCustomPainter old) => old.intensity != intensity;
}

// ── Balance — Maintain ────────────────────────────────────────────────────────

class _BalanceMascot extends StatelessWidget {
  final double progress;
  const _BalanceMascot({required this.progress});

  String get _label {
    if (progress < 0.5) return 'Under Target';
    if (progress < 0.9) return 'On Track 📈';
    if (progress < 1.1) return 'Balanced ✅';
    return 'Over Target';
  }

  @override
  Widget build(BuildContext context) {
    final isBalanced = progress >= 0.9 && progress <= 1.1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            color: isBalanced
                ? Colors.purple.shade100
                : Colors.purple.shade50,
            shape: BoxShape.circle,
            border: Border.all(
              color: isBalanced
                  ? Colors.purple.shade500
                  : Colors.purple.shade200,
              width: isBalanced ? 3 : 1.5,
            ),
          ),
          child: Center(
            child: Text(
              isBalanced ? '🎯' : (progress < 1 ? '📈' : '📉'),
              style: const TextStyle(fontSize: 64),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isBalanced ? Colors.purple.shade700 : Colors.purple.shade500,
          ),
        ),
      ],
    );
  }
}
