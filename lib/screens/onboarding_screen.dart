import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';

/// First-launch onboarding: collects name, goal type, and macro targets.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Page 1: name
  final _nameCtrl = TextEditingController();

  // Page 2: goal type
  NutritionGoalType _selectedGoalType = NutritionGoalType.maintain;

  // Page 3: macro targets (pre-filled from goal defaults, editable)
  late int _calories    = GoalDefaults.calories(_selectedGoalType);
  late int _carbLimit   = GoalDefaults.carbLimitG(_selectedGoalType);
  late int _proteinTarget = GoalDefaults.proteinTargetG(_selectedGoalType);
  late int _fatTarget   = GoalDefaults.fatTargetG(_selectedGoalType);

  static const _totalPages = 4;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _totalPages - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _selectGoal(NutritionGoalType goal) {
    setState(() {
      _selectedGoalType = goal;
      _calories      = GoalDefaults.calories(goal);
      _carbLimit     = GoalDefaults.carbLimitG(goal);
      _proteinTarget = GoalDefaults.proteinTargetG(goal);
      _fatTarget     = GoalDefaults.fatTargetG(goal);
    });
  }

  Future<void> _finish() async {
    await ref.read(userPrefsProvider.notifier).completeOnboarding(
          name: _nameCtrl.text.trim(),
          dailyCalorieGoal: _calories,
          nutritionGoal: _selectedGoalType,
          dailyCarbLimitG: _carbLimit,
          dailyProteinTargetG: _proteinTarget,
          dailyFatTargetG: _fatTarget,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.green50,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i ? AppTheme.green600 : AppTheme.green200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomePage(onNext: _next),
                  _NamePage(controller: _nameCtrl, onNext: _next),
                  _GoalTypePage(
                    selected: _selectedGoalType,
                    onSelect: _selectGoal,
                    onNext: _next,
                  ),
                  _ConfirmPage(
                    goalType: _selectedGoalType,
                    calories: _calories,
                    carbLimit: _carbLimit,
                    proteinTarget: _proteinTarget,
                    fatTarget: _fatTarget,
                    onCaloriesChanged: (v) => setState(() => _calories = v),
                    onCarbChanged: (v) => setState(() => _carbLimit = v),
                    onProteinChanged: (v) => setState(() => _proteinTarget = v),
                    onFatChanged: (v) => setState(() => _fatTarget = v),
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Page 0: Welcome â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.green100,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.green300, width: 3),
            ),
            child: const Icon(Icons.eco, size: 56, color: AppTheme.green600),
          ),
          const SizedBox(height: 32),
          const Text(
            'Pixels to Macros',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.green700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scan your food with your camera and get\n'
            'instant calorie estimates â€” 100% offline.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppTheme.gray400, height: 1.5),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Get Started'),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Page 1: Name â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NamePage extends StatelessWidget {
  const _NamePage({required this.controller, required this.onNext});
  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_outline, size: 56, color: AppTheme.green500),
          const SizedBox(height: 24),
          const Text(
            'What\'s your name?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'We\'ll use it to personalise your dashboard.',
            style: TextStyle(fontSize: 14, color: AppTheme.gray400),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Page 2: Goal Type â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GoalTypePage extends StatelessWidget {
  const _GoalTypePage({
    required this.selected,
    required this.onSelect,
    required this.onNext,
  });
  final NutritionGoalType selected;
  final ValueChanged<NutritionGoalType> onSelect;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Text(
            'What\'s your goal?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose the plan that fits your lifestyle.',
            style: TextStyle(fontSize: 13, color: AppTheme.gray400),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: NutritionGoalType.values.map((goal) {
                final isSelected = goal == selected;
                return GestureDetector(
                  onTap: () => onSelect(goal),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? goal.lightColor : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? goal.color : AppTheme.gray300,
                        width: isSelected ? 2.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(goal.emoji,
                            style: const TextStyle(fontSize: 36)),
                        const SizedBox(height: 6),
                        Text(
                          goal.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected ? goal.color : AppTheme.gray600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Selected goal description
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Container(
              key: ValueKey(selected),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected.lightColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected.color.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(selected.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selected.description,
                      style: TextStyle(
                          fontSize: 12, color: selected.color, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Next'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// â”€â”€ Page 3: Confirm Targets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ConfirmPage extends StatelessWidget {
  const _ConfirmPage({
    required this.goalType,
    required this.calories,
    required this.carbLimit,
    required this.proteinTarget,
    required this.fatTarget,
    required this.onCaloriesChanged,
    required this.onCarbChanged,
    required this.onProteinChanged,
    required this.onFatChanged,
    required this.onFinish,
  });

  final NutritionGoalType goalType;
  final int calories;
  final int carbLimit;
  final int proteinTarget;
  final int fatTarget;
  final ValueChanged<int> onCaloriesChanged;
  final ValueChanged<int> onCarbChanged;
  final ValueChanged<int> onProteinChanged;
  final ValueChanged<int> onFatChanged;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                Text(goalType.emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(height: 4),
                Text(
                  goalType.label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: goalType.color,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Your daily targets (adjust if needed)',
                  style: TextStyle(fontSize: 13, color: AppTheme.gray400),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _TargetSlider(
            label: 'ðŸ”¥ Daily Calories',
            value: calories,
            min: 1200,
            max: 5000,
            step: 100,
            unit: 'kcal',
            color: goalType.color,
            onChanged: onCaloriesChanged,
          ),
          const SizedBox(height: 16),
          _TargetSlider(
            label: 'ðŸž Carb Limit',
            value: carbLimit,
            min: 15,
            max: 500,
            step: 5,
            unit: 'g / day',
            color: Colors.amber.shade700,
            onChanged: onCarbChanged,
          ),
          const SizedBox(height: 16),
          _TargetSlider(
            label: 'ðŸ’ª Protein Target',
            value: proteinTarget,
            min: 30,
            max: 300,
            step: 5,
            unit: 'g / day',
            color: Colors.red.shade600,
            onChanged: onProteinChanged,
          ),
          const SizedBox(height: 16),
          _TargetSlider(
            label: 'ðŸ¥‘ Fat Target',
            value: fatTarget,
            min: 20,
            max: 250,
            step: 5,
            unit: 'g / day',
            color: Colors.green.shade600,
            onChanged: onFatChanged,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFinish,
              child: const Text('Start Scanning! ðŸš€'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TargetSlider extends StatelessWidget {
  const _TargetSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            Text(
              '$value $unit',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 14),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ step,
          activeColor: color,
          inactiveColor: color.withValues(alpha: 0.2),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
