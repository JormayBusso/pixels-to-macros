import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_meal.dart';
import '../models/food_data.dart';
import '../services/barcode_lookup_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Screen to create or edit a [CustomMeal].
///
/// Pass an existing [meal] to edit it; pass null to create a new one.
class CreateMealScreen extends ConsumerStatefulWidget {
  const CreateMealScreen({super.key, this.meal});

  final CustomMeal? meal;

  @override
  ConsumerState<CreateMealScreen> createState() => _CreateMealScreenState();
}

class _CreateMealScreenState extends ConsumerState<CreateMealScreen> {
  final _nameCtrl = TextEditingController();
  MealType _mealType = MealType.lunch;

  // Ingredient list being built: food + grams
  final List<_IngredientEntry> _ingredients = [];

  // Food database for search
  List<FoodData> _allFoods = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final foods = await DatabaseService.instance.getAllFoods();
    final meal = widget.meal;
    setState(() {
      _allFoods = foods;
      _loading = false;
      if (meal != null) {
        _nameCtrl.text = meal.name;
        _mealType = meal.mealType;
        for (final ing in meal.ingredients) {
          _ingredients.add(_IngredientEntry(
            label: ing.foodLabel,
            grams: ing.grams,
          ));
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _removeIngredient(int index) {
    setState(() => _ingredients.removeAt(index));
  }

  void _showAddIngredientSheet() {
    _searchCtrl.clear();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddIngredientSheet(
        foods: _allFoods,
        existingLabels: _ingredients.map((e) => e.label).toSet(),
        onAdded: (label, grams) {
          setState(() {
            _ingredients.add(_IngredientEntry(label: label, grams: grams));
          });
        },
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter a meal name.')));
      return;
    }
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one ingredient.')));
      return;
    }

    setState(() => _saving = true);

    final ingredients = _ingredients
        .map((e) => MealIngredient(
              mealId: widget.meal?.id ?? 0,
              foodLabel: e.label,
              grams: e.grams,
            ))
        .toList();

    if (widget.meal == null) {
      final meal = CustomMeal(
        name: name,
        mealType: _mealType,
        createdAt: DateTime.now(),
      );
      await DatabaseService.instance.insertCustomMeal(meal, ingredients);
    } else {
      final updated = widget.meal!.copyWith(name: name, mealType: _mealType);
      await DatabaseService.instance.updateCustomMeal(updated, ingredients);
    }

    setState(() => _saving = false);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.meal != null;

    // Compute total kcal preview
    final kcalMap = {for (final f in _allFoods) f.label: f.kcalPer100g};
    final totalKcal = _ingredients.fold<double>(
        0, (sum, e) => sum + (kcalMap[e.label] ?? 0) * e.grams / 100.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Meal' : 'Create Meal'),
        actions: [
          if (_saving)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
              children: [
                // ── Meal name + type ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Meal name',
                          hintText: 'e.g. My morning oatmeal',
                          prefixIcon: Icon(Icons.restaurant_menu),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Meal type chips
                      Row(
                        children: MealType.values.map((type) {
                          final selected = _mealType == type;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_mealTypeIcon(type),
                                      size: 14,
                                      color: selected
                                          ? context.primary700
                                          : AppTheme.gray400),
                                  const SizedBox(width: 4),
                                  Text(type.displayName),
                                ],
                              ),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _mealType = type),
                              selectedColor: context.primary100,
                              checkmarkColor: context.primary700,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                // ── Ingredient list ───────────────────────────────────
                Expanded(
                  child: _ingredients.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_shopping_cart_outlined,
                                  size: 48, color: AppTheme.gray300),
                              const SizedBox(height: 8),
                              Text('No ingredients yet',
                                  style: TextStyle(
                                      color: AppTheme.gray400,
                                      fontSize: 15)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          itemCount: _ingredients.length,
                          onReorder: (oldIndex, newIndex) {
                            setState(() {
                              if (newIndex > oldIndex) newIndex--;
                              final item = _ingredients.removeAt(oldIndex);
                              _ingredients.insert(newIndex, item);
                            });
                          },
                          itemBuilder: (ctx, i) {
                            final entry = _ingredients[i];
                            final kcal = (kcalMap[entry.label] ?? 0) *
                                entry.grams /
                                100.0;
                            return Card(
                              key: ValueKey('$i-${entry.label}'),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                title: Text(entry.label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${entry.grams.round()} g  •  ${kcal.round()} kcal'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Grams edit
                                    SizedBox(
                                      width: 64,
                                      child: _GramsField(
                                        initialGrams: entry.grams,
                                        onChanged: (g) =>
                                            setState(() => entry.grams = g),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 18, color: AppTheme.gray400),
                                      onPressed: () => _removeIngredient(i),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // ── Bottom bar: total + add ───────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        top: BorderSide(color: context.primary100)),
                  ),
                  child: Row(
                    children: [
                      if (_ingredients.isNotEmpty)
                        Expanded(
                          child: Text(
                            'Total: ${totalKcal.round()} kcal  •  '
                            '${_ingredients.length} ingredient${_ingredients.length == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.primary700),
                          ),
                        )
                      else
                        const Expanded(child: SizedBox()),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Ingredient'),
                        onPressed: _showAddIngredientSheet,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  IconData _mealTypeIcon(MealType type) => switch (type) {
        MealType.breakfast => Icons.wb_sunny_outlined,
        MealType.lunch => Icons.wb_cloudy_outlined,
        MealType.dinner => Icons.nights_stay_outlined,
      };
}

// ── Mutable ingredient entry ───────────────────────────────────────────────

class _IngredientEntry {
  String label;
  double grams;

  _IngredientEntry({required this.label, required this.grams});
}

// ── Inline grams field ────────────────────────────────────────────────────

class _GramsField extends StatefulWidget {
  const _GramsField(
      {required this.initialGrams, required this.onChanged});

  final double initialGrams;
  final ValueChanged<double> onChanged;

  @override
  State<_GramsField> createState() => _GramsFieldState();
}

class _GramsFieldState extends State<_GramsField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialGrams.round().toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: const InputDecoration(
        suffixText: 'g',
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      onChanged: (v) {
        final g = double.tryParse(v);
        if (g != null && g > 0) widget.onChanged(g);
      },
    );
  }
}

// ── Add ingredient bottom sheet ───────────────────────────────────────────

class _AddIngredientSheet extends StatefulWidget {
  const _AddIngredientSheet({
    required this.foods,
    required this.existingLabels,
    required this.onAdded,
  });

  final List<FoodData> foods;
  final Set<String> existingLabels;
  final void Function(String label, double grams) onAdded;

  @override
  State<_AddIngredientSheet> createState() => _AddIngredientSheetState();
}

class _AddIngredientSheetState extends State<_AddIngredientSheet> {
  final _searchCtrl = TextEditingController();
  final _gramsCtrl = TextEditingController(text: '100');
  List<FoodData> _filtered = [];
  FoodData? _selected;

  @override
  void initState() {
    super.initState();
    _filtered = List.of(widget.foods);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _gramsCtrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? List.of(widget.foods)
          : widget.foods
              .where((f) => f.label.toLowerCase().contains(q.toLowerCase()))
              .toList();
    });
  }

  Future<void> _scanBarcode() async {
    // Connectivity check
    try {
      final result = await InternetAddress.lookup('world.openfoodfacts.org')
          .timeout(const Duration(seconds: 3));
      if (result.isEmpty || result[0].rawAddress.isEmpty) throw Exception();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barcode scanning requires internet.')),
      );
      return;
    }

    final result = await BarcodeLookupService.instance.scanAndLookup();
    if (result == null || !mounted) return;

    // Add to DB if not already present
    var existing = await DatabaseService.instance.getFoodByLabel(result.name);
    if (existing == null) {
      final lowerName = result.name.toLowerCase();
      final isDrink = const [
        'water', 'juice', 'drink', 'cola', 'soda', 'milk', 'tea', 'coffee',
      ].any((kw) => lowerName.contains(kw));

      final food = FoodData(
        label: result.name,
        densityMin: isDrink ? 0.99 : 0.80,
        densityMax: isDrink ? 1.05 : 1.00,
        kcalPer100g: result.kcalPer100g,
        category: isDrink ? 'drink' : 'mixed',
        proteinPer100g: result.proteinPer100g,
        carbsPer100g: result.carbsPer100g,
        fatPer100g: result.fatPer100g,
        perMl: isDrink,
        fiberPer100g: result.fiberPer100g,
        sugarsPer100g: result.sugarsPer100g,
        saturatedFatPer100g: result.saturatedFatPer100g,
        sodiumMgPer100g: result.sodiumMgPer100g,
      );
      await DatabaseService.instance.insertFood(food);
      existing = await DatabaseService.instance.getFoodByLabel(result.name);
    }

    if (!mounted) return;
    final grams = result.servingGrams ?? 100.0;
    widget.onAdded(result.name, grams);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.85;
    return SizedBox(
      height: maxH,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: AppTheme.gray200,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Text('Add Ingredient',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            // Search + barcode
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _filter,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search food…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan barcode',
                  onPressed: _scanBarcode,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final food = _filtered[i];
                  final alreadyAdded =
                      widget.existingLabels.contains(food.label);
                  final isSelected = _selected?.label == food.label;
                  return ListTile(
                    dense: true,
                    title: Text(food.label,
                        style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: alreadyAdded ? AppTheme.gray400 : null)),
                    subtitle: Text(
                        '${food.kcalPer100g.round()} kcal / ${food.unitLabel}'),
                    trailing: alreadyAdded
                        ? const Icon(Icons.check, color: AppTheme.gray400,
                            size: 18)
                        : isSelected
                            ? Icon(Icons.check_circle,
                                color: context.primary600)
                            : null,
                    onTap: alreadyAdded
                        ? null
                        : () => setState(() => _selected = food),
                  );
                },
              ),
            ),
            // Grams + confirm (shown when something is selected)
            if (_selected != null) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(_selected!.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _gramsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        suffixText: _selected!.perMl ? 'ml' : 'g',
                        labelText: _selected!.perMl ? 'ml' : 'g',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      final g =
                          double.tryParse(_gramsCtrl.text) ?? 100.0;
                      widget.onAdded(_selected!.label, g);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
