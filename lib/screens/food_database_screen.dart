import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/food_data.dart';
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
    'all', 'fruit', 'vegetable', 'grain', 'protein', 'dairy', 'mixed',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final foods = await DatabaseService.instance.getAllFoods();
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _AddFoodScreen()),
    ).then((_) => _load());
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
                // ── Search ─────────────────────────────────────────────
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

                // ── Category chips ─────────────────────────────────────
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

                // ── Count ──────────────────────────────────────────────
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

                // ── Food list ──────────────────────────────────────────
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
    return Card(
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
                ],
              ),
            ),
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
                const Text(
                  'kcal/100g',
                  style: TextStyle(fontSize: 10, color: AppTheme.gray400),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryBadge(BuildContext context, String category) {
    final (Color bg, Color fg, IconData icon) = switch (category) {
      'fruit' => (context.primary100, context.primary700, Icons.apple),
      'vegetable' => (context.primary100, context.primary600, Icons.grass),
      'grain' => (AppTheme.amber100, AppTheme.amber700, Icons.grain),
      'protein' => (AppTheme.red100, AppTheme.red700, Icons.egg),
      'dairy' => (AppTheme.amber100, AppTheme.amber500, Icons.water_drop),
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

// ── Add custom food screen ──────────────────────────────────────────────────

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
    'fruit', 'vegetable', 'grain', 'protein', 'dairy', 'mixed',
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
              labelText: 'Calories per 100g',
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
          Text(
            'Category',
            style: const TextStyle(
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
