import 'package:flutter/material.dart';

import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';
import '../theme/app_theme.dart';

// â”€â”€ Public entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Displays an animated mascot for the user's nutrition goal.
///
/// [progress]       â€” calories consumed / calorie goal  (0.0 â€“ 1.0+)
/// [stressLevel]    â€” carbs consumed / carb limit       (0.0 â€“ 1.0+)
/// [mascotOverride] â€” when non-auto, shows this mascot regardless of goalType.
class GoalMascotWidget extends StatelessWidget {
  final NutritionGoalType goalType;
  final double progress;
  final double stressLevel;
  final MascotType mascotOverride;
  final VoidCallback? onTap;

  const GoalMascotWidget({
    super.key,
    required this.goalType,
    required this.progress,
    this.stressLevel = 0,
    this.mascotOverride = MascotType.auto,
    this.onTap,
  });

  MascotType get _effectiveMascot {
    if (mascotOverride != MascotType.auto) return mascotOverride;
    switch (goalType) {
      case NutritionGoalType.muscleGrowth: return MascotType.gorilla;
      case NutritionGoalType.vegan:        return MascotType.plant;
      case NutritionGoalType.keto:         return MascotType.flame;
      case NutritionGoalType.weightLoss:   return MascotType.flame;
      case NutritionGoalType.diabetes:     return MascotType.sugar;
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
          onTap: onTap,
        );
      case MascotType.plant:
        return _ImageMascot(
          stages: const _MascotStages.plant(),
          progress: progress,
          onTap: onTap,
        );
      case MascotType.flame:
        return _ImageMascot(
          stages: const _MascotStages.flame(),
          progress: progress,
          onTap: onTap,
        );
      case MascotType.sugar:
        return _ImageMascot(
          stages: const _MascotStages.sugar(),
          progress: stressLevel,
          invertStage: true,
          onTap: onTap,
        );
      case MascotType.auto:
        return _ImageMascot(
          stages: const _MascotStages.plant(),
          progress: progress,
          onTap: onTap,
        );
    }
  }
}

// â”€â”€ Mascot stage data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
          'Baby Gorilla',
          'Growing Strong',
          'Mighty Gorilla',
          'Champion',
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
          'assets/mascots/huge_tree.png',
        ],
        labels = const [
          'Seedling',
          'Sprouting',
          'Growing Strong',
          'In Full Bloom',
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
          'Warming Up',
          'Fat Burning',
          'Extreme Burn',
        ],
        bgColors = const [
          Color(0xFFFFF7ED),
          Color(0xFFFED7AA),
          Color(0xFFFB923C),
          Color(0xFFEA580C),
        ];

  const _MascotStages.sugar()
      : imagePaths = const [
          'assets/mascots/very_unhealty_sugar.PNG',
          'assets/mascots/bit_unhealthy_sugar.PNG',
          'assets/mascots/healthy_sugar.PNG',
          'assets/mascots/very_healthy_sugar.PNG',
        ],
        labels = const [
          'Sugar Overload',
          'Too Much Sugar',
          'Under Control',
          'Excellent Control',
        ],
        bgColors = const [
          Color(0xFFFEE2E2),
          Color(0xFFFEF3C7),
          Color(0xFFDCFCE7),
          Color(0xFFBBF7D0),
        ];
}

// â”€â”€ Shared image mascot widget â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ImageMascot extends StatelessWidget {
  final _MascotStages stages;
  final double progress; // 0.0 – 1.0+
  /// When true, high progress = lower stage (e.g. pancreas: high stress → worse).
  final bool invertStage;
  final VoidCallback? onTap;

  const _ImageMascot({
    required this.stages,
    required this.progress,
    this.invertStage = false,
    this.onTap,
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
    // Circle colours follow the app's chosen theme seed.
    final bgColor           = context.primary100;
    final borderActiveColor = context.primary400;
    final borderIdleColor   = context.primary200;
    final isBest = s == 3;

    final col = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          width: 120,
          height: 120,
          // clipBehavior ensures the image never bleeds outside the circle.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: isBest ? borderActiveColor : borderIdleColor,
              width: isBest ? 3 : 1.5,
            ),
            boxShadow: isBest
                ? [
                    BoxShadow(
                      color: borderActiveColor.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 4,
                    )
                  ]
                : [],
          ),
          // Padding gives a consistent inset so every mascot image is
          // comfortably inside the circle with no clipping at the edges.
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Image.asset(
                stages.imagePaths[s],
                key: ValueKey(s),
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('🍽️', style: TextStyle(fontSize: 40)),
                ),
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
                  ? context.primary700
                  : AppTheme.gray700,
            ),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(height: 4),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nutrition details',
                style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
              Icon(Icons.chevron_right, size: 12, color: Color(0xFF9CA3AF)),
            ],
          ),
        ],
      ],
    );

    return onTap != null
        ? GestureDetector(onTap: onTap, child: col)
        : col;
  }
}
