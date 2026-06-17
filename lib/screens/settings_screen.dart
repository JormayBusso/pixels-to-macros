import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/glucose_unit.dart';
import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';
import '../providers/user_prefs_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';
import 'eval_dashboard_screen.dart';
import 'food_database_screen.dart';

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
  bool _obscurePassword = true;
  int _foodCount = 0;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPrefsProvider);
    _nameCtrl = TextEditingController(text: prefs.name);
    _goalCtrl = TextEditingController(text: prefs.dailyCalorieGoal.toString());
    _passwordCtrl = TextEditingController();
    _loadFoodCount();
  }

  Future<void> _loadFoodCount() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (mounted) setState(() => _foodCount = foods.length);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final goal = int.tryParse(_goalCtrl.text) ?? 2000;
    final prefs = ref.read(userPrefsProvider).copyWith(
          name: _nameCtrl.text.trim(),
          dailyCalorieGoal: goal.clamp(500, 10000),
        );
    await ref.read(userPrefsProvider.notifier).update(prefs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  Future<void> _exportCsv({required bool detailed}) async {
    final export = DataExportService.instance;
    final csv = detailed
        ? await export.exportToCsv()
        : await export.exportDailySummary();
    await export.copyToClipboard(csv);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.person_outline), text: 'Account'),
              Tab(icon: Icon(Icons.palette_outlined), text: 'Appearance'),
              Tab(icon: Icon(Icons.privacy_tip_outlined), text: 'Privacy'),
              Tab(icon: Icon(Icons.science_outlined), text: 'Evaluation'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Profile'),
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

        _SectionHeader('Nutrition Goal'),
        const SizedBox(height: 12),
        _NutritionGoalPickerCard(),
        const SizedBox(height: 24),

        // ── Diabetes management (only when the goal is Diabetes) ────────
        if (ref.watch(userPrefsProvider).nutritionGoal ==
            NutritionGoalType.diabetes) ...[
          _SectionHeader('Diabetes Management'),
          const SizedBox(height: 12),
          _DiabetesSettingsCard(),
          const SizedBox(height: 24),
        ],

        _SectionHeader('Database'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.restaurant_menu,
                  label: 'Food database entries',
                  value: '$_foodCount',
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.storage,
                  label: 'Database version',
                  value: '12',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Browse Food Database'),
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
      ],
    );
  }

  Widget _buildAppearanceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Mascot'),
        const SizedBox(height: 12),
        _MascotPickerCard(),
        const SizedBox(height: 24),

        _SectionHeader('App Color Theme'),
        const SizedBox(height: 12),
        _ThemeColorPickerCard(),
      ],
    );
  }

  Widget _buildPrivacyTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Data & Privacy'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All data is stored locally on your device. '
                  'No data is sent to any server.',
                  style: TextStyle(fontSize: 13, color: AppTheme.gray600),
                ),
                const SizedBox(height: 16),
                const _InfoRow(
                  icon: Icons.phone_iphone,
                  label: 'Storage',
                  value: 'On-device only',
                ),
                const SizedBox(height: 8),
                const _InfoRow(
                  icon: Icons.cloud_off,
                  label: 'Cloud sync',
                  value: 'None',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Export Daily Summary (CSV)'),
                    onPressed: () => _exportCsv(detailed: false),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Export Detailed Data (CSV)'),
                    onPressed: () => _exportCsv(detailed: true),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader('About'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Evaluation Tools'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Scientific evaluation tools for thesis research.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.gray400,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.science),
                    label: const Text('Evaluation Dashboard'),
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
                  avatar: Text(goal.emoji,
                      style: const TextStyle(fontSize: 16)),
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
                    await ref
                        .read(userPrefsProvider.notifier)
                        .update(updated);
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

// ── Diabetes settings (Insulin-to-Carb Ratio) ────────────────────────────────

class _DiabetesSettingsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DiabetesSettingsCard> createState() =>
      _DiabetesSettingsCardState();
}

class _DiabetesSettingsCardState extends ConsumerState<_DiabetesSettingsCard> {
  late TextEditingController _icrCtrl;
  late TextEditingController _isfCtrl;
  late TextEditingController _targetCtrl;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPrefsProvider);
    final unit = prefs.glucoseUnit;
    _icrCtrl = TextEditingController(
        text: prefs.insulinCarbRatio > 0 ? _fmt(prefs.insulinCarbRatio) : '');
    _isfCtrl = TextEditingController(
        text: prefs.insulinSensitivityFactor > 0
            ? unit.formatValue(prefs.insulinSensitivityFactor)
            : '');
    _targetCtrl = TextEditingController(
        text: unit.formatValue(prefs.targetBloodGlucoseMgdl));
  }

  @override
  void dispose() {
    _icrCtrl.dispose();
    _isfCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double? _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Switch glucose unit and re-format the ISF / target fields to the new unit.
  Future<void> _setUnit(GlucoseUnit unit) async {
    final prefs = ref.read(userPrefsProvider);
    if (prefs.glucoseUnit == unit) return;
    await ref
        .read(userPrefsProvider.notifier)
        .update(prefs.copyWith(glucoseUnit: unit));
    // Re-display stored canonical (mg/dL) values in the freshly-selected unit.
    setState(() {
      if (prefs.insulinSensitivityFactor > 0) {
        _isfCtrl.text = unit.formatValue(prefs.insulinSensitivityFactor);
      }
      _targetCtrl.text = unit.formatValue(prefs.targetBloodGlucoseMgdl);
    });
  }

  Future<void> _saveAll() async {
    final prefs = ref.read(userPrefsProvider);
    final unit = prefs.glucoseUnit;

    // ICR — grams of carb per unit.
    final icrRaw = _parse(_icrCtrl) ?? 0;
    final icr = icrRaw <= 0 ? 0.0 : icrRaw.clamp(1.0, 50.0);

    // ISF — entered in the user's glucose unit, stored canonically as mg/dL.
    final isfRaw = _parse(_isfCtrl);
    final double isfMgdl = (isfRaw == null || isfRaw <= 0)
        ? 0.0
        : unit.toMgdl(isfRaw).clamp(5.0, 200.0);

    // Target blood glucose — entered in unit, stored as mg/dL (clamp 70–200).
    final targetRaw = _parse(_targetCtrl);
    final double targetMgdl = (targetRaw == null || targetRaw <= 0)
        ? 120.0
        : unit.toMgdl(targetRaw).clamp(70.0, 200.0);

    await ref.read(userPrefsProvider.notifier).update(prefs.copyWith(
          insulinCarbRatio: icr,
          insulinSensitivityFactor: isfMgdl,
          targetBloodGlucoseMgdl: targetMgdl,
        ));

    if (mounted) {
      FocusScope.of(context).unfocus();
      // Reflect any clamping back into the fields.
      _targetCtrl.text = unit.formatValue(targetMgdl);
      if (isfMgdl > 0) _isfCtrl.text = unit.formatValue(isfMgdl);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diabetes settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPrefsProvider);
    final unit = prefs.glucoseUnit;
    final icrNotSet = prefs.insulinCarbRatio <= 0;
    final isfNotSet = prefs.insulinSensitivityFactor <= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Warning banners ──────────────────────────────────────────
            if (icrNotSet)
              _warningBanner(
                'Your Insulin-to-Carb Ratio (ICR) is not set. Set it below to '
                'unlock accurate meal insulin dosing and injection-timing '
                'guidance.',
              ),
            if (isfNotSet)
              _warningBanner(
                'Your Insulin Sensitivity Factor (ISF) is not set. Add it to '
                'enable correction doses based on your current blood glucose.',
              ),

            // ── Blood-glucose unit toggle ────────────────────────────────
            const Text(
              'Blood glucose unit',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<GlucoseUnit>(
              segments: const [
                ButtonSegment(
                    value: GlucoseUnit.mgdl, label: Text('mg/dL')),
                ButtonSegment(
                    value: GlucoseUnit.mmoll, label: Text('mmol/L')),
              ],
              selected: {unit},
              onSelectionChanged: (s) => _setUnit(s.first),
            ),
            const SizedBox(height: 20),

            // ── ICR ──────────────────────────────────────────────────────
            const Text(
              'Insulin-to-Carbohydrate Ratio (ICR)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Grams of carbohydrate covered by 1 unit of rapid-acting insulin. '
              'From your management plan — e.g. "1 unit per 10 g".',
              style: TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('1 unit  /  ',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _icrCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: '10',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('g carbs',
                    style: TextStyle(fontSize: 15, color: AppTheme.gray700)),
              ],
            ),
            const SizedBox(height: 20),

            // ── ISF ──────────────────────────────────────────────────────
            const Text(
              'Insulin Sensitivity Factor (ISF)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'How much your blood glucose (${unit.label}) drops per 1 unit of '
              'insulin. Often estimated as 1800 ÷ total daily dose for mg/dL '
              '(100 ÷ TDD for mmol/L) — confirm yours with your doctor.',
              style: const TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('1 unit  ↓  ',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _isfCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: unit == GlucoseUnit.mmoll ? '3' : '50',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(unit.label,
                    style: const TextStyle(
                        fontSize: 15, color: AppTheme.gray700)),
              ],
            ),
            const SizedBox(height: 20),

            // ── Target blood glucose ─────────────────────────────────────
            const Text(
              'Target blood glucose',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'The blood-glucose level corrections aim for. A common default '
              'is 120 mg/dL (6.7 mmol/L) — use the value your doctor set.',
              style: TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _targetCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: unit == GlucoseUnit.mmoll ? '6.7' : '120',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(unit.label,
                    style: const TextStyle(
                        fontSize: 15, color: AppTheme.gray700)),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Diabetes Settings'),
                onPressed: _saveAll,
              ),
            ),
            const SizedBox(height: 12),

            // ── Persistent safety reminder ───────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.amber100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.amber500),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.health_and_safety_outlined,
                      color: AppTheme.amber700, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Review your ICR and ISF with your doctor regularly — they '
                      'change with weight, activity, illness and time. Always '
                      'measure your blood glucose correctly and double-check '
                      'every dose. This app gives educational estimates only and '
                      'does not replace medical advice.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.gray700,
                          height: 1.35),
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

  Widget _warningBanner(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.amber100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.amber500),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppTheme.amber700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: AppTheme.gray700),
            ),
          ),
        ],
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
  @override
  Widget build(BuildContext context) {
    final prefs   = ref.watch(userPrefsProvider);
    final current = prefs.mascotType;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose your companion mascot',
              style: TextStyle(fontSize: 13, color: AppTheme.gray600),
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
                  avatar: Text(mt.emoji,
                      style: const TextStyle(fontSize: 16)),
                  label: Text(mt.label),
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
    final prefs   = ref.watch(userPrefsProvider);
    final current = prefs.themeColorSeed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick an accent color for the whole app',
              style: TextStyle(fontSize: 13, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: AppColorSeed.values.map((seed) {
                final selected = current == seed;
                return GestureDetector(
                  onTap: () async {
                    final updated =
                        prefs.copyWith(themeColorSeed: seed);
                    await ref
                        .read(userPrefsProvider.notifier)
                        .update(updated);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: seed.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppTheme.gray900
                            : Colors.transparent,
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
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 22)
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
