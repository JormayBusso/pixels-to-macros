import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_meal.dart';
import '../models/food_data.dart';
import '../models/nutrition_goal.dart';
import '../models/scan_result.dart';
import '../models/serving_config.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/barcode_lookup_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'create_meal_screen.dart';

/// Manual food entry — pick from the food DB, scan a barcode, or enter grams.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  List<FoodData> _allFoods = [];
  List<FoodData> _filtered = [];
  final Set<String> _selectedLabels = {};
  FoodData? _activeFood; // the food currently being configured in bottom panel
  final _searchCtrl = TextEditingController();
  final _portionCtrl = TextEditingController(text: '100');
  bool _loading = true;
  double _sliderGrams = 100;

  // Per-food gram overrides: label → grams
  final Map<String, double> _gramsOverrides = {};

  // Serving-size picker state (for countable foods).
  ServingConfig? _servingConfig;
  int _servingCount = 1;
  int _selectedSizeIndex = 1; // default to medium

  // ── Meals mode ──────────────────────────────────────────────────────────
  bool _showMeals = false;
  List<CustomMeal> _meals = [];

  @override
  void initState() {
    super.initState();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    final foods = await DatabaseService.instance.getAllFoods();
    final meals = await DatabaseService.instance.getCustomMeals();
    setState(() {
      _allFoods = foods;
      _filtered = foods;
      _meals = meals;
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
    setState(() {
      if (_selectedLabels.contains(food.label)) {
        // Deselect
        _selectedLabels.remove(food.label);
        _gramsOverrides.remove(food.label);
        if (_activeFood?.label == food.label) {
          _activeFood = null;
          _servingConfig = null;
        }
      } else {
        // Add to selection
        _selectedLabels.add(food.label);
        _gramsOverrides[food.label] = 100;
      }
      // Always make the last-tapped food the active one for gram adjustment
      if (_selectedLabels.contains(food.label)) {
        _activeFood = food;
        final config = getServingConfig(food.label);
        _servingConfig = config;
        _servingCount = 1;
        _selectedSizeIndex = config != null
            ? (config.sizes.length > 1 ? 1 : 0)
            : 0;
        if (config != null) {
          final grams = config.totalGrams(
              _servingCount, config.sizes[_selectedSizeIndex]);
          _portionCtrl.text = grams.round().toString();
          _sliderGrams = grams;
          _gramsOverrides[food.label] = grams;
        } else {
          final g = _gramsOverrides[food.label] ?? 100;
          _portionCtrl.text = g.round().toString();
          _sliderGrams = g;
        }
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
      if (_activeFood != null) {
        _gramsOverrides[_activeFood!.label] = grams;
      }
    });
  }

  void _onSliderChanged(double value) {
    setState(() {
      _sliderGrams = value;
      _portionCtrl.text = value.round().toString();
      if (_activeFood != null) {
        _gramsOverrides[_activeFood!.label] = value;
      }
    });
  }

  void _onPortionTextChanged(String text) {
    final grams = double.tryParse(text);
    if (grams != null && grams >= 0 && grams <= 1000) {
      setState(() {
        _sliderGrams = grams;
        if (_activeFood != null) {
          _gramsOverrides[_activeFood!.label] = grams;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_selectedLabels.isEmpty) return;

    // Save active food's current grams
    if (_activeFood != null) {
      _gramsOverrides[_activeFood!.label] =
          double.tryParse(_portionCtrl.text) ?? 100;
    }

    final detectedFoods = <DetectedFood>[];
    int totalCal = 0;

    for (final label in _selectedLabels) {
      final food = _allFoods.firstWhere((f) => f.label == label,
          orElse: () => _allFoods.first);
      final grams = _gramsOverrides[label] ?? 100;
      final avgDensity = (food.densityMin + food.densityMax) / 2;
      final volumeCm3 = grams / avgDensity;
      final range = food.calorieRange(volumeCm3);
      detectedFoods.add(DetectedFood(
        label: food.label,
        volumeCm3: volumeCm3,
        caloriesMin: range.min,
        caloriesMax: range.max,
      ));
      totalCal += ((range.min + range.max) / 2).round();
    }

    final result = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'manual',
      foods: detectedFoods,
    );

    await ref.read(historyProvider.notifier).addScan(result);
    await ref.read(dailyIntakeProvider.notifier).load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedLabels.length} item${_selectedLabels.length > 1 ? 's' : ''} logged — '
            '$totalCal kcal',
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  // ── Meal logging ────────────────────────────────────────────────────────

  /// Quick-log a drink (water, juice, etc.) by volume in ml.
  Future<void> _quickLogDrink(String label, double ml) async {
    // Look up food entry (prefer 'water' entry or match by label).
    FoodData food;
    try {
      food = _allFoods.firstWhere(
          (f) => f.label.toLowerCase() == label.toLowerCase());
    } catch (_) {
      // Water fallback: 0 kcal, density ≈ 1 g/ml
      food = FoodData(
        label: label,
        densityMin: 1.0,
        densityMax: 1.0,
        kcalPer100g: 0,
        category: 'drink',
        perMl: true,
      );
    }
    final avgDensity = (food.densityMin + food.densityMax) / 2;
    final volumeCm3 = ml / avgDensity;
    final range = food.calorieRange(volumeCm3);
    final result = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'manual',
      foods: [
        DetectedFood(
          label: food.label,
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
        SnackBar(content: Text('${ml.round()} ml $label logged')),
      );
    }
  }

  /// Show the "Quick Drink" bottom sheet with glass presets + custom ml.
  Future<void> _showDrinkSheet() {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DrinkSheet(
        onLog: (label, ml) {
          Navigator.of(ctx).pop();
          _quickLogDrink(label, ml);
        },
      ),
    );
  }

  Future<void> _logMeal(CustomMeal meal) async {
    if (meal.ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This meal has no ingredients.')));
      return;
    }

    final detectedFoods = <DetectedFood>[];
    int totalCal = 0;
    double totalCarbs = 0;

    for (final ing in meal.ingredients) {
      final food = _allFoods.firstWhere(
        (f) => f.label.toLowerCase() == ing.foodLabel.toLowerCase(),
        orElse: () => FoodData(
          label: ing.foodLabel,
          densityMin: 0.90,
          densityMax: 1.00,
          kcalPer100g: 0,
          category: 'mixed',
        ),
      );
      final avgDensity = (food.densityMin + food.densityMax) / 2;
      final volumeCm3 = ing.grams / avgDensity;
      final range = food.calorieRange(volumeCm3);
      detectedFoods.add(DetectedFood(
        label: food.label,
        volumeCm3: volumeCm3,
        caloriesMin: range.min,
        caloriesMax: range.max,
      ));
      totalCal += ((range.min + range.max) / 2).round();
      totalCarbs += food.carbsPer100g * ing.grams / 100.0;
    }

    // Show bolus sheet for diabetic users before logging.
    final prefs = ref.read(userPrefsProvider);
    if (prefs.nutritionGoal == NutritionGoalType.diabetes &&
        totalCarbs > 0 &&
        mounted) {
      final proceed = await _showMealBolusSheet(
        mealName: meal.name,
        totalCarbs: totalCarbs,
        icr: prefs.icrGramsPerUnit,
      );
      if (proceed != true || !mounted) return;
    }

    final result = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'manual',
      foods: detectedFoods,
    );

    await ref.read(historyProvider.notifier).addScan(result);
    await ref.read(dailyIntakeProvider.notifier).load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${meal.name} logged — $totalCal kcal'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// Show the bolus calculation bottom sheet.
  /// Returns true when user taps "Log Meal", false/null on dismiss.
  Future<bool?> _showMealBolusSheet({
    required String mealName,
    required double totalCarbs,
    required double icr,
  }) {
    final bolus = (totalCarbs / icr * 10).round() / 10; // round to 0.1
    return showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Meal Coverage for: $mealName',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _BolusRow(icon: Icons.grain, label: 'Carbohydrates', value: '${totalCarbs.toStringAsFixed(1)} g'),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1976D2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vaccines_outlined,
                      color: Color(0xFF1976D2), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested Meal Bolus: $bolus units',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        Text(
                          '${totalCarbs.toStringAsFixed(1)} g ÷ $icr g/unit',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF1976D2)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️  This dose only covers the carbs in this meal. It does '
                'not include a correction bolus. Always verify with your '
                'healthcare provider.',
                style: TextStyle(fontSize: 11, color: AppTheme.gray700),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Log Meal'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Barcode scanning ────────────────────────────────────────────────────

  Future<void> _openBarcodeScanner() async {
    // The native Swift side presents its own full-screen scanner UI and
    // performs the OpenFoodFacts lookup using URLSession — no Flutter
    // packages required.
    final themeColor = context.primary500;
    final result = await BarcodeLookupService.instance.scanAndLookup(themeColor: themeColor);
    if (result == null || !mounted) return;

    // Check if food is already in our database.
    final existing =
        await DatabaseService.instance.getFoodByLabel(result.name);
    FoodData food;
    if (existing != null) {
      food = existing;
    } else {
      // Heuristic: treat as a drink if the name contains common beverage words.
      final lowerName = result.name.toLowerCase();
      final isDrink = const [
        'water', 'juice', 'drink', 'cola', 'soda', 'beer', 'wine', 'milk',
        'tea', 'coffee', 'smoothie', 'shake', 'lemonade', 'espresso', 'latte',
        'beverage', 'nectar', 'syrup', 'liqueur', 'spirit', 'cocktail',
      ].any((kw) => lowerName.contains(kw));

      // Add the barcode food to the database with all available nutrients.
      food = FoodData(
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
        cholesterolMgPer100g: result.cholesterolMgPer100g,
        vitaminAUgPer100g: result.vitaminAUgPer100g,
        vitaminCMgPer100g: result.vitaminCMgPer100g,
        vitaminDUgPer100g: result.vitaminDUgPer100g,
        vitaminEMgPer100g: result.vitaminEMgPer100g,
        vitaminKUgPer100g: result.vitaminKUgPer100g,
        vitaminB12UgPer100g: result.vitaminB12UgPer100g,
        folateUgPer100g: result.folateUgPer100g,
        calciumMgPer100g: result.calciumMgPer100g,
        ironMgPer100g: result.ironMgPer100g,
        magnesiumMgPer100g: result.magnesiumMgPer100g,
        potassiumMgPer100g: result.potassiumMgPer100g,
        zincMgPer100g: result.zincMgPer100g,
      );
      await DatabaseService.instance.insertFood(food);
      // Reload the list.
      await _loadFoods();
      // Re-fetch so we get the id.
      food = (await DatabaseService.instance.getFoodByLabel(result.name)) ??
          food;
    }

    // Health score sheet handles _selectFood + serving pre-fill via its buttons.
    if (mounted) {
      await _showBarcodeHealthSheet(food: food, servingGrams: result.servingGrams);
    }
  }

  /// Compute a 0-100 health score for a barcode food.
  /// Based on: low sat-fat/sugars/sodium = good; high fiber/protein/vitamins = good.
  int _healthScore(FoodData food) {
    double score = 50; // start neutral

    // Good contributors (add points)
    score += (food.fiberPer100g * 4).clamp(0, 20);           // fiber: up to +20
    score += (food.proteinPer100g * 0.5).clamp(0, 15);       // protein: up to +15
    score += ((food.vitaminCMgPer100g / 90) * 5).clamp(0, 5); // vit C
    score += ((food.calciumMgPer100g / 1000) * 5).clamp(0, 5); // calcium

    // Bad contributors (subtract points)
    score -= (food.sugarsPer100g * 0.8).clamp(0, 25);         // sugars: up to -25
    score -= (food.saturatedFatPer100g * 1.5).clamp(0, 20);   // sat fat: up to -20
    score -= ((food.sodiumMgPer100g / 2300) * 15).clamp(0, 15); // sodium: up to -15
    if (food.kcalPer100g > 400) score -= 10;                   // dense energy penalty

    return score.round().clamp(0, 100);
  }

  Future<void> _showBarcodeHealthSheet({
    required FoodData food,
    double? servingGrams,
  }) {
    final score = _healthScore(food);
    final Color scoreColor;
    final String label;
    if (score >= 70) {
      scoreColor = const Color(0xFF388E3C);
      label = 'Healthy';
    } else if (score >= 40) {
      scoreColor = const Color(0xFFF57C00);
      label = 'Moderate';
    } else {
      scoreColor = const Color(0xFFD32F2F);
      label = 'Unhealthy';
    }
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(food.label,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              '${food.kcalPer100g.round()} kcal  •  ${food.proteinPer100g.round()} g protein  •  '
              '${food.carbsPer100g.round()} g carbs  •  ${food.fatPer100g.round()} g fat',
              style: const TextStyle(fontSize: 12, color: AppTheme.gray600),
            ),
            const SizedBox(height: 16),
            // ── Health score bar ──────────────────────────────────────
            Row(
              children: [
                const Text('Unhealthy',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400)),
                const Spacer(),
                const Text('Healthy',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFD32F2F),
                          Color(0xFFFFA726),
                          Color(0xFF388E3C),
                        ],
                      ),
                    ),
                  ),
                  // Indicator
                  FractionallySizedBox(
                    widthFactor: (score / 100.0),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 14,
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: scoreColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$score / 100',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _selectFood(food);
                      if (servingGrams != null) {
                        setState(() {
                          _portionCtrl.text = servingGrams.round().toString();
                          _sliderGrams = servingGrams;
                          _gramsOverrides[food.label] = servingGrams;
                        });
                      }
                    },
                    child: const Text('Add to Log'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
    final prefs = ref.watch(userPrefsProvider);
    final isDiabetic = prefs.nutritionGoal == NutritionGoalType.diabetes;
    final icr = prefs.icrGramsPerUnit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Food Manually'),
        actions: [
          IconButton(
            icon: const Icon(Icons.local_drink_outlined),
            tooltip: 'Quick Drink',
            onPressed: _showDrinkSheet,
          ),
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
                  // ── Tab toggle: Search Food | My Meals ─────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TabToggleButton(
                            label: 'Search Food',
                            icon: Icons.search,
                            active: !_showMeals,
                            onTap: () => setState(() => _showMeals = false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TabToggleButton(
                            label: 'My Meals',
                            icon: Icons.restaurant_menu,
                            active: _showMeals,
                            onTap: () => setState(() => _showMeals = true),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_showMeals) ...[
                    // ── Meals list ────────────────────────────────────
                    Expanded(
                      child: _MealsTab(
                        meals: _meals,
                        kcalMap: {for (final f in _allFoods) f.label: f.kcalPer100g},
                        carbsMap: {for (final f in _allFoods) f.label: f.carbsPer100g},
                        onLog: _logMeal,
                        onEdit: (meal) async {
                          final updated = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => CreateMealScreen(meal: meal),
                            ),
                          );
                          if (updated == true) await _loadFoods();
                        },
                        onDelete: (meal) async {
                          if (meal.id != null) {
                            await DatabaseService.instance
                                .deleteCustomMeal(meal.id!);
                            await _loadFoods();
                          }
                        },
                        onCreate: () async {
                          final created = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => const CreateMealScreen(),
                            ),
                          );
                          if (created == true) await _loadFoods();
                        },
                      ),
                    ),
                  ] else ...[
                    // ── Search field ──────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _filter,
                        decoration: const InputDecoration(
                          hintText: 'Search food…',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),

                    // ── Food list ─────────────────────────────────────
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final food = _filtered[i];
                          final isSelected = _selectedLabels.contains(food.label);
                          final isActive = _activeFood?.label == food.label;
                          return Card(
                            color: isActive
                                ? context.primary50
                                : (isSelected
                                    ? context.primary50.withValues(alpha: 0.5)
                                    : null),
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
                                isDiabetic && food.bolusPer100(icr) != null
                                    ? '${food.kcalPer100g.round()} kcal / ${food.unitLabel}  •  '
                                      '${food.bolusPer100(icr)!.toStringAsFixed(1)} u insulin'
                                    : '${food.kcalPer100g.round()} kcal / ${food.unitLabel}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.gray400,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle,
                                      color: context.primary600)
                                  : Icon(Icons.circle_outlined,
                                      color: AppTheme.gray300),
                              onTap: () => _selectFood(food),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── Portion + save bar ──────────────────────────────
                  if (!_showMeals && _selectedLabels.isNotEmpty)
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
                          // Selected count
                          if (_selectedLabels.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, size: 16, color: context.primary600),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_selectedLabels.length} items selected',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: context.primary700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_activeFood != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _activeFood!.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (calPreview != null)
                                    Text(
                                      '≈ ${calPreview.round()} kcal',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: context.primary700,
                                      ),
                                    ),
                                  if (isDiabetic && _activeFood != null) ...[
                                    Builder(builder: (ctx) {
                                      final grams = double.tryParse(_portionCtrl.text) ?? 0;
                                      final bolus = _activeFood!.bolusForGrams(grams, icr);
                                      if (bolus == null || bolus <= 0) return const SizedBox.shrink();
                                      return Text(
                                        '💉 ${bolus.toStringAsFixed(1)} u',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1976D2),
                                        ),
                                      );
                                    }),
                                  ],
                                ],
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

                          // ── Gram/ml slider ─────────────────────────
                          Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _portionCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: _onPortionTextChanged,
                                  decoration: InputDecoration(
                                    suffixText: _activeFood?.perMl == true ? 'ml' : 'g',
                                    labelText: _activeFood?.perMl == true ? 'ml' : 'Grams',
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
                                  label: _activeFood?.perMl == true
                                      ? '${_sliderGrams.round()}ml'
                                      : '${_sliderGrams.round()}g',
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
                                    label: _activeFood?.perMl == true ? '${g}ml' : '${g}g',
                                    active:
                                        _portionCtrl.text == g.toString(),
                                    onTap: () {
                                      _portionCtrl.text = g.toString();
                                      setState(() {
                                        _sliderGrams = g.toDouble();
                                        if (_activeFood != null) {
                                          _gramsOverrides[_activeFood!.label] = g.toDouble();
                                        }
                                      });
                                    },
                                  ),
                                )).toList(),
                          ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: Text('+ Log Food (${_selectedLabels.length})'),
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
    if (_activeFood == null) return null;
    final grams = double.tryParse(_portionCtrl.text) ?? 0;
    return _activeFood!.kcalPer100g * grams / 100;
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
    this.label,
  });
  final int grams;
  final bool active;
  final VoidCallback onTap;
  final String? label;

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
          label ?? '${grams}g',
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

