import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_prefs_provider.dart';
import '../services/data_export_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Profile section ──────────────────────────────────────
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

            // ── Quick presets ────────────────────────────────────────
            _SectionHeader('Quick Goal Presets'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1500, 1800, 2000, 2200, 2500, 3000].map((goal) {
                final isActive =
                    _goalCtrl.text == goal.toString();
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

            // ── Database info ────────────────────────────────────────
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
                      value: '5',
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

            // ── About ────────────────────────────────────────────────
            _SectionHeader('Evaluation'),
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

            const SizedBox(height: 24),

            // ── About ────────────────────────────────────────────────
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
        ),
      ),
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
