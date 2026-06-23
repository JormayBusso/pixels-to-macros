import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../core/app_locale.dart';
import '../models/dietary_restriction.dart';
import '../models/mascot_type.dart';
import '../models/glucose_unit.dart';
import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../providers/scroll_trigger_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../providers/diabetes_provider.dart';
import '../providers/weight_tracking_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';
import '../widgets/premium_theme_effects.dart';
import '../widgets/tour_keys.dart';
import 'auth_screen.dart';
import 'eval_dashboard_screen.dart';
import 'diabetes/bolus_setup_screen.dart';
import 'diabetes/diabetes_review_screen.dart';
import 'food_database_screen.dart';
import 'onboarding_screen.dart';

/// Settings screen for editing user profile and calorie goal.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _goalCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _carbCtrl;
  late TextEditingController _proteinCtrl;
  late TextEditingController _fatCtrl;
  late TextEditingController _waterCtrl;
  bool _obscurePassword = true;
  int _foodCount = 0;
  final _accountScrollController = ScrollController();
  // Private keys replaced by TourKeys so AppTutorialOverlay can measure them.
  int _lastVacationTrigger = 0;
  int _lastWeeklyReviewTrigger = 0;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPrefsProvider);
    _nameCtrl = TextEditingController(text: prefs.name);
    _goalCtrl = TextEditingController(text: prefs.dailyCalorieGoal.toString());
    _passwordCtrl = TextEditingController();
    _weightCtrl = TextEditingController(
        text: GoalDefaults.formatWeightKg(prefs.weightKg));
    _heightCtrl = TextEditingController(
        text: GoalDefaults.formatHeightCm(prefs.heightCm));
    _carbCtrl = TextEditingController(text: prefs.dailyCarbLimitG.toString());
    _proteinCtrl =
        TextEditingController(text: prefs.dailyProteinTargetG.toString());
    _fatCtrl = TextEditingController(text: prefs.dailyFatTargetG.toString());
    _waterCtrl = TextEditingController(text: prefs.dailyWaterGoalMl.toString());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(weightTrackingProvider.notifier).load(),
    );
    _loadFoodCount();
  }

  Future<void> _loadFoodCount() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (mounted) setState(() => _foodCount = foods.length);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    _passwordCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _carbCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _waterCtrl.dispose();
    _accountScrollController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _saveDebounce?.cancel();
    await _persistPrefs();
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).settingsSaved)),
      );
    }
  }

  /// Debounced save used by sliders — only persists after the user stops
  /// dragging for 400 ms and never shows a toast on every tick.
  void _saveSilent() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      await _persistPrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsSaved)),
        );
      }
    });
  }

  Future<void> _persistPrefs() async {
    final goal = int.tryParse(_goalCtrl.text) ?? 2000;
    final carb = int.tryParse(_carbCtrl.text) ?? 250;
    final protein = int.tryParse(_proteinCtrl.text) ?? 80;
    final fat = int.tryParse(_fatCtrl.text) ?? 65;
    final water = int.tryParse(_waterCtrl.text) ?? 2000;
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.')) ??
        ref.read(userPrefsProvider).weightKg;
    final height = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ??
        ref.read(userPrefsProvider).heightCm;
    final prefs = ref.read(userPrefsProvider).copyWith(
          name: _nameCtrl.text.trim(),
          dailyCalorieGoal: goal.clamp(500, 10000),
          dailyCarbLimitG: carb.clamp(0, 1000),
          dailyProteinTargetG: protein.clamp(0, 500),
          dailyFatTargetG: fat.clamp(0, 500),
          dailyWaterGoalMl: water.clamp(500, 10000),
          weightKg: GoalDefaults.snapWeightKg(weight),
          heightCm: GoalDefaults.snapHeightCm(height),
        );
    await ref.read(userPrefsProvider.notifier).update(prefs);
  }

  void _setWeightKg(double weightKg) {
    final snappedWeight = GoalDefaults.snapWeightKg(weightKg);
    final prefs = ref.read(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final calories = GoalDefaults.caloriesForProfile(
      prefs.nutritionGoal,
      weightKg: snappedWeight,
      heightCm: prefs.heightCm,
      muscleMassLevel: prefs.muscleMassLevel,
      male: isMale,
    );
    final macros = GoalDefaults.macroGrams(prefs.nutritionGoal, calories);
    setState(() {
      _weightCtrl.text = GoalDefaults.formatWeightKg(snappedWeight);
      _goalCtrl.text = calories.toString();
      _carbCtrl.text = macros.carbG.clamp(15, 500).toString();
      _proteinCtrl.text = macros.proteinG.clamp(30, 300).toString();
      _fatCtrl.text = macros.fatG.clamp(20, 250).toString();
    });
    _saveSilent();
  }

  void _setHeightCm(double heightCm) {
    final snappedHeight = GoalDefaults.snapHeightCm(heightCm);
    final prefs = ref.read(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.')) ??
        prefs.weightKg;
    final snappedWeight = GoalDefaults.snapWeightKg(weight);
    final calories = GoalDefaults.caloriesForProfile(
      prefs.nutritionGoal,
      weightKg: snappedWeight,
      heightCm: snappedHeight,
      muscleMassLevel: prefs.muscleMassLevel,
      male: isMale,
    );
    final macros = GoalDefaults.macroGrams(prefs.nutritionGoal, calories);
    setState(() {
      _heightCtrl.text = GoalDefaults.formatHeightCm(snappedHeight);
      _weightCtrl.text = GoalDefaults.formatWeightKg(snappedWeight);
      _goalCtrl.text = calories.toString();
      _carbCtrl.text = macros.carbG.clamp(15, 500).toString();
      _proteinCtrl.text = macros.proteinG.clamp(30, 300).toString();
      _fatCtrl.text = macros.fatG.clamp(20, 250).toString();
    });
    _saveSilent();
  }

  Future<void> _setMuscleMassLevel(MuscleMassLevel muscleMassLevel) async {
    final prefs = ref.read(userPrefsProvider);
    final isMale = prefs.gender == UserGender.male;
    final weight = double.tryParse(_weightCtrl.text.replaceAll(',', '.')) ??
        prefs.weightKg;
    final height = double.tryParse(_heightCtrl.text.replaceAll(',', '.')) ??
        prefs.heightCm;
    final snappedWeight = GoalDefaults.snapWeightKg(weight);
    final snappedHeight = GoalDefaults.snapHeightCm(height);
    final calories = GoalDefaults.caloriesForProfile(
      prefs.nutritionGoal,
      weightKg: snappedWeight,
      heightCm: snappedHeight,
      muscleMassLevel: muscleMassLevel,
      male: isMale,
    );
    final macros = GoalDefaults.macroGrams(prefs.nutritionGoal, calories);
    setState(() {
      _weightCtrl.text = GoalDefaults.formatWeightKg(snappedWeight);
      _heightCtrl.text = GoalDefaults.formatHeightCm(snappedHeight);
      _goalCtrl.text = calories.toString();
      _carbCtrl.text = macros.carbG.clamp(15, 500).toString();
      _proteinCtrl.text = macros.proteinG.clamp(30, 300).toString();
      _fatCtrl.text = macros.fatG.clamp(20, 250).toString();
    });
    await ref.read(userPrefsProvider.notifier).update(
          prefs.copyWith(
            weightKg: snappedWeight,
            heightCm: snappedHeight,
            muscleMassLevel: muscleMassLevel,
            dailyCalorieGoal: calories,
            dailyCarbLimitG: macros.carbG.clamp(15, 500),
            dailyProteinTargetG: macros.proteinG.clamp(30, 300),
            dailyFatTargetG: macros.fatG.clamp(20, 250),
          ),
        );
  }

  Future<void> _exportCsv({required bool detailed}) async {
    final export = DataExportService.instance;
    final csv = detailed
        ? await export.exportToCsv()
        : await export.exportDailySummary();
    await export.copyToClipboard(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).csvCopied)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vacationTrigger = ref.watch(scrollToVacationProvider);
    final weeklyReviewTrigger = ref.watch(scrollToWeeklyReviewProvider);
    if (vacationTrigger != _lastVacationTrigger) {
      _lastVacationTrigger = vacationTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = TourKeys.vacationModeCard.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        } else if (_accountScrollController.hasClients) {
          _accountScrollController.animateTo(
            _accountScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
    if (weeklyReviewTrigger != _lastWeeklyReviewTrigger) {
      _lastWeeklyReviewTrigger = weeklyReviewTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = TourKeys.weeklyReviewCard.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.0,
          );
        } else if (_accountScrollController.hasClients) {
          _accountScrollController.animateTo(
            _accountScrollController.position.maxScrollExtent - 200,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.settings),
          bottom: TabBar(
            isScrollable: true,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: [
              Tab(icon: const Icon(Icons.person_outline), text: l10n.account),
              Tab(
                  icon: const Icon(Icons.palette_outlined),
                  text: l10n.appearance),
              Tab(
                  icon: const Icon(Icons.privacy_tip_outlined),
                  text: l10n.privacy),
              Tab(
                  icon: const Icon(Icons.science_outlined),
                  text: l10n.evaluation),
            ],
          ),
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: TabBarView(
              children: [
                // ── Account tab ──────────────────────────────────────────
                _buildAccountTab(),
                // ── Appearance tab ───────────────────────────────────────
                _buildAppearanceTab(),
                // ── Privacy tab ──────────────────────────────────────────
                _buildPrivacyTab(),
                // ── Evaluation tab ───────────────────────────────────────
                _buildEvaluationTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      controller: _accountScrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(l10n.profile),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.yourName,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) => _WeightCalibrationCard(
                    onTargetsChanged: (calories, weightKg) {
                      setState(() {
                        _goalCtrl.text = calories.toString();
                        _weightCtrl.text =
                            GoalDefaults.formatWeightKg(weightKg);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _goalCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: l10n.dailyCalorieGoal,
                    prefixIcon: const Icon(Icons.flag_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                // Gender picker
                Consumer(
                  builder: (context, ref, _) {
                    final prefs = ref.watch(userPrefsProvider);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.selectGender,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<UserGender>(
                          segments: [
                            ButtonSegment(
                              value: UserGender.male,
                              label: Text(l10n.male),
                              icon: const Icon(Icons.male, size: 18),
                            ),
                            ButtonSegment(
                              value: UserGender.female,
                              label: Text(l10n.female),
                              icon: const Icon(Icons.female, size: 18),
                            ),
                            ButtonSegment(
                              value: UserGender.preferNotToSay,
                              label: Text(l10n.other),
                              icon: const Icon(Icons.help_outline, size: 18),
                            ),
                          ],
                          selected: {prefs.gender},
                          onSelectionChanged: (selection) async {
                            final gender = selection.first;
                            final isMale = gender == UserGender.male;
                            final weight = double.tryParse(
                                  _weightCtrl.text.replaceAll(',', '.'),
                                ) ??
                                prefs.weightKg;
                            final height = double.tryParse(
                                  _heightCtrl.text.replaceAll(',', '.'),
                                ) ??
                                prefs.heightCm;
                            final snappedWeight =
                                GoalDefaults.snapWeightKg(weight);
                            final snappedHeight =
                                GoalDefaults.snapHeightCm(height);
                            final calories = GoalDefaults.caloriesForProfile(
                              prefs.nutritionGoal,
                              weightKg: snappedWeight,
                              heightCm: snappedHeight,
                              muscleMassLevel: prefs.muscleMassLevel,
                              male: isMale,
                            );
                            final macros = GoalDefaults.macroGrams(
                              prefs.nutritionGoal,
                              calories,
                            );
                            setState(() {
                              _weightCtrl.text =
                                  GoalDefaults.formatWeightKg(snappedWeight);
                              _heightCtrl.text =
                                  GoalDefaults.formatHeightCm(snappedHeight);
                              _goalCtrl.text = calories.toString();
                              _carbCtrl.text =
                                  macros.carbG.clamp(15, 500).toString();
                              _proteinCtrl.text =
                                  macros.proteinG.clamp(30, 300).toString();
                              _fatCtrl.text =
                                  macros.fatG.clamp(20, 250).toString();
                            });
                            await ref.read(userPrefsProvider.notifier).update(
                                  prefs.copyWith(
                                    gender: gender,
                                    weightKg: snappedWeight,
                                    heightCm: snappedHeight,
                                    dailyCalorieGoal: calories,
                                    dailyCarbLimitG:
                                        macros.carbG.clamp(15, 500),
                                    dailyProteinTargetG:
                                        macros.proteinG.clamp(30, 300),
                                    dailyFatTargetG: macros.fatG.clamp(20, 250),
                                  ),
                                );
                          },
                          style: SegmentedButton.styleFrom(
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final prefs = ref.watch(userPrefsProvider);
                    final weight = double.tryParse(
                          _weightCtrl.text.replaceAll(',', '.'),
                        ) ??
                        prefs.weightKg;
                    return _WeightSettingsInput(
                      value: weight,
                      onChanged: _setWeightKg,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final prefs = ref.watch(userPrefsProvider);
                    final height = double.tryParse(
                          _heightCtrl.text.replaceAll(',', '.'),
                        ) ??
                        prefs.heightCm;
                    return _BodyProfileSettingsInput(
                      heightCm: height,
                      muscleMassLevel: prefs.muscleMassLevel,
                      onHeightChanged: _setHeightCm,
                      onMuscleChanged: _setMuscleMassLevel,
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(l10n.saveChanges),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.nutritionGoal),
        const SizedBox(height: 12),
        _NutritionGoalPickerCard(
          onTargetsChanged: (calories, macros) {
            setState(() {
              _goalCtrl.text = calories.toString();
              _carbCtrl.text = macros.carbG.clamp(15, 500).toString();
              _proteinCtrl.text = macros.proteinG.clamp(30, 300).toString();
              _fatCtrl.text = macros.fatG.clamp(20, 250).toString();
            });
          },
        ),
        const SizedBox(height: 12),
        const _DietaryRestrictionsCard(),
        const SizedBox(height: 12),
        // Diabetes management card — only shown for Diabetes goal
        Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(userPrefsProvider);
            if (prefs.nutritionGoal != NutritionGoalType.diabetes) {
              return const SizedBox.shrink();
            }
            return const _DiabetesSettingsCard();
          },
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.dailyMacroTargets),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(userPrefsProvider);
            final goalType = prefs.nutritionGoal;
            final calories = prefs.dailyCalorieGoal;
            final r = GoalDefaults.macroRatios(goalType);
            final idealCarb = (calories * r.carb / 4).round();
            final idealProtein = (calories * r.protein / 4).round();
            final idealFat = (calories * r.fat / 9).round();

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsSlider(
                      label: '🍞 Carbs',
                      value:
                          int.tryParse(_carbCtrl.text) ?? prefs.dailyCarbLimitG,
                      min: 15,
                      max: 500,
                      step: 5,
                      unit: 'g / day',
                      color: Colors.amber.shade700,
                      recommendedValue: idealCarb,
                      warningValue: (idealCarb * 1.3).round().clamp(20, 500),
                      dangerValue: (idealCarb * 1.6).round().clamp(30, 500),
                      onChanged: (v) {
                        setState(() => _carbCtrl.text = v.toString());
                        _saveSilent();
                      },
                    ),
                    const SizedBox(height: 12),
                    _SettingsSlider(
                      label: '💪 Protein',
                      value: int.tryParse(_proteinCtrl.text) ??
                          prefs.dailyProteinTargetG,
                      min: 30,
                      max: 300,
                      step: 5,
                      unit: 'g / day',
                      color: Colors.red.shade600,
                      recommendedValue: idealProtein,
                      warningValue: (idealProtein * 1.3).round().clamp(40, 300),
                      dangerValue: (idealProtein * 1.6).round().clamp(50, 300),
                      onChanged: (v) {
                        setState(() => _proteinCtrl.text = v.toString());
                        _saveSilent();
                      },
                    ),
                    const SizedBox(height: 12),
                    _SettingsSlider(
                      label: '🥑 Fat',
                      value:
                          int.tryParse(_fatCtrl.text) ?? prefs.dailyFatTargetG,
                      min: 20,
                      max: 250,
                      step: 5,
                      unit: 'g / day',
                      color: Colors.green.shade600,
                      recommendedValue: idealFat,
                      warningValue: (idealFat * 1.3).round().clamp(25, 250),
                      dangerValue: (idealFat * 1.6).round().clamp(35, 250),
                      onChanged: (v) {
                        setState(() => _fatCtrl.text = v.toString());
                        _saveSilent();
                      },
                    ),
                    const SizedBox(height: 12),
                    // Macro breakdown info
                    Builder(builder: (_) {
                      final carbVal =
                          int.tryParse(_carbCtrl.text) ?? prefs.dailyCarbLimitG;
                      final protVal = int.tryParse(_proteinCtrl.text) ??
                          prefs.dailyProteinTargetG;
                      final fatVal =
                          int.tryParse(_fatCtrl.text) ?? prefs.dailyFatTargetG;
                      final total = carbVal * 4 + protVal * 4 + fatVal * 9;
                      final pct =
                          calories > 0 ? (total / calories * 100).round() : 0;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.isPremiumTheme
                              ? context.primary50
                              : goalType.lightColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: goalType.color.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 14, color: goalType.color),
                            const SizedBox(width: 6),
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
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.waterGoal),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _waterCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.dailyWaterGoalMl,
                    prefixIcon: const Icon(Icons.water_drop_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [1500, 2000, 2500, 3000].map((ml) {
                    return ActionChip(
                      label: Text(
                          '${ml ~/ 1000}.${(ml % 1000) ~/ 100 == 0 ? '0' : (ml % 1000) ~/ 100}L'),
                      onPressed: () =>
                          setState(() => _waterCtrl.text = ml.toString()),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(l10n.saveWaterGoal),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.reminders),
        const SizedBox(height: 12),
        const _RemindersCard(),

        const SizedBox(height: 24),
        _SectionHeader(l10n.aboutSection),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.primary100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tour_outlined, color: context.primary600),
            ),
            title: Text(l10n.replayAppTour,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.replayAppTourSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(userPrefsProvider.notifier).replayAppTutorial();
              ref.read(showTourProvider.notifier).state = true;
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.primary100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.document_scanner_outlined,
                  color: context.primary600),
            ),
            title: Text(l10n.replayScanTutorial,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.replayScanTutorialSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(userPrefsProvider.notifier).replayScanTutorial();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.replayScanTutorialSubtitle)),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.weeklyReview),
        const SizedBox(height: 12),
        Container(
          key: TourKeys.weeklyReviewCard,
          child: const _WeeklyBadgeRecapCard(),
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.vacationMode),
        const SizedBox(height: 12),
        Container(
          key: TourKeys.vacationModeCard,
          child: Consumer(
            builder: (context, ref, _) {
              final vacation =
                  ref.watch(userPrefsProvider.select((p) => p.vacationMode));
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.beach_access_outlined,
                              color: Color(0xFFF57C00)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.vacationMode,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.vacationModeDesc,
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.gray600),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: vacation,
                            onChanged: (v) => ref
                                .read(userPrefsProvider.notifier)
                                .setVacationMode(v),
                          ),
                        ],
                      ),
                      if (vacation) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.amber100.withValues(
                              alpha: context.isPremiumTheme ? 0.18 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.amber500.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.info_outline,
                                  size: 14, color: Color(0xFFF57C00)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '🏖️  Vacation active — your streak is protected.',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFFF57C00)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAppearanceTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(l10n.language),
        const SizedBox(height: 12),
        Consumer(
          builder: (context, ref, _) {
            final current = ref.watch(localeProvider);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: AppLanguage.values.map((lang) {
                    final selected = lang == current;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        leading: Text(lang.flag,
                            style: const TextStyle(fontSize: 22)),
                        title: Text(
                          lang.nativeName,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        trailing: selected
                            ? Icon(Icons.check_circle,
                                color: context.primary500)
                            : null,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        selectedTileColor:
                            context.primary500.withValues(alpha: 0.08),
                        selected: selected,
                        onTap: () {
                          ref.read(localeProvider.notifier).setLanguage(lang);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        _SectionHeader(l10n.textSize),
        const SizedBox(height: 12),
        _TextSizePickerCard(),
        const SizedBox(height: 24),
        _SectionHeader(l10n.mascot),
        const SizedBox(height: 12),
        _MascotPickerCard(),
        const SizedBox(height: 24),
        _SectionHeader(l10n.appColorTheme),
        const SizedBox(height: 12),
        const _ThemeColorPickerCard(),
      ],
    );
  }

  Widget _buildPrivacyTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(l10n.dataAndPrivacy),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dataStoredLocally,
                  style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
                ),
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.phone_iphone,
                  label: l10n.storage,
                  value: l10n.onDeviceOnly,
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.cloud_off,
                  label: l10n.cloudSync,
                  value: l10n.noneLabel,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(l10n.exportDailySummary),
                    onPressed: () => _exportCsv(detailed: false),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text(l10n.exportDetailedData),
                    onPressed: () => _exportCsv(detailed: true),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: Text(
                      l10n.clearAllScanHistory,
                      style: const TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () async {
                      final l10n = AppLocalizations.of(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.clearScanHistory),
                          content: Text(l10n.deleteScanDesc),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: Text(l10n.delete),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        final db = await DatabaseService.instance.database;
                        await db.delete('scan_results');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(AppLocalizations.of(context)
                                    .scanHistoryCleared)),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(l10n.database),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.restaurant_menu,
                  label: l10n.foodDatabaseEntries,
                  value: '$_foodCount',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt),
                    label: Text(l10n.browseFoodDatabase),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FoodDatabaseScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(l10n.cloudSync),
        const SizedBox(height: 12),
        const _CloudSyncCard(),
        const SizedBox(height: 24),
        _SectionHeader(l10n.aboutSection),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pixels to Macros',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.primary700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '100% offline Multi-Food Calorie Scanner\n'
                  'Flutter + ARKit + CoreML',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.gray400,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEvaluationTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(l10n.evaluationTools),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.evaluationToolsDesc,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.gray400,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.science),
                    label: Text(l10n.evaluationDashboard),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EvalDashboardScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(l10n.debug),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Testing tools — reset the app to the initial state.',
                  style: TextStyle(fontSize: 13, color: AppTheme.gray400),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restart_alt, color: Colors.red),
                    label: const Text(
                      'Full App Reset (Testing)',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () async {
                      final l10n = AppLocalizations.of(context);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.resetEntireApp),
                          content: Text(l10n.deleteScanDesc),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.red),
                              child: Text(l10n.resetEverything),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        await DatabaseService.instance.resetAllData();
                        await ref.read(userPrefsProvider.notifier).reset();
                        if (mounted) {
                          // Sign out if auth is active
                          try {
                            if (isSupabaseConfigured) {
                              await supabase.auth.signOut();
                            }
                          } catch (_) {}
                          unawaited(
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) => const OnboardingScreen()),
                              (route) => false,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: context.appTextColor,
      ),
    );
  }
}

// ── Diabetes management card ──────────────────────────────────────────────────

const Color _diabetesBlue = Color(0xFF1976D2);

/// Full diabetes setup: blood-glucose unit, Insulin-to-Carb Ratio (ICR),
/// Insulin Sensitivity Factor (ISF) with a 1800-rule helper, and target
/// blood glucose. All glucose values are stored canonically in mg/dL and
/// only converted at this UI boundary.
class _DiabetesSettingsCard extends ConsumerStatefulWidget {
  const _DiabetesSettingsCard();

  @override
  ConsumerState<_DiabetesSettingsCard> createState() =>
      _DiabetesSettingsCardState();
}

class _DiabetesSettingsCardState extends ConsumerState<_DiabetesSettingsCard> {
  late final TextEditingController _icrCtrl;
  late final TextEditingController _isfCtrl;
  late final TextEditingController _targetCtrl;
  late GlucoseUnit _unit;

  @override
  void initState() {
    super.initState();
    final p = ref.read(userPrefsProvider);
    _unit = p.glucoseUnit;
    _icrCtrl =
        TextEditingController(text: p.icrGramsPerUnit.round().toString());
    _isfCtrl = TextEditingController(
        text: p.insulinSensitivityFactor > 0
            ? _fmtGlucose(p.insulinSensitivityFactor)
            : '');
    _targetCtrl =
        TextEditingController(text: _fmtGlucose(p.targetBloodGlucoseMgdl));
  }

  @override
  void dispose() {
    _icrCtrl.dispose();
    _isfCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  /// Format a canonical mg/dL value as a plain number in the active unit.
  String _fmtGlucose(double mgdl) {
    final v = _unit.fromMgdl(mgdl);
    return _unit == GlucoseUnit.mmoll
        ? v.toStringAsFixed(1)
        : v.round().toString();
  }

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.'));

  void _saveIcr() {
    final v = _parse(_icrCtrl);
    if (v != null && v > 0) ref.read(userPrefsProvider.notifier).setIcr(v);
  }

  void _saveIsf() {
    final v = _parse(_isfCtrl);
    if (v != null && v > 0) {
      ref
          .read(userPrefsProvider.notifier)
          .setInsulinSensitivityFactor(_unit.toMgdl(v));
    }
  }

  void _saveTarget() {
    final v = _parse(_targetCtrl);
    if (v != null && v > 0) {
      ref
          .read(userPrefsProvider.notifier)
          .setTargetBloodGlucose(_unit.toMgdl(v));
    }
  }

  void _changeUnit(GlucoseUnit unit) {
    if (unit == _unit) return;
    ref.read(userPrefsProvider.notifier).setGlucoseUnit(unit);
    final p = ref.read(userPrefsProvider);
    setState(() {
      _unit = unit;
      // Re-render ISF and target in the new unit from canonical mg/dL.
      _isfCtrl.text = p.insulinSensitivityFactor > 0
          ? _fmtGlucose(p.insulinSensitivityFactor)
          : '';
      _targetCtrl.text = _fmtGlucose(p.targetBloodGlucoseMgdl);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = _unit.label;
    return Card(
      color:
          context.isPremiumTheme ? context.primary50 : const Color(0xFFE3F2FD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: context.isPremiumTheme ? context.primary300 : _diabetesBlue,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.medical_services_outlined,
                    color: _diabetesBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'Diabetes Management',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: _diabetesBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Blood-glucose unit ─────────────────────────────────────
            const Text('Blood glucose unit',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gray700)),
            const SizedBox(height: 6),
            SegmentedButton<GlucoseUnit>(
              segments: const [
                ButtonSegment(value: GlucoseUnit.mgdl, label: Text('mg/dL')),
                ButtonSegment(value: GlucoseUnit.mmoll, label: Text('mmol/L')),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => _changeUnit(s.first),
              showSelectedIcon: false,
            ),
            const Divider(height: 28),

            // ── ICR ────────────────────────────────────────────────────
            const Text('Insulin-to-Carb Ratio (ICR)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _diabetesBlue)),
            const SizedBox(height: 4),
            const Text('1 unit of insulin covers how many grams of carbs?',
                style: TextStyle(fontSize: 12, color: AppTheme.gray600)),
            const SizedBox(height: 8),
            _FieldRow(
              controller: _icrCtrl,
              suffix: 'g / unit',
              onSave: _saveIcr,
            ),
            const Divider(height: 28),

            // ── ISF ────────────────────────────────────────────────────
            const Text('Insulin Sensitivity Factor (ISF)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _diabetesBlue)),
            const SizedBox(height: 4),
            Text(
              '1 unit of insulin lowers your blood glucose by how much '
              '($unitLabel)? Used for correction doses.',
              style: const TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 8),
            _FieldRow(
              controller: _isfCtrl,
              suffix: '$unitLabel / unit',
              onSave: _saveIsf,
            ),
            const Divider(height: 28),

            // ── Target BG ──────────────────────────────────────────────
            const Text('Target blood glucose',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _diabetesBlue)),
            const SizedBox(height: 4),
            const Text('Your goal blood glucose for correction calculations.',
                style: TextStyle(fontSize: 12, color: AppTheme.gray600)),
            const SizedBox(height: 8),
            _FieldRow(
              controller: _targetCtrl,
              suffix: unitLabel,
              onSave: _saveTarget,
            ),
            const SizedBox(height: 14),

            // ── Safety warning ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.amber100.withValues(
                  alpha: context.isPremiumTheme ? 0.18 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.amber500.withValues(alpha: 0.38)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      color: Colors.amber.shade800, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Confirm your ICR, ISF and target with your healthcare '
                      'provider and review them regularly — they change over '
                      'time. Always measure your blood glucose correctly and '
                      'double-check every dose before injecting.',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.gray700, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 28),

            // ── Bolus Calculator Mode (safety-gated, OFF by default) ───
            const Text('Bolus Calculator Mode',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _diabetesBlue)),
            const SizedBox(height: 4),
            const Text(
              'An optional, safety-gated insulin estimate. Off by default. '
              'Requires a settings survey, consent, and review every 90 days.',
              style: TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final enabled =
                    ref.watch(insulinSettingsProvider).bolusCalculatorEnabled;
                final available = ref.watch(bolusCalculatorAvailableProvider);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BolusSetupScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.tune, color: _diabetesBlue),
                      label: Text(
                        enabled
                            ? 'Manage Bolus Calculator Mode'
                            : 'Set up Bolus Calculator Mode',
                        style: const TextStyle(color: _diabetesBlue),
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DiabetesReviewScreen(),
                          ),
                        ),
                        icon: Icon(
                          available
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color:
                              available ? AppTheme.green700 : AppTheme.amber700,
                          size: 18,
                        ),
                        label: Text(
                          available
                              ? 'Calculator available — review settings'
                              : 'Review required before use',
                          style: TextStyle(
                            color: available
                                ? AppTheme.green700
                                : AppTheme.amber700,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled numeric input with a Save button used by the diabetes card.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.controller,
    required this.suffix,
    required this.onSave,
  });
  final TextEditingController controller;
  final String suffix;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onEditingComplete: onSave,
            decoration: InputDecoration(
              labelText: suffix,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: onSave,
          style: FilledButton.styleFrom(backgroundColor: _diabetesBlue),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.primary500),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(fontSize: 14, color: context.appTextColor)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.appTextColor,
          ),
        ),
      ],
    );
  }
}

class _WeeklyBadgeRecapCard extends ConsumerWidget {
  const _WeeklyBadgeRecapCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      userPrefsProvider.select((prefs) => prefs.weeklyBadgeRecapEnabled),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.primary100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.workspace_premium_outlined,
                color: context.primary700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Badge Recap',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.appTextColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Show badges earned last week on the first app start of each new week.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appMutedTextColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (value) => ref
                  .read(userPrefsProvider.notifier)
                  .setWeeklyBadgeRecapEnabled(value),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Text size picker ───────────────────────────────────────────────────────────

class _TextSizePickerCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(userPrefsProvider.select((p) => p.fontScale));

    const options = [
      (1.0, 'Normal', Icons.text_fields),
      (1.18, 'Large', Icons.format_size),
      (1.38, 'Extra Large', Icons.text_increase),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Adjust text size throughout the app.',
              style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            Row(
              children: options
                  .map(((double scale, String label, IconData icon) opt) {
                final selected = (fontScale - opt.$1).abs() < 0.01;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(userPrefsProvider.notifier)
                          .setFontScale(opt.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? context.primary100
                              : context.appSurfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? context.primary600
                                : context.appBorderColor,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              opt.$3,
                              size: 18 * opt.$1,
                              color: selected
                                  ? context.primary600
                                  : context.appMutedTextColor,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              opt.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? context.primary700
                                    : context.appMutedTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Live preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appSubtleFillColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.appBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.appMutedTextColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Calories · Protein · Vitamin D',
                    style: TextStyle(fontSize: 14, color: context.appTextColor),
                  ),
                  Text(
                    '285 kcal  /  32 g protein',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appMutedTextColor,
                    ),
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

// ── Nutrition goal picker ──────────────────────────────────────────────────────

class _NutritionGoalPickerCard extends ConsumerWidget {
  const _NutritionGoalPickerCard({this.onTargetsChanged});

  final void Function(
    int calories,
    ({int carbG, int proteinG, int fatG}) macros,
  )? onTargetsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);
    final current = prefs.nutritionGoal;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current.description,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: NutritionGoalType.values.map((goal) {
                final selected = current == goal;
                return ChoiceChip(
                  avatar:
                      Text(goal.emoji, style: const TextStyle(fontSize: 16)),
                  label: Text(goal.label),
                  selected: selected,
                  selectedColor: goal.lightColor,
                  onSelected: (_) async {
                    final calories = GoalDefaults.caloriesForProfile(
                      goal,
                      weightKg: prefs.weightKg,
                      heightCm: prefs.heightCm,
                      muscleMassLevel: prefs.muscleMassLevel,
                      male: prefs.gender == UserGender.male,
                    );
                    final macros = GoalDefaults.macroGrams(goal, calories);
                    final updated = prefs.copyWith(
                      nutritionGoal: goal,
                      dailyCalorieGoal: calories,
                      dailyCarbLimitG: macros.carbG.clamp(15, 500),
                      dailyProteinTargetG: macros.proteinG.clamp(30, 300),
                      dailyFatTargetG: macros.fatG.clamp(20, 250),
                    );
                    onTargetsChanged?.call(calories, macros);
                    await ref.read(userPrefsProvider.notifier).update(updated);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DietaryRestrictionsCard extends ConsumerWidget {
  const _DietaryRestrictionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);
    final selected = prefs.dietaryRestrictions;
    final l10n = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.no_food_outlined,
                    size: 20, color: context.primary600),
                const SizedBox(width: 8),
                Text(
                  l10n.dietaryRestrictions,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.dietaryRestrictionsDesc,
              style: const TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: DietaryRestriction.values.map((restriction) {
                final isSelected = selected.contains(restriction);
                return FilterChip(
                  label: Text(l10n.dietaryRestrictionLabel(restriction.name)),
                  selected: isSelected,
                  selectedColor: context.primary100,
                  checkmarkColor: context.primary700,
                  onSelected: (_) async {
                    final updated = {...selected};
                    if (isSelected) {
                      updated.remove(restriction);
                    } else {
                      updated.add(restriction);
                    }
                    await ref.read(userPrefsProvider.notifier).update(
                          prefs.copyWith(dietaryRestrictions: updated),
                        );
                  },
                );
              }).toList(),
            ),
            if (selected.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...selected.map(
                (restriction) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: context.primary500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${l10n.dietaryRestrictionShortLabel(restriction.name)}: ${l10n.dietaryRestrictionDescription(restriction.name)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.gray600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Mascot picker ─────────────────────────────────────────────────────────────

class _MascotPickerCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MascotPickerCard> createState() => _MascotPickerCardState();
}

class _MascotPickerCardState extends ConsumerState<_MascotPickerCard> {
  String _mascotLabel(MascotType mt, AppLocalizations l10n) {
    switch (mt) {
      case MascotType.auto:
        return l10n.mascotAuto;
      case MascotType.gorilla:
        return l10n.mascotGorilla;
      case MascotType.plant:
        return l10n.mascotPlant;
      case MascotType.flame:
        return l10n.mascotFlame;
      case MascotType.sugar:
        return l10n.mascotSugarCube;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(userPrefsProvider);
    final current = prefs.mascotType;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chooseMascot,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            // Live preview — show all 4 stages
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [0.15, 0.40, 0.65, 0.90].map((p) {
                  return SizedBox(
                    width: 72,
                    child: GoalMascotWidget(
                      goalType: prefs.nutritionGoal,
                      progress: p,
                      stressLevel: p,
                      mascotOverride: current,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MascotType.values.map((mt) {
                final selected = current == mt;
                return ChoiceChip(
                  avatar: Text(mt.emoji, style: const TextStyle(fontSize: 16)),
                  label: Text(_mascotLabel(mt, l10n)),
                  selected: selected,
                  onSelected: (_) async {
                    final updated = prefs.copyWith(mascotType: mt);
                    await ref.read(userPrefsProvider.notifier).update(updated);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Theme color picker ────────────────────────────────────────────────────────

class _ThemeColorPickerCard extends ConsumerWidget {
  const _ThemeColorPickerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(userPrefsProvider);
    final current = prefs.themeColorSeed;
    final premiumSeeds = AppColorSeed.values.where((seed) => seed.isPremium);
    final standardSeeds = AppColorSeed.values.where((seed) => !seed.isPremium);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final columns = constraints.maxWidth >= 780
                    ? 4
                    : constraints.maxWidth >= 560
                        ? 3
                        : constraints.maxWidth >= 340
                            ? 2
                            : 1;
                final tileWidth =
                    (constraints.maxWidth - spacing * (columns - 1)) / columns;

                Widget tilesFor(Iterable<AppColorSeed> seeds) {
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: seeds.map((seed) {
                      return SizedBox(
                        width: tileWidth,
                        child: _ThemePreviewTile(
                          seed: seed,
                          selected: current == seed,
                          onTap: () async {
                            final updated =
                                prefs.copyWith(themeColorSeed: seed);
                            await ref
                                .read(userPrefsProvider.notifier)
                                .update(updated);
                          },
                        ),
                      );
                    }).toList(),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ThemePickerSectionHeader(
                      label: 'Premium',
                      color: context.visualTheme.primaryAccent,
                    ),
                    const SizedBox(height: 8),
                    tilesFor(premiumSeeds),
                    const SizedBox(height: 18),
                    _ThemePickerSectionHeader(
                      label: 'Standard',
                      color: AppTheme.gray500,
                    ),
                    const SizedBox(height: 8),
                    tilesFor(standardSeeds),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePickerSectionHeader extends StatelessWidget {
  const _ThemePickerSectionHeader({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: context.appTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _ThemePreviewTile extends StatefulWidget {
  const _ThemePreviewTile({
    required this.seed,
    required this.selected,
    required this.onTap,
  });

  final AppColorSeed seed;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ThemePreviewTile> createState() => _ThemePreviewTileState();
}

class _ThemePreviewTileState extends State<_ThemePreviewTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration(widget.seed),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ThemePreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _controller.duration = _animationDuration(widget.seed);
    }
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _animationDuration(AppColorSeed seed) {
    switch (seed) {
      case AppColorSeed.aiAurora:
        return const Duration(seconds: 8);
      case AppColorSeed.liquidGlass:
        return const Duration(seconds: 9);
      case AppColorSeed.geminiAI:
      case AppColorSeed.midnightNeon:
      case AppColorSeed.solarFlare:
        return const Duration(seconds: 6);
      default:
        return const Duration(seconds: 1);
    }
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final shouldAnimate = widget.seed.isPremium &&
        TickerMode.valuesOf(context).enabled &&
        !reduceMotion;

    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final seed = widget.seed;
    final premium = seed.isPremium;
    final selected = widget.selected;
    final borderColor = selected
        ? seed.color
        : premium
            ? Colors.white.withValues(alpha: 0.16)
            : AppTheme.gray200;
    final textColor = premium ? Colors.white : AppTheme.gray900;
    final mutedColor = premium ? Colors.white70 : AppTheme.gray600;
    final standardTileFill = Color.alphaBlend(
      seed.color.withValues(alpha: selected ? 0.10 : 0.055),
      Colors.white,
    );
    final radius = BorderRadius.circular(14);

    return Semantics(
      button: true,
      selected: selected,
      label: seed.label,
      child: PremiumMotionSurface(
        enabled: premium,
        borderRadius: radius,
        borderWidth: selected ? 3.6 : 2.6,
        glow: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: premium ? null : standardTileFill,
                gradient: premium
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          seed.surfaceColor,
                          seed.premiumSurfaceColor,
                          Color.alphaBlend(
                            seed.color.withValues(alpha: 0.22),
                            seed.premiumSurfaceColor,
                          ),
                        ],
                      )
                    : null,
                borderRadius: radius,
                border: Border.all(
                    color: borderColor,
                    width: premium
                        ? 2.4
                        : selected
                            ? 2
                            : 1),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: seed.color
                              .withValues(alpha: premium ? 0.22 : 0.16),
                          blurRadius: premium ? 14 : 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _ThemePreviewPainter(
                              seed: seed,
                              progress: _controller.value,
                            ),
                            child: premium && seed == AppColorSeed.liquidGlass
                                ? BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 4,
                                      sigmaY: 4,
                                    ),
                                    child: const SizedBox.expand(),
                                  )
                                : const SizedBox.expand(),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seed.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          seed.shortDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: mutedColor,
                            fontSize: 10.5,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: selected ? seed.color : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? seed.color
                            : (premium
                                ? Colors.white.withValues(alpha: 0.24)
                                : AppTheme.gray300),
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 14)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  const _ThemePreviewPainter({required this.seed, required this.progress});

  final AppColorSeed seed;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (!seed.isPremium) {
      _paintClassic(canvas, size);
      return;
    }

    switch (seed) {
      case AppColorSeed.aiAurora:
        _paintAurora(canvas, size);
        break;
      case AppColorSeed.liquidGlass:
        _paintLiquidGlass(canvas, size);
        break;
      case AppColorSeed.midnightNeon:
        _paintMidnightPulse(canvas, size);
        break;
      case AppColorSeed.geminiAI:
      case AppColorSeed.solarFlare:
        _paintAurora(canvas, size);
        break;
      default:
        _paintClassic(canvas, size);
    }
  }

  void _paintClassic(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          seed.surfaceColor,
          Color.alphaBlend(seed.color.withValues(alpha: 0.08), Colors.white),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    final accent = Paint()..color = seed.color;
    final soft = Paint()..color = seed.color.withValues(alpha: 0.16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.10, size.height * 0.14, size.width * 0.54,
            size.height * 0.12),
        const Radius.circular(12),
      ),
      soft,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.10, size.height * 0.35, size.width * 0.78,
            size.height * 0.40),
        const Radius.circular(14),
      ),
      Paint()
        ..color = Color.alphaBlend(
          seed.color.withValues(alpha: 0.06),
          Colors.white,
        ).withValues(alpha: 0.92),
    );
    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.55),
        size.height * 0.11, accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.49, size.width * 0.34,
            size.height * 0.09),
        const Radius.circular(12),
      ),
      Paint()..color = seed.color.withValues(alpha: 0.52),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.63, size.width * 0.22,
            size.height * 0.06),
        const Radius.circular(12),
      ),
      Paint()..color = seed.color.withValues(alpha: 0.28),
    );
  }

  void _paintAurora(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0B0F17));

    final colors = seed.accentColors;
    for (var i = 0; i < colors.length; i++) {
      final phase = progress * math.pi * 2 + i * 1.35;
      final center = Offset(
        size.width * (0.22 + 0.58 * ((math.sin(phase) + 1) / 2)),
        size.height * (0.20 + 0.55 * ((math.cos(phase * 0.72) + 1) / 2)),
      );
      final radius = size.shortestSide * (0.42 + i * 0.05);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: 0.42),
            colors[i].withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          colors[2].withValues(alpha: 0.48),
          colors[1].withValues(alpha: 0.34),
          Colors.transparent,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..moveTo(0, size.height * 0.60);
    for (var x = 0.0; x <= size.width; x += 8) {
      final y = size.height *
          (0.56 + 0.08 * math.sin(x / size.width * 5 + progress * 2));
      path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);

    _paintPreviewChrome(canvas, size, colors[0], dark: true);
  }

  void _paintLiquidGlass(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1117), Color(0xFF1D2632)],
        ).createShader(rect),
    );

    final shimmerX = size.width * (-0.28 + 1.56 * progress);
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.20),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(shimmerX - 24, 0, 48, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(shimmerX - 18, -8, 36, size.height + 16),
        const Radius.circular(22),
      ),
      shimmerPaint,
    );

    final glassFill = Paint()..color = Colors.white.withValues(alpha: 0.14);
    final glassStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.15, size.width * 0.84,
          size.height * 0.62),
      const Radius.circular(18),
    );
    canvas.drawRRect(panel, glassFill);
    canvas.drawRRect(panel, glassStroke);

    _paintPreviewChrome(canvas, size, const Color(0xFF93C5FD), dark: true);
  }

  void _paintMidnightPulse(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050816), Color(0xFF0B1020)],
        ).createShader(rect),
    );

    final pulse = 0.5 + 0.5 * math.sin(progress * math.pi * 2);
    final center = Offset(size.width * 0.68, size.height * 0.47);
    for (var i = 0; i < 3; i++) {
      final radius = size.shortestSide * (0.18 + i * 0.13 + pulse * 0.035);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color =
              seed.color.withValues(alpha: (0.22 - i * 0.045).clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final tracePaint = Paint()
      ..color = const Color(0xFF22D3EE).withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.10, size.height * 0.64)
      ..lineTo(size.width * 0.32, size.height * 0.64)
      ..cubicTo(size.width * 0.42, size.height * 0.64, size.width * 0.40,
          size.height * 0.35, size.width * 0.52, size.height * 0.35)
      ..lineTo(size.width * 0.86, size.height * 0.35);
    canvas.drawPath(path, tracePaint);

    _paintPreviewChrome(canvas, size, seed.color, dark: true);
  }

  void _paintPreviewChrome(Canvas canvas, Size size, Color accent,
      {required bool dark}) {
    final textPaint = Paint()
      ..color =
          (dark ? Colors.white : AppTheme.gray900).withValues(alpha: 0.86);
    final mutedPaint = Paint()
      ..color =
          (dark ? Colors.white : AppTheme.gray500).withValues(alpha: 0.34);
    final accentPaint = Paint()..color = accent.withValues(alpha: 0.82);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.10, size.height * 0.16, size.width * 0.34,
            size.height * 0.055),
        const Radius.circular(12),
      ),
      textPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.10, size.height * 0.28, size.width * 0.22,
            size.height * 0.045),
        const Radius.circular(12),
      ),
      mutedPaint,
    );
    canvas.drawCircle(Offset(size.width * 0.22, size.height * 0.58),
        size.height * 0.095, accentPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.52, size.width * 0.30,
            size.height * 0.055),
        const Radius.circular(12),
      ),
      textPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.40, size.height * 0.63, size.width * 0.20,
            size.height * 0.045),
        const Radius.circular(12),
      ),
      mutedPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ThemePreviewPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.progress != progress;
  }
}