// ── Tab toggle button ────────────────────────────────────────────────────────

class _TabToggleButton extends StatelessWidget {
  const _TabToggleButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? context.primary600 : AppTheme.gray100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: active ? Colors.white : AppTheme.gray400),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppTheme.gray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meals tab ────────────────────────────────────────────────────────────────

class _MealsTab extends StatelessWidget {
  const _MealsTab({
    required this.meals,
    required this.kcalMap,
    required this.carbsMap,
    required this.onLog,
    required this.onEdit,
    required this.onDelete,
    required this.onCreate,
  });

  final List<CustomMeal> meals;
  final Map<String, double> kcalMap;
  final Map<String, double> carbsMap;
  final Future<void> Function(CustomMeal) onLog;
  final void Function(CustomMeal) onEdit;
  final void Function(CustomMeal) onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (meals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_outlined,
                size: 56, color: AppTheme.gray300),
            const SizedBox(height: 12),
            const Text('No saved meals yet',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.gray400)),
            const SizedBox(height: 6),
            const Text('Create a meal to quickly log it next time.',
                style: TextStyle(color: AppTheme.gray400)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create Meal'),
              onPressed: onCreate,
            ),
          ],
        ),
      );
    }

    // Group by meal type
    final grouped = <MealType, List<CustomMeal>>{};
    for (final meal in meals) {
      grouped.putIfAbsent(meal.mealType, () => []).add(meal);
    }

    final sections = <Widget>[];

    for (final type in MealType.values) {
      final typeMeals = grouped[type];
      if (typeMeals == null || typeMeals.isEmpty) continue;

      sections.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          children: [
            Icon(_mealTypeIcon(type), size: 16, color: AppTheme.gray400),
            const SizedBox(width: 6),
            Text(
              type.displayName,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.gray400,
                  letterSpacing: 0.5),
            ),
          ],
        ),
      ));

      for (final meal in typeMeals) {
        final totalKcal = meal.totalKcal(kcalMap);
        final totalCarbs = meal.ingredients.fold<double>(0.0, (sum, ing) {
          final carbsPer100 = carbsMap[ing.foodLabel] ?? 0.0;
          return sum + carbsPer100 * ing.grams / 100.0;
        });
        final prefs = ref.watch(userPrefsProvider);
        final isDiabetic = prefs.nutritionGoal == NutritionGoalType.diabetes;
        final icr = prefs.icrGramsPerUnit;
        final bolus = (isDiabetic && totalCarbs > 0 && icr > 0)
            ? (totalCarbs / icr * 10).round() / 10
            : null;
        sections.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.fromLTRB(16, 8, 8, 8),
                title: Text(meal.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${meal.ingredients.length} ingredient${meal.ingredients.length == 1 ? '' : 's'}  •  ${totalKcal.round()} kcal'
                  + (bolus != null ? '  •  ${totalCarbs.toStringAsFixed(1)} g  •  ${bolus.toStringAsFixed(1)} u' : ''),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit',
                      onPressed: () => onEdit(meal),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: AppTheme.red500),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, meal),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(60, 36),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12)),
                      onPressed: () => onLog(meal),
                      child: const Text('Log'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(children: sections),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create New Meal'),
              onPressed: onCreate,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, CustomMeal meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete meal?'),
        content: Text('Delete "${meal.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Delete', style: TextStyle(color: AppTheme.red500))),
        ],
      ),
    );
    if (confirmed == true) onDelete(meal);
  }

  IconData _mealTypeIcon(MealType type) => switch (type) {
        MealType.breakfast => Icons.wb_sunny_outlined,
        MealType.lunch => Icons.wb_cloudy_outlined,
        MealType.dinner => Icons.nights_stay_outlined,
      };
}

