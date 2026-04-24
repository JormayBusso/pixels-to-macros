import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';
import '../providers/user_prefs_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';
import 'debug_screen.dart';
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
  int _foodCount = 0;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPrefsProvider);
    _nameCtrl = TextEditingController(text: prefs.name);
    _goalCtrl = TextEditingController(text: prefs.dailyCalorieGoal.toString());
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
        body: SafeArea(
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
                  decoration: const InputDecoration(
                    labelText: 'Daily calorie goal (kcal)',
                    prefixIcon: Icon(Icons.flag_outlined),
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

        _SectionHeader('Quick Goal Presets'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1500, 1800, 2000, 2200, 2500, 3000].map((goal) {
            final isActive = _goalCtrl.text == goal.toString();
            return ChoiceChip(
              label: Text('$goal'),
              selected: isActive,
              selectedColor: AppTheme.green200,
              onSelected: (_) {
                setState(() => _goalCtrl.text = goal.toString());
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Nutrition Goal'),
        const SizedBox(height: 12),
        _NutritionGoalPickerCard(),
        const SizedBox(height: 24),

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
              children: const [
                Text(
                  'Pixels to Macros',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.green700,
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
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.bug_report),
                    label: const Text('Debug Log'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DebugScreen(),
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
        Icon(icon, size: 18, color: AppTheme.green500),
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
