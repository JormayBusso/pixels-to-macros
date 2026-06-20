import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../core/app_locale.dart';
import '../models/mascot_type.dart';
import '../models/glucose_unit.dart';
import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../providers/scroll_trigger_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../providers/diabetes_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';
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
    _carbCtrl = TextEditingController(text: prefs.dailyCarbLimitG.toString());
    _proteinCtrl =
        TextEditingController(text: prefs.dailyProteinTargetG.toString());
    _fatCtrl = TextEditingController(text: prefs.dailyFatTargetG.toString());
    _waterCtrl = TextEditingController(text: prefs.dailyWaterGoalMl.toString());
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
    final prefs = ref.read(userPrefsProvider).copyWith(
          name: _nameCtrl.text.trim(),
          dailyCalorieGoal: goal.clamp(500, 10000),
          dailyCarbLimitG: carb.clamp(0, 1000),
          dailyProteinTargetG: protein.clamp(0, 500),
          dailyFatTargetG: fat.clamp(0, 500),
          dailyWaterGoalMl: water.clamp(500, 10000),
        );
    await ref.read(userPrefsProvider.notifier).update(prefs);
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
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _goalCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Daily calorie goal (kcal)',
                    prefixIcon: Icon(Icons.flag_outlined),
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
                        const Text(
                          'Biological sex',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<UserGender>(
                          segments: const [
                            ButtonSegment(
                              value: UserGender.male,
                              label: Text('Male'),
                              icon: Icon(Icons.male, size: 18),
                            ),
                            ButtonSegment(
                              value: UserGender.female,
                              label: Text('Female'),
                              icon: Icon(Icons.female, size: 18),
                            ),
                            ButtonSegment(
                              value: UserGender.preferNotToSay,
                              label: Text('Other'),
                              icon: Icon(Icons.help_outline, size: 18),
                            ),
                          ],
                          selected: {prefs.gender},
                          onSelectionChanged: (selection) {
                            ref
                                .read(userPrefsProvider.notifier)
                                .setGender(selection.first);
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
                    child: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader(l10n.nutritionGoal),
        const SizedBox(height: 12),
        _NutritionGoalPickerCard(),
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
                          color: goalType.lightColor,
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
              child:
                  Icon(Icons.document_scanner_outlined, color: context.primary600),
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
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
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
        _ThemeColorPickerCard(),
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
                                content: Text(AppLocalizations.of(context).scanHistoryCleared)),
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
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const OnboardingScreen()),
                            (route) => false,
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.gray700,
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
    _icrCtrl = TextEditingController(text: p.icrGramsPerUnit.round().toString());
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
      color: const Color(0xFFE3F2FD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _diabetesBlue, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
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
                final enabled = ref
                    .watch(insulinSettingsProvider)
                    .bolusCalculatorEnabled;
                final available =
                    ref.watch(bolusCalculatorAvailableProvider);
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
                          color: available
                              ? AppTheme.green700
                              : AppTheme.amber700,
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
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
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
              style: const TextStyle(fontSize: 14, color: AppTheme.gray700)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.gray900,
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Badge Recap',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gray900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Show badges earned last week on the first app start of each new week.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.gray600,
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
                          color: selected ? context.primary100 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? context.primary600
                                : AppTheme.gray300,
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
                                  : AppTheme.gray400,
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
                                    : AppTheme.gray400,
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
                color: AppTheme.gray100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Preview',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.gray400,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Calories · Protein · Vitamin D',
                    style: TextStyle(fontSize: 14, color: AppTheme.gray700),
                  ),
                  Text(
                    '285 kcal  /  32 g protein',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.gray400,
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
                    final updated = prefs.copyWith(
                      nutritionGoal: goal,
                      dailyCalorieGoal: GoalDefaults.calories(goal),
                      dailyCarbLimitG: GoalDefaults.carbLimitG(goal),
                      dailyProteinTargetG: GoalDefaults.proteinTargetG(goal),
                      dailyFatTargetG: GoalDefaults.fatTargetG(goal),
                    );
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(userPrefsProvider);
    final current = prefs.themeColorSeed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.pickAccentColor,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AppColorSeed.values.map((seed) {
                final selected = current == seed;
                return GestureDetector(
                  onTap: () async {
                    final updated = prefs.copyWith(themeColorSeed: seed);
                    await ref.read(userPrefsProvider.notifier).update(updated);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: seed.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppTheme.gray900 : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: seed.color.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ]
                          : [],
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white, size: 22)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              current.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: current.color,
              ),
            ),
          ],
        ),
      ),
    );
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
