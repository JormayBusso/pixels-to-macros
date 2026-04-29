import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
import '../models/nutrient_data.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Full food database browser with search, category filter, and add custom food.
class FoodDatabaseScreen extends ConsumerStatefulWidget {
  const FoodDatabaseScreen({super.key});

  @override
  ConsumerState<FoodDatabaseScreen> createState() => _FoodDatabaseScreenState();
}

class _FoodDatabaseScreenState extends ConsumerState<FoodDatabaseScreen> {
  List<FoodData> _allFoods = [];
  List<FoodData> _filtered = [];
  String _searchQuery = '';
  String _selectedCategory = 'all';
  bool _loading = true;

  static const _categories = [
    'all',
    'fruit',
    'vegetable',
    'grain',
    'protein',
    'dairy',
    'mixed',
    'drink',
    'snack',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (!mounted) return;
    setState(() {
      _allFoods = foods;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    setState(() {
      _filtered = _allFoods.where((f) {
        final matchesCategory =
            _selectedCategory == 'all' || f.category == _selectedCategory;
        final matchesSearch = _searchQuery.isEmpty ||
            f.label.toLowerCase().contains(_searchQuery.toLowerCase());
        return matchesCategory && matchesSearch;
      }).toList();
    });
  }

  void _openAddFood() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(builder: (_) => const _AddFoodScreen()),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Database'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add custom food',
            onPressed: _openAddFood,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (q) {
                      _searchQuery = q;
                      _applyFilter();
                    },
                    decoration: const InputDecoration(
                      hintText: 'Search foods...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: _categories.map((cat) {
                      final isActive = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(cat == 'all' ? 'All' : cat),
                          selected: isActive,
                          selectedColor: context.primary200,
                          onSelected: (_) {
                            _selectedCategory = cat;
                            _applyFilter();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '${_filtered.length} foods',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.gray400,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_allFoods.length} total',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.gray400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final food = _filtered[i];
                      return _FoodTile(food: food);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food});

  final FoodData food;

  @override
  Widget build(BuildContext context) {
    final nutrients = nutrientsPer100gForFood(food);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _categoryBadge(context, food.category),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Density: ${food.densityMin}–${food.densityMax} g/cm³',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.gray400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _NutrientPill(label: '${_fmt(food.proteinPer100g)}g P'),
                        _NutrientPill(label: '${_fmt(food.carbsPer100g)}g C'),
                        _NutrientPill(label: '${_fmt(food.fatPer100g)}g F'),
                        if (nutrients.hasAnyValue) ...[
                          _NutrientPill(
                            label: '${_fmt(nutrients.fiberG)}g fiber',
                          ),
                          _NutrientPill(
                            label: '${_fmt(nutrients.vitaminCMg)}mg C',
                          ),
                          _NutrientPill(
                            label: '${_fmt(nutrients.calciumMg)}mg Ca',
                          ),
                          _NutrientPill(
                            label: '${_fmt(nutrients.ironMg)}mg Fe',
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${food.kcalPer100g.round()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: context.primary700,
                    ),
                  ),
                  Text(
                    'kcal/${food.unitLabel}',
                    style:
                        const TextStyle(fontSize: 10, color: AppTheme.gray400),
                  ),
                  const SizedBox(height: 8),
                  Icon(Icons.chevron_right, color: context.primary600),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetails(BuildContext context) {
    final nutrients = nutrientsPer100gForFood(food);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                food.label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'per ${food.unitLabel}',
                style: const TextStyle(color: AppTheme.gray400),
              ),
              const SizedBox(height: 20),
              _DetailSection(
                title: 'Macros',
                rows: [
                  ('Calories', '${_fmt(food.kcalPer100g)} kcal'),
                  ('Protein', '${_fmt(food.proteinPer100g)} g'),
                  ('Carbs', '${_fmt(food.carbsPer100g)} g'),
                  ('Fat', '${_fmt(food.fatPer100g)} g'),
                  ('Fiber', '${_fmt(nutrients.fiberG)} g'),
                  ('Sodium', '${_fmt(nutrients.sodiumMg)} mg'),
                ],
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: 'Vitamins',
                rows: [
                  ('Vitamin A', '${_fmt(nutrients.vitaminAUg)} μg'),
                  ('Vitamin C', '${_fmt(nutrients.vitaminCMg)} mg'),
                  ('Vitamin D', '${_fmt(nutrients.vitaminDUg)} μg'),
                  ('Vitamin E', '${_fmt(nutrients.vitaminEMg)} mg'),
                  ('Vitamin K', '${_fmt(nutrients.vitaminKUg)} μg'),
                  ('Folate', '${_fmt(nutrients.folateMcg)} μg'),
                  ('Vitamin B12', '${_fmt(nutrients.b12Mcg)} μg'),
                ],
              ),
              const SizedBox(height: 16),
              _DetailSection(
                title: 'Minerals',
                rows: [
                  ('Calcium', '${_fmt(nutrients.calciumMg)} mg'),
                  ('Iron', '${_fmt(nutrients.ironMg)} mg'),
                  ('Magnesium', '${_fmt(nutrients.magnesiumMg)} mg'),
                  ('Potassium', '${_fmt(nutrients.potassiumMg)} mg'),
                  ('Zinc', '${_fmt(nutrients.zincMg)} mg'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _fmt(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    if (value >= 10) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  Widget _categoryBadge(BuildContext context, String category) {
    final (Color bg, Color fg, IconData icon) = switch (category) {
      'fruit' => (context.primary100, context.primary700, Icons.apple),
      'vegetable' => (context.primary100, context.primary600, Icons.grass),
      'grain' => (AppTheme.amber100, AppTheme.amber700, Icons.grain),
      'protein' => (AppTheme.red100, AppTheme.red700, Icons.egg),
      'dairy' => (AppTheme.amber100, AppTheme.amber500, Icons.water_drop),
      'drink' => (context.primary100, context.primary700, Icons.local_drink),
      'snack' => (AppTheme.amber100, AppTheme.amber700, Icons.cookie),
      'mixed' => (AppTheme.gray100, AppTheme.gray700, Icons.restaurant),
      _ => (AppTheme.gray100, AppTheme.gray400, Icons.circle),
    };
    return CircleAvatar(
      backgroundColor: bg,
      radius: 20,
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

class _NutrientPill extends StatelessWidget {
  const _NutrientPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.gray700,
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.gray700,
          ),
        ),
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: const TextStyle(color: AppTheme.gray600),
                  ),
                ),
                Text(
                  row.$2,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.gray900,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AddFoodScreen extends StatefulWidget {
  const _AddFoodScreen();

  @override
  State<_AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<_AddFoodScreen> {
  final _labelCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _densityMinCtrl = TextEditingController(text: '0.70');
  final _densityMaxCtrl = TextEditingController(text: '0.90');
  String _category = 'mixed';

  static const _categories = [
    'fruit',
    'vegetable',
    'grain',
    'protein',
    'dairy',
    'mixed',
    'drink',
    'snack',
  ];

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final kcal = double.tryParse(_kcalCtrl.text);
    final dMin = double.tryParse(_densityMinCtrl.text);
    final dMax = double.tryParse(_densityMaxCtrl.text);

    if (label.isEmpty || kcal == null || dMin == null || dMax == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final food = FoodData(
      label: label,
      densityMin: dMin,
      densityMax: dMax,
      kcalPer100g: kcal,
      category: _category,
    );

    await DatabaseService.instance.insertFood(food);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label added to database')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _kcalCtrl.dispose();
    _densityMinCtrl.dispose();
    _densityMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Custom Food')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _labelCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Food name',
              prefixIcon: Icon(Icons.restaurant),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _kcalCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Calories per 100g (or 100ml for drinks)',
              prefixIcon: Icon(Icons.local_fire_department),
              suffixText: 'kcal',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _densityMinCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Density min',
                    suffixText: 'g/cm³',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _densityMaxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Density max',
                    suffixText: 'g/cm³',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Category',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              return ChoiceChip(
                label: Text(cat),
                selected: _category == cat,
                selectedColor: context.primary200,
                onSelected: (_) => setState(() => _category = cat),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Food'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
