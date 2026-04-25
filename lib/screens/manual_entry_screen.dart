import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../models/serving_config.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/barcode_lookup_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Manual food entry — pick from the food DB, scan a barcode, or enter grams.
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
  double _sliderGrams = 100;

  // Serving-size picker state (for countable foods).
  ServingConfig? _servingConfig;
  int _servingCount = 1;
  int _selectedSizeIndex = 1; // default to medium

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

  void _selectFood(FoodData food) {
    final config = getServingConfig(food.label);
    setState(() {
      _selected = food;
      _servingConfig = config;
      _servingCount = 1;
      _selectedSizeIndex = config != null
          ? (config.sizes.length > 1 ? 1 : 0) // default to medium
          : 0;
      if (config != null) {
        final grams = config.totalGrams(
            _servingCount, config.sizes[_selectedSizeIndex]);
        _portionCtrl.text = grams.round().toString();
        _sliderGrams = grams;
      } else {
        _portionCtrl.text = '100';
        _sliderGrams = 100;
      }
    });
  }

  void _updateServingGrams() {
    if (_servingConfig == null) return;
    final grams = _servingConfig!.totalGrams(
        _servingCount, _servingConfig!.sizes[_selectedSizeIndex]);
    setState(() {
      _portionCtrl.text = grams.round().toString();
      _sliderGrams = grams;
    });
  }

  void _onSliderChanged(double value) {
    setState(() {
      _sliderGrams = value;
      _portionCtrl.text = value.round().toString();
    });
  }

  void _onPortionTextChanged(String text) {
    final grams = double.tryParse(text);
    if (grams != null && grams >= 0 && grams <= 1000) {
      setState(() => _sliderGrams = grams);
    }
  }

  Future<void> _save() async {
    if (_selected == null) return;

    final grams = double.tryParse(_portionCtrl.text) ?? 100;
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

  // ── Barcode scanning ────────────────────────────────────────────────────

  Future<void> _openBarcodeScanner() async {
    // The native Swift side presents its own full-screen scanner UI and
    // performs the OpenFoodFacts lookup using URLSession — no Flutter
    // packages required.
    final result = await BarcodeLookupService.instance.scanAndLookup();
    if (result == null || !mounted) return;

    // Check if food is already in our database.
    final existing =
        await DatabaseService.instance.getFoodByLabel(result.name);
    FoodData food;
    if (existing != null) {
      food = existing;
    } else {
      // Add the barcode food to the database with average density.
      food = FoodData(
        label: result.name,
        densityMin: 0.80,
        densityMax: 1.00,
        kcalPer100g: result.kcalPer100g,
        category: 'mixed',
        proteinPer100g: result.proteinPer100g,
        carbsPer100g: result.carbsPer100g,
        fatPer100g: result.fatPer100g,
      );
      await DatabaseService.instance.insertFood(food);
      // Reload the list.
      await _loadFoods();
      // Re-fetch so we get the id.
      food = (await DatabaseService.instance.getFoodByLabel(result.name)) ??
          food;
    }

    _selectFood(food);

    // Pre-fill serving grams if available from OpenFoodFacts.
    if (result.servingGrams != null) {
      setState(() {
        _portionCtrl.text = result.servingGrams!.round().toString();
        _sliderGrams = result.servingGrams!;
        _servingConfig = null; // barcode overrides serving picker
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found: ${result.name}')),
      );
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
      appBar: AppBar(
        title: const Text('Log Food Manually'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: _openBarcodeScanner,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Search bar ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _filter,
                            decoration: const InputDecoration(
                              hintText: 'Search food...',
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text('Barcode'),
                          onPressed: _openBarcodeScanner,
                        ),
                      ],
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
                          color: isSelected ? context.primary50 : null,
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
                                ? Icon(Icons.check_circle,
                                    color: context.primary600)
                                : null,
                            onTap: () => _selectFood(food),
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
                          top: BorderSide(color: context.primary100),
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
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: context.primary700,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ── Serving picker for countable foods ──────
                          if (_servingConfig != null) ...[
                            _ServingPicker(
                              config: _servingConfig!,
                              count: _servingCount,
                              selectedSizeIndex: _selectedSizeIndex,
                              onCountChanged: (c) {
                                _servingCount = c;
                                _updateServingGrams();
                              },
                              onSizeChanged: (i) {
                                _selectedSizeIndex = i;
                                _updateServingGrams();
                              },
                            ),
                            const SizedBox(height: 8),
                          ],

                          // ── Gram slider ─────────────────────────────
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _portionCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: _onPortionTextChanged,
                                  decoration: const InputDecoration(
                                    suffixText: 'g',
                                    labelText: 'Grams',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Slider(
                                  value: _sliderGrams.clamp(0, 1000),
                                  min: 0,
                                  max: 1000,
                                  divisions: 200,
                                  label: '${_sliderGrams.round()}g',
                                  onChanged: _onSliderChanged,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Quick portion buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [50, 100, 150, 200, 300].map((g) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  child: _PortionChip(
                                    grams: g,
                                    active:
                                        _portionCtrl.text == g.toString(),
                                    onTap: () {
                                      _portionCtrl.text = g.toString();
                                      setState(() => _sliderGrams = g.toDouble());
                                    },
                                  ),
                                )).toList(),
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
      'fruit' => (Icons.apple, context.primary600),
      'vegetable' => (Icons.grass, context.primary500),
      'grain' => (Icons.grain, AppTheme.amber700),
      'protein' => (Icons.egg, AppTheme.red500),
      'dairy' => (Icons.water_drop, AppTheme.amber500),
      'mixed' => (Icons.restaurant, AppTheme.gray700),
      'legume' => (Icons.eco, context.primary700),
      'nut' => (Icons.filter_vintage, AppTheme.amber600),
      'snack' => (Icons.cookie, AppTheme.amber500),
      'drink' => (Icons.local_drink, context.primary400),
      _ => (Icons.circle, AppTheme.gray400),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.12),
      radius: 18,
      child: Icon(icon, size: 18, color: color),
    );
  }
}

// ── Serving picker widget ───────────────────────────────────────────────────

class _ServingPicker extends StatelessWidget {
  const _ServingPicker({
    required this.config,
    required this.count,
    required this.selectedSizeIndex,
    required this.onCountChanged,
    required this.onSizeChanged,
  });

  final ServingConfig config;
  final int count;
  final int selectedSizeIndex;
  final ValueChanged<int> onCountChanged;
  final ValueChanged<int> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Count selector.
        Row(
          children: [
            Text(
              config.countLabel,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 22,
              onPressed: count > 1 ? () => onCountChanged(count - 1) : null,
            ),
            Text(
              '$count',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 22,
              onPressed: count < 20 ? () => onCountChanged(count + 1) : null,
            ),
          ],
        ),
        // Size selector.
        Text(
          config.sizeLabel,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var i = 0; i < config.sizes.length; i++)
              ChoiceChip(
                label: Text(
                  config.sizes[i].label,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: i == selectedSizeIndex,
                onSelected: (_) => onSizeChanged(i),
                selectedColor: context.primary200,
              ),
          ],
        ),
      ],
    );
  }
}

// ── Portion chip ────────────────────────────────────────────────────────────

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
          color: active ? context.primary200 : AppTheme.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${grams}g',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? context.primary700 : AppTheme.gray700,
          ),
        ),
      ),
    );
  }
}
