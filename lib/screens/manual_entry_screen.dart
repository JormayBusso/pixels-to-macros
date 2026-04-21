import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Manual food entry — pick from the food DB and enter a portion.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  List<FoodData> _allFoods = [];
  List<FoodData> _filtered = [];
  FoodData? _selected;
  final _searchCtrl = TextEditingController();
  final _portionCtrl = TextEditingController(text: '100');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    final foods = await DatabaseService.instance.getAllFoods();
    setState(() {
      _allFoods = foods;
      _filtered = foods;
      _loading = false;
    });
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = _allFoods;
      } else {
        final q = query.toLowerCase();
        _filtered =
            _allFoods.where((f) => f.label.toLowerCase().contains(q)).toList();
      }
    });
  }

  Future<void> _save() async {
    if (_selected == null) return;

    final grams = double.tryParse(_portionCtrl.text) ?? 100;
    // Convert grams to approximate volume using average density
    final avgDensity = (_selected!.densityMin + _selected!.densityMax) / 2;
    final volumeCm3 = grams / avgDensity;

    final range = _selected!.calorieRange(volumeCm3);

    final result = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'manual',
      foods: [
        DetectedFood(
          label: _selected!.label,
          volumeCm3: volumeCm3,
          caloriesMin: range.min,
          caloriesMax: range.max,
        ),
      ],
    );

    await ref.read(historyProvider.notifier).addScan(result);
    await ref.read(dailyIntakeProvider.notifier).load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selected!.label} logged — '
            '${((range.min + range.max) / 2).round()} kcal',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _portionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calPreview = _caloriePreview();

    return Scaffold(
      appBar: AppBar(title: const Text('Log Food Manually')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Search bar ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _filter,
                      decoration: const InputDecoration(
                        hintText: 'Search food...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),

                  // ── Food list ───────────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final food = _filtered[i];
                        final isSelected = _selected?.label == food.label;
                        return Card(
                          color: isSelected ? AppTheme.green50 : null,
                          child: ListTile(
                            leading: _categoryIcon(food.category),
                            title: Text(
                              food.label,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${food.kcalPer100g.round()} kcal / 100g',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.gray400,
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: AppTheme.green600)
                                : null,
                            onTap: () => setState(() => _selected = food),
                          ),
                        );
                      },
                    ),
                  ),

                  // ── Portion + save bar ──────────────────────────────
                  if (_selected != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: AppTheme.green100),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _selected!.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (calPreview != null)
                                Text(
                                  '≈ ${calPreview.round()} kcal',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.green700,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _portionCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    suffixText: 'g',
                                    labelText: 'Portion',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Quick portion buttons
                              ...[50, 100, 150, 200].map((g) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 3),
                                    child: _PortionChip(
                                      grams: g,
                                      active:
                                          _portionCtrl.text == g.toString(),
                                      onTap: () {
                                        _portionCtrl.text = g.toString();
                                        setState(() {});
                                      },
                                    ),
                                  )),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Log Food'),
                              onPressed: _save,
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

  double? _caloriePreview() {
    if (_selected == null) return null;
    final grams = double.tryParse(_portionCtrl.text) ?? 0;
    return _selected!.kcalPer100g * grams / 100;
  }

  Widget _categoryIcon(String category) {
    final (IconData icon, Color color) = switch (category) {
      'fruit' => (Icons.apple, AppTheme.green600),
      'vegetable' => (Icons.grass, AppTheme.green500),
      'grain' => (Icons.grain, AppTheme.amber700),
      'protein' => (Icons.egg, AppTheme.red500),
      'dairy' => (Icons.water_drop, AppTheme.amber500),
      'mixed' => (Icons.restaurant, AppTheme.gray700),
      _ => (Icons.circle, AppTheme.gray400),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      radius: 18,
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _PortionChip extends StatelessWidget {
  const _PortionChip({
    required this.grams,
    required this.active,
    required this.onTap,
  });
  final int grams;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.green200 : AppTheme.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${grams}g',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? AppTheme.green700 : AppTheme.gray700,
          ),
        ),
      ),
    );
  }
}