// ── Bolus row helper ──────────────────────────────────────────────────────────

class _BolusRow extends StatelessWidget {
  const _BolusRow({
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
        Icon(icon, size: 18, color: AppTheme.gray400),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 14, color: AppTheme.gray700)),
        ),
        Text(value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            )),
      ],
    );
  }
}

// ── Drinks Quick-Add sheet ────────────────────────────────────────────────────

class _DrinkSheet extends StatefulWidget {
  const _DrinkSheet({required this.onLog});
  final void Function(String label, double ml) onLog;

  @override
  State<_DrinkSheet> createState() => _DrinkSheetState();
}

class _DrinkSheetState extends State<_DrinkSheet> {
  final _customCtrl = TextEditingController();
  String _selectedDrink = 'water';

  static const _presets = [
    ('water',     'Water'),
    ('juice',     'Juice'),
    ('milk',      'Milk'),
    ('coffee',    'Coffee'),
    ('tea',       'Tea'),
    ('soda',      'Soda'),
  ];

  static const _sizes = [
    (150.0,  'Small\n150 ml',   Icons.local_drink_outlined),
    (250.0,  'Medium\n250 ml',  Icons.local_drink),
    (400.0,  'Large\n400 ml',   Icons.coffee_outlined),
    (500.0,  'Bottle\n500 ml',  Icons.water_drop_outlined),
  ];

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('💧 Quick Drink',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((p) {
                final selected = _selectedDrink == p.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.$2),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedDrink = p.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: _sizes.map((s) {
              return GestureDetector(
                onTap: () => widget.onLog(_selectedDrink, s.$1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.gray100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.gray200),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s.$3, size: 28, color: const Color(0xFF1976D2)),
                      const SizedBox(height: 4),
                      Text(s.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text('Or enter amount:',
              style: TextStyle(fontSize: 12, color: AppTheme.gray600)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'ml',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  final ml = double.tryParse(_customCtrl.text);
                  if (ml != null && ml > 0) widget.onLog(_selectedDrink, ml);
                },
                child: const Text('Log'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}