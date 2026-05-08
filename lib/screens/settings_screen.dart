import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mascot_type.dart';
import '../models/nutrition_goal.dart';
import '../models/user_preferences.dart';
import '../providers/scroll_trigger_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/auth_service.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/goal_mascot_widget.dart';
import '../widgets/tour_keys.dart';
import 'auth_screen.dart';
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

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(userPrefsProvider);
    _nameCtrl = TextEditingController(text: prefs.name);
    _goalCtrl = TextEditingController(text: prefs.dailyCalorieGoal.toString());
    _passwordCtrl = TextEditingController();
    _carbCtrl = TextEditingController(text: prefs.dailyCarbLimitG.toString());
    _proteinCtrl = TextEditingController(text: prefs.dailyProteinTargetG.toString());
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
            alignment: 0.12,
          );
        } else if (_accountScrollController.hasClients) {
          _accountScrollController.animateTo(
            650,
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
            alignment: 0.12,
          );
        } else if (_accountScrollController.hasClients) {
          _accountScrollController.animateTo(
            560,
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
      controller: _accountScrollController,
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

        _SectionHeader('Nutrition Goal'),
        const SizedBox(height: 12),
        _NutritionGoalPickerCard(),
        const SizedBox(height: 12),
        // ICR card — only shown for Diabetes goal
        Consumer(
          builder: (context, ref, _) {
            final prefs = ref.watch(userPrefsProvider);
            if (prefs.nutritionGoal != NutritionGoalType.diabetes) {
              return const SizedBox.shrink();
            }
            return _IcrCard(
              currentIcr: prefs.icrGramsPerUnit,
              onChanged: (v) => ref.read(userPrefsProvider.notifier).setIcr(v),
            );
          },
        ),
        const SizedBox(height: 24),

        _SectionHeader('Daily Macro Targets'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _carbCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Carbs (g)',
                          prefixIcon: Icon(Icons.grain),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _proteinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Protein (g)',
                          prefixIcon: Icon(Icons.egg_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _fatCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Fat (g)',
                          prefixIcon: Icon(Icons.opacity),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save Macro Targets'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Water Goal'),
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
                  decoration: const InputDecoration(
                    labelText: 'Daily water goal (ml)',
                    prefixIcon: Icon(Icons.water_drop_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [1500, 2000, 2500, 3000].map((ml) {
                    return ActionChip(
                      label: Text('${ml ~/ 1000}.${(ml % 1000) ~/ 100 == 0 ? '0' : (ml % 1000) ~/ 100}L'),
                      onPressed: () => setState(() => _waterCtrl.text = ml.toString()),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save Water Goal'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Reminders'),
        const SizedBox(height: 12),
        const _RemindersCard(),

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
                  value: '24',
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

        const SizedBox(height: 24),
        _SectionHeader('Cloud Sync'),
        const SizedBox(height: 12),
        const _CloudSyncCard(),

        const SizedBox(height: 24),
        _SectionHeader('About'),
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
            title: const Text('Replay App Tour',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Re-watch the guided feature tour'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ref.read(userPrefsProvider.notifier).replayAppTutorial();
              ref.read(showTourProvider.notifier).state = true;
            },
          ),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Weekly Review'),
        const SizedBox(height: 12),
        Container(
          key: TourKeys.weeklyReviewCard,
          child: const _WeeklyBadgeRecapCard(),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Vacation Mode'),
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
                                const Text('Vacation Mode',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                                const SizedBox(height: 2),
                                const Text(
                                  'Keeps your streak alive while you\'re away.',
                                  style: TextStyle(
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Text Size'),
        const SizedBox(height: 12),
        _TextSizePickerCard(),
        const SizedBox(height: 24),
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text(
                      'Clear All Scan History',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear Scan History?'),
                          content: const Text(
                            'This will permanently delete all your scan records. This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        final db = await DatabaseService.instance.database;
                        await db.delete('scan_results');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Scan history cleared')),
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

// ── ICR (Insulin-to-Carb Ratio) card ─────────────────────────────────────────

class _IcrCard extends StatefulWidget {
  const _IcrCard({required this.currentIcr, required this.onChanged});
  final double currentIcr;
  final ValueChanged<double> onChanged;

  @override
  State<_IcrCard> createState() => _IcrCardState();
}

class _IcrCardState extends State<_IcrCard> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentIcr.round().toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_ctrl.text);
    if (v != null && v > 0) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE3F2FD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1976D2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.vaccines_outlined,
                    color: Color(0xFF1976D2), size: 20),
                SizedBox(width: 8),
                Text(
                  'Insulin-to-Carb Ratio (ICR)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '1 unit of insulin covers how many grams of carbs?',
              style: TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onEditingComplete: _save,
                    decoration: const InputDecoration(
                      labelText: 'g / unit',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2)),
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ Always confirm your ICR with your healthcare provider.',
              style: const TextStyle(fontSize: 11, color: AppTheme.gray600),
            ),
          ],
        ),
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
  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(userPrefsProvider);
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
                  avatar: Text(mt.emoji, style: const TextStyle(fontSize: 16)),
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
    final prefs = ref.watch(userPrefsProvider);
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
                    onPressed: () =>
                        ref.read(authProvider.notifier).signOut(),
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