// ─────────────────────── Cloud Sync Card ───────────────────────

class _CloudSyncCard extends ConsumerWidget {
  const _CloudSyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (!isSupabaseConfigured) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.cloud_off, size: 32, color: AppTheme.gray300),
              const SizedBox(height: 8),
              const Text(
                'Cloud sync not configured yet.\nAdd Supabase credentials to .env to enable.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.gray400, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (!auth.isLoggedIn) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.cloud_outlined, size: 32, color: context.primary500),
              const SizedBox(height: 8),
              const Text(
                'Sign in to sync your scans across devices',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Sign In / Create Account'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: context.primary100,
                  child: Text(
                    auth.displayName[0].toUpperCase(),
                    style: TextStyle(
                      color: context.primary700,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(auth.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(auth.user?.email ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.gray500)),
                    ],
                  ),
                ),
                Icon(Icons.cloud_done, color: Colors.green.shade400, size: 22),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(authProvider.notifier).signOut(),
                    child: const Text('Sign Out'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmDelete(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Delete Account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This will permanently delete your account and all synced data. '
          'Local data on this device will be kept.\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authProvider.notifier).deleteAccount();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _RemindersCard extends StatefulWidget {
  const _RemindersCard();

  @override
  State<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<_RemindersCard> {
  bool _mealReminder = true;
  bool _waterReminder = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query('user_preferences', limit: 1);
    if (rows.isNotEmpty) {
      final row = rows.first;
      if (mounted) {
        setState(() {
          _mealReminder = (row['meal_reminder_enabled'] as int? ?? 1) == 1;
          _waterReminder = (row['water_reminder_enabled'] as int? ?? 1) == 1;
        });
      }
    }
  }

  Future<void> _save() async {
    final db = await DatabaseService.instance.database;
    try {
      await db.update('user_preferences', {
        'meal_reminder_enabled': _mealReminder ? 1 : 0,
        'water_reminder_enabled': _waterReminder ? 1 : 0,
      });
    } catch (_) {
      // Older DBs may not have these columns yet; migration will add them.
    }

    try {
      final prefs = await DatabaseService.instance.getUserPreferences();
      await NotificationService.instance.scheduleReminders(prefs: prefs);
    } catch (_) {
      // Avoid surfacing transient notification scheduling failures in settings UI.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'In-app reminders (coming soon)',
              style: TextStyle(fontSize: 12, color: AppTheme.gray400),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.restaurant_outlined),
              title: const Text('Meal reminder',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Remind me to log meals at 13:00'),
              value: _mealReminder,
              onChanged: (v) {
                setState(() => _mealReminder = v);
                _save();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.water_drop_outlined),
              title: const Text('Water reminder',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Remind me to drink water every 2 hours'),
              value: _waterReminder,
              onChanged: (v) {
                setState(() => _waterReminder = v);
                _save();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightCalibrationCard extends ConsumerWidget {
  const _WeightCalibrationCard({required this.onTargetsChanged});

  final void Function(int calories, double weightKg) onTargetsChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(weightTrackingProvider);
    final latest = state.latest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, color: context.primary600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.adaptiveCalorieCalibration,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _logWeight(context, ref),
                  icon: const Icon(Icons.monitor_weight_outlined, size: 17),
                  label: Text(l10n.logMonthlyWeight),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.adaptiveCalorieCalibrationDesc,
              style: const TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            if (state.lastCalibration != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.primary50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.primary200),
                ),
                child: Text(
                  '${state.lastCalibration!.recommendedCalories} kcal. ${l10n.calorieCalibrationMessage(state.lastCalibration!.messageKey)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.primary700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (state.loading)
              const Center(child: CircularProgressIndicator())
            else if (state.entries.isEmpty)
              Text(
                l10n.noMonthlyWeightsYet,
                style: const TextStyle(fontSize: 12, color: AppTheme.gray500),
              )
            else
              Column(
                children: state.entries.take(4).map((entry) {
                  final isLatest = latest?.id == entry.id;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isLatest
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isLatest ? context.primary600 : AppTheme.gray400,
                    ),
                    title: Text('${entry.weightKg.round()} kg'),
                    subtitle: Text(_formatMonth(entry.recordedAt)),
                    trailing: IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ref
                          .read(weightTrackingProvider.notifier)
                          .deleteEntry(entry),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logWeight(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(userPrefsProvider);
    final controller = TextEditingController(
      text: GoalDefaults.formatWeightKg(prefs.weightKg),
    );

    double? parse() {
      final value = double.tryParse(controller.text.replaceAll(',', '.'));
      if (value == null) return null;
      return GoalDefaults.snapWeightKg(value);
    }

    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logMonthlyWeight),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: 'kg',
            helperText: l10n.monthlyWeightHelper,
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
    if (selected == null) return;
    final result = await ref
        .read(weightTrackingProvider.notifier)
        .logMonthlyWeight(selected);
    onTargetsChanged(result.recommendedCalories, selected);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(l10n.calorieCalibrationMessage(result.messageKey))),
    );
  }

  String _formatMonth(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _WeightSettingsInput extends StatelessWidget {
  const _WeightSettingsInput({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapped = GoalDefaults.snapWeightKg(value);
    final displayWeight = GoalDefaults.formatWeightKg(snapped);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.weightKg,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.gray400,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: snapped <= GoalDefaults.minWeightKg
                  ? null
                  : () => onChanged(snapped - GoalDefaults.weightStepKg),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Tooltip(
                message: l10n.weightKg,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editWeight(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$displayWeight kg',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: context.primary700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 18, color: context.primary500),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: snapped >= GoalDefaults.maxWeightKg
                  ? null
                  : () => onChanged(snapped + GoalDefaults.weightStepKg),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
          ),
          child: Slider(
            value: snapped,
            min: GoalDefaults.minWeightKg,
            max: GoalDefaults.maxWeightKg,
            divisions: ((GoalDefaults.maxWeightKg - GoalDefaults.minWeightKg) /
                    GoalDefaults.weightStepKg)
                .round(),
            activeColor: context.primary600,
            inactiveColor: context.primary200,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${GoalDefaults.minWeightKg.round()} kg',
                style: const TextStyle(fontSize: 11, color: AppTheme.gray400)),
            Text('${GoalDefaults.maxWeightKg.round()} kg',
                style: const TextStyle(fontSize: 11, color: AppTheme.gray400)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.weightEstimateNote,
          style: const TextStyle(fontSize: 12, color: AppTheme.gray500),
        ),
      ],
    );
  }

  Future<void> _editWeight(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: GoalDefaults.formatWeightKg(value));

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

class _BodyProfileSettingsInput extends StatelessWidget {
  const _BodyProfileSettingsInput({
    required this.heightCm,
    required this.muscleMassLevel,
    required this.onHeightChanged,
    required this.onMuscleChanged,
  });

  final double heightCm;
  final MuscleMassLevel muscleMassLevel;
  final ValueChanged<double> onHeightChanged;
  final ValueChanged<MuscleMassLevel> onMuscleChanged;

  @override
  Widget build(BuildContext context) {
    final snappedHeight = GoalDefaults.snapHeightCm(heightCm);
    final displayHeight = GoalDefaults.formatHeightCm(snappedHeight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Height',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.gray400,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: snappedHeight <= GoalDefaults.minHeightCm
                  ? null
                  : () => onHeightChanged(
                        snappedHeight - GoalDefaults.heightStepCm,
                      ),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Tooltip(
                message: 'Height',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editHeight(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$displayHeight cm',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: context.primary700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.edit_outlined,
                            size: 18, color: context.primary500),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: snappedHeight >= GoalDefaults.maxHeightCm
                  ? null
                  : () => onHeightChanged(
                        snappedHeight + GoalDefaults.heightStepCm,
                      ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
          ),
          child: Slider(
            value: snappedHeight,
            min: GoalDefaults.minHeightCm,
            max: GoalDefaults.maxHeightCm,
            divisions: ((GoalDefaults.maxHeightCm - GoalDefaults.minHeightCm) /
                    GoalDefaults.heightStepCm)
                .round(),
            activeColor: context.primary600,
            inactiveColor: context.primary200,
            onChanged: onHeightChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${GoalDefaults.minHeightCm.round()} cm',
                style: const TextStyle(fontSize: 11, color: AppTheme.gray400)),
            Text('${GoalDefaults.maxHeightCm.round()} cm',
                style: const TextStyle(fontSize: 11, color: AppTheme.gray400)),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Muscle amount',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.gray400,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MuscleMassLevel.values.map((level) {
            return ChoiceChip(
              label: Text(level.label),
              selected: muscleMassLevel == level,
              selectedColor: context.primary100,
              onSelected: (_) => onMuscleChanged(level),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          muscleMassLevel.description,
          style: const TextStyle(fontSize: 12, color: AppTheme.gray500),
        ),
        const SizedBox(height: 4),
        const Text(
          'Calories use weight, height, biological sex and muscle amount as a starting estimate, then should be refined from your real weight trend.',
          style: TextStyle(fontSize: 12, color: AppTheme.gray500),
        ),
      ],
    );
  }

  Future<void> _editHeight(BuildContext context) async {
    final controller =
        TextEditingController(text: GoalDefaults.formatHeightCm(heightCm));

    double? parse() {
      final parsed = double.tryParse(controller.text.replaceAll(',', '.'));
      if (parsed == null) return null;
      return GoalDefaults.snapHeightCm(parsed);
    }

    final selected = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Height'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: 'cm',
            helperText:
                '${GoalDefaults.minHeightCm.round()}-${GoalDefaults.maxHeightCm.round()} cm',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, parse()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parse()),
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );

    controller.dispose();
    if (selected != null) onHeightChanged(selected);
  }
}

// ── Settings macro slider (same green→yellow→orange→red as onboarding) ──────

class _SettingsSlider extends StatelessWidget {
  const _SettingsSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.color,
    required this.onChanged,
    this.recommendedValue,
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
  final int? recommendedValue;
  final int? warningValue;
  final int? dangerValue;

  Color get _activeColor {
    if (recommendedValue != null && recommendedValue! > 0) {
      final deviation =
          (value - recommendedValue!).abs() / recommendedValue!.toDouble();
      if (deviation <= 0.15) return Colors.green.shade600;
      if (deviation <= 0.30) return Colors.yellow.shade700;
      if (deviation <= 0.45) return Colors.orange.shade700;
      return Colors.red.shade600;
    }
    if (dangerValue != null && value > dangerValue!) return Colors.red.shade600;
    if (warningValue != null &&
        dangerValue != null &&
        value > (warningValue! + dangerValue!) / 2) {
      return Colors.orange.shade700;
    }
    if (warningValue != null && value > warningValue!)
      return Colors.yellow.shade700;
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
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(
              '$value $unit',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: activeColor,
                  fontSize: 13),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ step,
            activeColor: activeColor,
            inactiveColor: activeColor.withValues(alpha: 0.2),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}
