import 'package:flutter/material.dart';

import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';

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
          'Baby Gorilla ðŸ’',
          'Growing Strong ðŸ¦',
          'Mighty Gorilla ðŸ¦',
          'Champion! ðŸ¦ðŸ’ª',
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
          'Seedling ðŸŒ±',
          'Sprouting ðŸŒ¿',
          'Growing Strong ðŸŒ³',
          'In Full Bloom ðŸŒ¸',
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
          'Warming Up ðŸ”¥',
          'Fat Burning! ðŸ”¥ðŸ”¥',
          'Extreme Burn! ðŸ”¥ðŸ”¥ðŸ”¥',
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
          'Overloaded! âŒ',
          'Under Stress âš ï¸',
          'Healthy ðŸ©º',
          'Perfect Control âœ…',
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
  final double progress; // 0.0 â€“ 1.0+
  /// When true, high progress = lower stage (e.g. pancreas: high stress â†’ worse).
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
