import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../core/app_locale.dart';
import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../providers/locale_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

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

  // Page 2: gender
  UserGender _selectedGender = UserGender.male;

  // Page 3: goal type
  NutritionGoalType _selectedGoalType = NutritionGoalType.maintain;

  // Weight (kg) — collected between name and gender
  double _weightKg = 70.0;
  double _heightCm = 170.0;
  MuscleMassLevel _muscleMassLevel = MuscleMassLevel.average;

  // Page 4: macro targets (pre-filled from goal defaults, editable)
  late int _calories = GoalDefaults.caloriesForProfile(
    _selectedGoalType,
    weightKg: _weightKg,
    heightCm: _heightCm,
    muscleMassLevel: _muscleMassLevel,
    male: _selectedGender == UserGender.male,
  );
  late int _carbLimit = GoalDefaults.carbLimitG(_selectedGoalType);
  late int _proteinTarget = GoalDefaults.proteinTargetG(_selectedGoalType);
  late int _fatTarget = GoalDefaults.fatTargetG(_selectedGoalType);

  // Page 5 (diabetes only): ICR — 0.0 means user chose to skip
  double _icr = 0.0;
  final _icrCtrl = TextEditingController();

  bool get _isDiabetes => _selectedGoalType == NutritionGoalType.diabetes;
  int get _totalPages => _isDiabetes ? 8 : 7;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _icrCtrl.dispose();
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

  void _back() {
    if (_page > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _selectGender(UserGender gender) {
    final isMale = gender == UserGender.male;
    final newCal = GoalDefaults.caloriesForProfile(
      _selectedGoalType,
      weightKg: _weightKg,
      heightCm: _heightCm,
      muscleMassLevel: _muscleMassLevel,
      male: isMale,
    );
    final r = GoalDefaults.macroRatios(_selectedGoalType);
    setState(() {
      _selectedGender = gender;
      _calories = newCal;
      _carbLimit = (newCal * r.carb / 4).round().clamp(15, 500);
      _proteinTarget = (newCal * r.protein / 4).round().clamp(30, 300);
      _fatTarget = (newCal * r.fat / 9).round().clamp(20, 250);
    });
  }

  void _selectGoal(NutritionGoalType goal) {
    final isMale = _selectedGender == UserGender.male;
    final newCal = GoalDefaults.caloriesForProfile(
      goal,
      weightKg: _weightKg,
      heightCm: _heightCm,
      muscleMassLevel: _muscleMassLevel,
      male: isMale,
    );
    final r = GoalDefaults.macroRatios(goal);
    setState(() {
      _selectedGoalType = goal;
      _calories = newCal;
      _carbLimit = (newCal * r.carb / 4).round().clamp(15, 500);
      _proteinTarget = (newCal * r.protein / 4).round().clamp(30, 300);
      _fatTarget = (newCal * r.fat / 9).round().clamp(20, 250);
    });
  }

  void _onWeightChanged(double weightKg) {
    final snappedWeight = GoalDefaults.snapWeightKg(weightKg);
    final isMale = _selectedGender == UserGender.male;
    final newCal = GoalDefaults.caloriesForProfile(
      _selectedGoalType,
      weightKg: snappedWeight,
      heightCm: _heightCm,
      muscleMassLevel: _muscleMassLevel,
      male: isMale,
    );
    final r = GoalDefaults.macroRatios(_selectedGoalType);
    setState(() {
      _weightKg = snappedWeight;
      _calories = newCal;
      _carbLimit = (newCal * r.carb / 4).round().clamp(15, 500);
      _proteinTarget = (newCal * r.protein / 4).round().clamp(30, 300);
      _fatTarget = (newCal * r.fat / 9).round().clamp(20, 250);
    });
  }

  /// When the calorie slider moves, recalculate macros using evidence-based
  /// ratios for the chosen goal — not a simple proportional scale.
  void _onCaloriesChanged(int newCalories) {
    final r = GoalDefaults.macroRatios(_selectedGoalType);
    setState(() {
      _calories = newCalories;
      _carbLimit = (newCalories * r.carb / 4).round().clamp(15, 500);
      _proteinTarget = (newCalories * r.protein / 4).round().clamp(30, 300);
      _fatTarget = (newCalories * r.fat / 9).round().clamp(20, 250);
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
          gender: _selectedGender,
          icrGramsPerUnit: _icr,
          weightKg: _weightKg,
          heightCm: _heightCm,
          muscleMassLevel: _muscleMassLevel,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: context.primary50,
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
                      color:
                          _page == i ? context.primary600 : context.primary200,
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
                  _LanguagePage(
                    onNext: _next,
                    onSelect: (lang) {
                      ref.read(localeProvider.notifier).setLanguage(lang);
                    },
                  ),
                  _WelcomePage(onNext: _next),
                  _NamePage(
                      controller: _nameCtrl, onNext: _next, onBack: _back),
                  _WeightPage(
                    weightKg: _weightKg,
                    onChanged: _onWeightChanged,
                    onNext: _next,
                    onBack: _back,
                  ),
                  _GenderPage(
                    selected: _selectedGender,
                    onSelect: _selectGender,
                    onNext: _next,
                    onBack: _back,
                  ),
                  _GoalTypePage(
                    selected: _selectedGoalType,
                    onSelect: _selectGoal,
                    onNext: _next,
                    onBack: _back,
                  ),
                  _ConfirmPage(
                    goalType: _selectedGoalType,
                    calories: _calories,
                    carbLimit: _carbLimit,
                    proteinTarget: _proteinTarget,
                    fatTarget: _fatTarget,
                    onCaloriesChanged: _onCaloriesChanged,
                    onCarbChanged: (v) => setState(() => _carbLimit = v),
                    onProteinChanged: (v) => setState(() => _proteinTarget = v),
                    onFatChanged: (v) => setState(() => _fatTarget = v),
                    onFinish: _isDiabetes ? _next : _finish,
                    onBack: _back,
                    finishLabel: _isDiabetes ? l10n.next : l10n.startScanning,
                  ),
                  if (_isDiabetes)
                    _IcrPage(
                      controller: _icrCtrl,
                      onChanged: (v) => setState(() => _icr = v),
                      onFinish: _finish,
                      onBack: _back,
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

class _OnboardingScrollFrame extends StatelessWidget {
  const _OnboardingScrollFrame({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 32),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: padding,
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }
}

// â”€â”€ Page 0: Welcome â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _OnboardingScrollFrame(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: context.primary100,
              shape: BoxShape.circle,
              border: Border.all(color: context.primary400, width: 3),
            ),
            child: Icon(Icons.eco, size: 56, color: context.primary600),
          ),
          const SizedBox(height: 32),
          Text(
            l10n.welcomeTitle,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: context.primary700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.welcomeSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.gray400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: Text(l10n.getStarted),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Page 1: Name â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _NamePage extends StatelessWidget {
  const _NamePage(
      {required this.controller, required this.onNext, required this.onBack});
  final TextEditingController controller;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _OnboardingScrollFrame(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_outline, size: 56, color: context.primary500),
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
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                onNext();
              },
              child: Text(AppLocalizations.of(context).continueLabel),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Page 2: Goal Type â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// ── Page 2: Gender ─────────────────────────────────────────────────────────────

class _GenderPage extends StatelessWidget {
  const _GenderPage({
    required this.selected,
    required this.onSelect,
    required this.onNext,
    required this.onBack,
  });
  final UserGender selected;
  final ValueChanged<UserGender> onSelect;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _OnboardingScrollFrame(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_outlined,
              size: 56, color: context.primary500),
          const SizedBox(height: 24),
          const Text(
            'Biological sex',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Used to personalise your nutrient targets\n(vitamin, mineral & calorie recommendations).',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: AppTheme.gray400, height: 1.5),
          ),
          const SizedBox(height: 32),
          _GenderOption(
            icon: Icons.male,
            label: AppLocalizations.of(context).male,
            isSelected: selected == UserGender.male,
            onTap: () => onSelect(UserGender.male),
          ),
          const SizedBox(height: 12),
          _GenderOption(
            icon: Icons.female,
            label: AppLocalizations.of(context).female,
            isSelected: selected == UserGender.female,
            onTap: () => onSelect(UserGender.female),
          ),
          const SizedBox(height: 12),
          _GenderOption(
            icon: Icons.help_outline,
            label: AppLocalizations.of(context).preferNotToSay,
            isSelected: selected == UserGender.preferNotToSay,
            onTap: () => onSelect(UserGender.preferNotToSay),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: Text(AppLocalizations.of(context).continueLabel),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(AppLocalizations.of(context).back),
            style: TextButton.styleFrom(foregroundColor: AppTheme.gray500),
          ),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? context.primary100 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.primary600 : AppTheme.gray300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 24,
                color: isSelected ? context.primary600 : AppTheme.gray400),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isSelected ? context.primary700 : AppTheme.gray600,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle, color: context.primary600, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GoalTypePage extends StatelessWidget {
  const _GoalTypePage({
    required this.selected,
    required this.onSelect,
    required this.onNext,
    required this.onBack,
  });
  final NutritionGoalType selected;
  final ValueChanged<NutritionGoalType> onSelect;
  final VoidCallback onNext;
  final VoidCallback onBack;

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
                final premium = context.isPremiumTheme;
                final selectedFill = premium
                    ? context.visualTheme.primaryAccent.withValues(alpha: 0.22)
                    : goal.lightColor;
                final unselectedFill =
                    premium ? context.appSubtleFillColor : Colors.white;
                final selectedBorder =
                    premium ? context.visualTheme.primaryAccent : goal.color;
                final labelColor = isSelected
                    ? (premium ? context.appTextColor : goal.color)
                    : (premium ? context.appMutedTextColor : AppTheme.gray600);
                return GestureDetector(
                  onTap: () => onSelect(goal),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedFill : unselectedFill,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? selectedBorder
                            : (premium
                                ? context.appBorderColor
                                : AppTheme.gray300),
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
                        Text(goal.emoji, style: const TextStyle(fontSize: 36)),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.of(context).nutritionGoalLabel(goal.name),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: labelColor,
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
                border:
                    Border.all(color: selected.color.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(selected.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).nutritionGoalDescription(selected.name),
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
              child: Text(AppLocalizations.of(context).next),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(AppLocalizations.of(context).back),
            style: TextButton.styleFrom(foregroundColor: AppTheme.gray500),
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
    required this.onBack,
    this.finishLabel = 'Start Scanning! 🚀',
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
  final VoidCallback onBack;
  final String finishLabel;

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
                  AppLocalizations.of(context).nutritionGoalLabel(goalType.name),
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
          // Dynamic thresholds: green = within ±25% of goal ratio,
          // orange = 25-50% off, red = >50% off.
          Builder(builder: (_) {
            final r = GoalDefaults.macroRatios(goalType);
            final idealCarb = (calories * r.carb / 4).round();
            final idealProtein = (calories * r.protein / 4).round();
            final idealFat = (calories * r.fat / 9).round();
            // Calorie thresholds: goal-specific healthy range
            final goalCal = goalType == NutritionGoalType.weightLoss
                ? 2200
                : goalType == NutritionGoalType.muscleGrowth
                    ? 4000
                    : 3200;
            return Column(children: [
              _TargetSlider(
                label: '🔥 Daily Calories',
                value: calories,
                min: 1200,
                max: 5000,
                step: 100,
                unit: 'kcal',
                color: goalType.color,
                warningValue: goalCal,
                dangerValue: (goalCal * 1.25).round(),
                onChanged: onCaloriesChanged,
              ),
              const SizedBox(height: 16),
              _TargetSlider(
                label: '🍞 Carb Limit',
                value: carbLimit,
                min: 15,
                max: 500,
                step: 5,
                unit: 'g / day',
                color: Colors.amber.shade700,
                warningValue: (idealCarb * 1.3).round().clamp(20, 500),
                dangerValue: (idealCarb * 1.6).round().clamp(30, 500),
                onChanged: onCarbChanged,
              ),
              const SizedBox(height: 16),
              _TargetSlider(
                label: '💪 Protein Target',
                value: proteinTarget,
                min: 30,
                max: 300,
                step: 5,
                unit: 'g / day',
                color: Colors.red.shade600,
                warningValue: (idealProtein * 1.3).round().clamp(40, 300),
                dangerValue: (idealProtein * 1.6).round().clamp(50, 300),
                onChanged: onProteinChanged,
              ),
              const SizedBox(height: 16),
              _TargetSlider(
                label: '🥑 Fat Target',
                value: fatTarget,
                min: 20,
                max: 250,
                step: 5,
                unit: 'g / day',
                color: Colors.green.shade600,
                warningValue: (idealFat * 1.3).round().clamp(25, 250),
                dangerValue: (idealFat * 1.6).round().clamp(35, 250),
                onChanged: onFatChanged,
              ),
            ]);
          }),
          const SizedBox(height: 16),
          // Show macro breakdown info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: goalType.lightColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: goalType.color.withValues(alpha: 0.3)),
            ),
            child: Builder(builder: (_) {
              final carbCal = carbLimit * 4;
              final protCal = proteinTarget * 4;
              final fatCal = fatTarget * 9;
              final total = carbCal + protCal + fatCal;
              final pct = calories > 0 ? (total / calories * 100).round() : 0;
              return Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: goalType.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Macros add up to $total kcal ($pct% of $calories kcal target)',
                      style: TextStyle(
                        fontSize: 11,
                        color: goalType.color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFinish,
              child: Text(finishLabel),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(AppLocalizations.of(context).back),
            style: TextButton.styleFrom(foregroundColor: AppTheme.gray500),
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
    this.warningValue,
    this.dangerValue,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String unit;
  final Color color;
  final ValueChanged<int> onChanged;
  final int? warningValue;
  final int? dangerValue;

  Color get _activeColor {
    if (warningValue == null || dangerValue == null)
      return Colors.green.shade600;
    if (value > dangerValue!) return Colors.red.shade600;
    if (value > (warningValue! + dangerValue!) / 2)
      return Colors.orange.shade700;
    if (value > warningValue!) return Colors.yellow.shade700;
    return Colors.green.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _activeColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(
              '$value $unit',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: activeColor,
                  fontSize: 14),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ step,
          activeColor: activeColor,
          inactiveColor: activeColor.withValues(alpha: 0.2),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}

// ── Page 2: Weight ─────────────────────────────────────────────────────────────

class _WeightPage extends StatelessWidget {
  const _WeightPage({
    required this.weightKg,
    required this.onChanged,
    required this.onNext,
    required this.onBack,
  });
  final double weightKg;
  final ValueChanged<double> onChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayWeight = GoalDefaults.formatWeightKg(weightKg);

    return _OnboardingScrollFrame(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_weight_outlined,
              size: 56, color: context.primary500),
          const SizedBox(height: 24),
          Text(
            l10n.weightKg,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.weightEstimateNote,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.gray400, height: 1.5),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: weightKg <= GoalDefaults.minWeightKg
                    ? null
                    : () => onChanged(weightKg - GoalDefaults.weightStepKg),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: l10n.weightKg,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editWeight(context),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$displayWeight kg',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: context.primary700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 20, color: context.primary500),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: weightKg >= GoalDefaults.maxWeightKg
                    ? null
                    : () => onChanged(weightKg + GoalDefaults.weightStepKg),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          Text(
            '≈ ${(weightKg * 2.20462).round()} lbs',
            style: const TextStyle(fontSize: 14, color: AppTheme.gray400),
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
            ),
            child: Slider(
              value: GoalDefaults.clampWeightKg(weightKg),
              min: GoalDefaults.minWeightKg,
              max: GoalDefaults.maxWeightKg,
              divisions:
                  ((GoalDefaults.maxWeightKg - GoalDefaults.minWeightKg) /
                          GoalDefaults.weightStepKg)
                      .round(),
              activeColor: context.primary600,
              inactiveColor: context.primary200,
              onChanged: (value) => onChanged(value),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${GoalDefaults.minWeightKg.round()} kg',
                  style: TextStyle(fontSize: 11, color: AppTheme.gray400)),
              Text('${GoalDefaults.maxWeightKg.round()} kg',
                  style: TextStyle(fontSize: 11, color: AppTheme.gray400)),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: Text(AppLocalizations.of(context).continueLabel),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(AppLocalizations.of(context).back),
            style: TextButton.styleFrom(foregroundColor: AppTheme.gray500),
          ),
        ],
      ),
    );
  }

  Future<void> _editWeight(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: GoalDefaults.formatWeightKg(weightKg));

    double? parse() {
      final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
      if (parsed == null) return null;
      return GoalDefaults.snapWeightKg(parsed);
    }

    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.weightKg),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: 'kg',
            helperText:
                '${GoalDefaults.minWeightKg.round()}-${GoalDefaults.maxWeightKg.round()} kg',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, parse()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parse()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    controller.dispose();
    if (selected != null) onChanged(selected);
  }
}

// ── Page 5 (diabetes only): ICR setup ─────────────────────────────────────────

class _IcrPage extends StatelessWidget {
  const _IcrPage({
    required this.controller,
    required this.onChanged,
    required this.onFinish,
    required this.onBack,
  });

  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final VoidCallback onFinish;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 16),
          const Text('🩺', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Your Insulin-to-Carb Ratio',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1976D2), width: 1),
            ),
            child: const Text(
              'Your ICR (Insulin-to-Carb Ratio) tells you how many grams of carbohydrate one unit of insulin covers.\n\n'
              'Example: an ICR of 10 means 1 unit covers 10 g of carbs.\n\n'
              'This value is personal and should be set by your diabetes care team. '
              'Do NOT use a pre-set value — an incorrect ICR can cause dangerous blood sugar swings.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF1565C0), height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'ICR — grams of carbs per 1 unit of insulin',
              hintText: 'e.g. 10',
              prefixIcon: Icon(Icons.vaccines_outlined),
              suffixText: 'g / unit',
            ),
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            onChanged: (v) {
              final parsed = double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
              onChanged(parsed);
            },
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => FocusScope.of(context).unfocus(),
              icon: const Icon(Icons.keyboard_hide_outlined, size: 18),
              label: Text(AppLocalizations.of(context).hideKeyboard),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final v = double.tryParse(
                      controller.text.replaceAll(',', '.'),
                    ) ??
                    0.0;
                onChanged(v);
                onFinish();
              },
              child: Text(AppLocalizations.of(context).startScanning),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              onChanged(0.0); // 0.0 = not set
              onFinish();
            },
            child: Text(
              AppLocalizations.of(context).skipSetLater,
              style: const TextStyle(color: AppTheme.gray500),
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(AppLocalizations.of(context).back),
            style: TextButton.styleFrom(foregroundColor: AppTheme.gray500),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Language Selection Page ──────────────────────────────────────────────────

class _LanguagePage extends StatelessWidget {
  const _LanguagePage({required this.onNext, required this.onSelect});
  final VoidCallback onNext;
  final ValueChanged<AppLanguage> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _OnboardingScrollFrame(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.translate, size: 56, color: AppTheme.gray600),
          const SizedBox(height: 24),
          Text(
            l10n.chooseLanguage,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.languageChangeLater,
            style: const TextStyle(fontSize: 14, color: AppTheme.gray400),
          ),
          const SizedBox(height: 32),
          ...AppLanguage.values.map((lang) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      onSelect(lang);
                      onNext();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Text(lang.flag, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 14),
                        Text(
                          lang.nativeName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
