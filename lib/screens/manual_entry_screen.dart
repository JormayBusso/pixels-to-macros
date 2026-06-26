import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/custom_meal.dart';
import '../models/dietary_restriction.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../models/serving_config.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/barcode_lookup_service.dart';
import '../services/database_service.dart';
import '../services/food_scoring_service.dart';
import '../theme/app_theme.dart';
import '../widgets/food_score_badge.dart';
import '../widgets/premium_theme_effects.dart';
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
        _selectedSizeIndex =
            config != null ? (config.sizes.length > 1 ? 1 : 0) : 0;
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
    final grams = _servingConfig!
        .totalGrams(_servingCount, _servingConfig!.sizes[_selectedSizeIndex]);
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

  Future<void> _logMeal(CustomMeal meal) async {
    if (meal.ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).noIngredients)));
      return;
    }

    final detectedFoods = <DetectedFood>[];
    int totalCal = 0;

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
          content: Text('${meal.name} logged — $totalCal kcal'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  // ── Barcode scanning ────────────────────────────────────────────────────

  Future<void> _openBarcodeScanner() async {
    final visualTheme = context.visualTheme;
    final themeColor =
        visualTheme.premium ? visualTheme.primaryAccent : context.primary500;

    // Barcode lookup needs internet (OpenFoodFacts API).
    // Do a quick connectivity check first.
    try {
      final result = await InternetAddress.lookup('world.openfoodfacts.org')
          .timeout(const Duration(seconds: 3));
      if (result.isEmpty || result[0].rawAddress.isEmpty) throw Exception();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '⚠️ Barcode scanning requires an internet connection to look up product info.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // The native Swift side presents its own full-screen scanner UI and
    // performs the OpenFoodFacts lookup using URLSession — no Flutter
    // packages required.
    final result = await BarcodeLookupService.instance
        .scanAndLookup(themeColor: themeColor);
    if (result == null || !mounted) return;

    // Check if food is already in our database.
    final existing = await DatabaseService.instance.getFoodByLabel(result.name);
    FoodData food;
    if (existing != null) {
      food = existing;
    } else {
      // Heuristic: treat as a drink if the name contains common beverage words.
      final lowerName = result.name.toLowerCase();
      final isDrink = const [
        'water',
        'juice',
        'drink',
        'cola',
        'soda',
        'beer',
        'wine',
        'milk',
        'tea',
        'coffee',
        'smoothie',
        'shake',
        'lemonade',
        'espresso',
        'latte',
        'beverage',
        'nectar',
        'syrup',
        'liqueur',
        'spirit',
        'cocktail',
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
      food =
          (await DatabaseService.instance.getFoodByLabel(result.name)) ?? food;
    }

    // Health score sheet handles _selectFood + serving pre-fill via its buttons.
    if (mounted) {
      await _showBarcodeHealthSheet(
          food: food, servingGrams: result.servingGrams);
    }
  }

  List<DietaryRestriction> _restrictionMatchesForFood(
    FoodData food,
    Set<DietaryRestriction> restrictions,
  ) {
    if (restrictions.isEmpty) return const <DietaryRestriction>[];
    final text = '${food.label} ${food.category}';
    return restrictions
        .where((restriction) => restriction.matchesText(text))
        .toList(growable: false);
  }

  Future<void> _showBarcodeHealthSheet({
    required FoodData food,
    double? servingGrams,
  }) {
    final prefs = ref.read(userPrefsProvider);
    final explanation = FoodScoringService.scoreFood(
      food,
      goal: prefs.nutritionGoal,
    );
    final score = explanation.score;
    final Color scoreColor;
    if (score >= 70) {
      scoreColor = const Color(0xFF388E3C);
    } else if (score >= 40) {
      scoreColor = const Color(0xFFF57C00);
    } else {
      scoreColor = const Color(0xFFD32F2F);
    }
    final l10n = AppLocalizations.of(context);
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    return showModalBottomSheet(
      context: context,
      backgroundColor: premium ? visualTheme.cardColor : null,
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            PremiumGradientText(
              text: food.label,
              enabled: premium,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${food.kcalPer100g.round()} kcal  •  ${food.proteinPer100g.round()} g protein  •  '
              '${food.carbsPer100g.round()} g carbs  •  ${food.fatPer100g.round()} g fat',
              style: TextStyle(fontSize: 12, color: context.appMutedTextColor),
            ),
            const SizedBox(height: 16),
            // ── Health score bar ──────────────────────────────────────
            Row(
              children: [
                Text(
                  l10n.foodScoreTitle('needsBalancing'),
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appMutedTextColor,
                  ),
                ),
                const Spacer(),
                Text(
                  l10n.foodScoreTitle('excellentFit'),
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appMutedTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: premium
                            ? visualTheme.gradient
                            : const [
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
                        width: 14,
                        height: 14,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(l10n.foodScoreTitle(explanation.titleKey),
                      style: TextStyle(
                          color: scoreColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FoodScoreBadge(explanation: explanation),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.cancel),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: context.isPremiumTheme
                          ? context.visualTheme.primaryAccent
                          : context.primary500,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(AppLocalizations.of(context).addToLog),
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
    final restrictions = prefs.dietaryRestrictions;
    final l10n = AppLocalizations.of(context);
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    // "Actively editing" == keyboard visible. Drives the contextual Done
    // button (AppBar) and the dismiss FAB, so neither is permanently shown.
    final editing = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).logFoodManually),
        actions: [
          if (editing)
            TextButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              child: Text(AppLocalizations.of(context).done),
            )
          else
            IconButton(
              icon: const Icon(Icons.qr_code_scanner, size: 30),
              tooltip: AppLocalizations.of(context).scanBarcode,
              onPressed: _openBarcodeScanner,
            ),
        ],
      ),
      floatingActionButton: editing
          ? FloatingActionButton.extended(
              onPressed: () => FocusScope.of(context).unfocus(),
              icon: const Icon(Icons.keyboard_arrow_down),
              label: Text(AppLocalizations.of(context).done),
            )
          : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
                              label: AppLocalizations.of(context).searchFoodLabel,
                              icon: Icons.search,
                              active: !_showMeals,
                              onTap: () => setState(() => _showMeals = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _TabToggleButton(
                              label: AppLocalizations.of(context).myMeals,
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
                          kcalMap: {
                            for (final f in _allFoods) f.label: f.kcalPer100g
                          },
                          carbsMap: {
                            for (final f in _allFoods) f.label: f.carbsPer100g
                          },
                          onLog: _logMeal,
                          onEdit: (meal) async {
                            final updated =
                                await Navigator.of(context).push<bool>(
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
                            final created =
                                await Navigator.of(context).push<bool>(
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
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(context).searchFoodHint,
                            prefixIcon: const Icon(Icons.search),
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
                            final isSelected =
                                _selectedLabels.contains(food.label);
                            final isActive = _activeFood?.label == food.label;
                            final restrictionMatches =
                                _restrictionMatchesForFood(food, restrictions);
                            return PremiumMotionSurface(
                              enabled: premium && (isActive || isSelected),
                              borderRadius: BorderRadius.circular(16),
                              padding: const EdgeInsets.all(2),
                              borderWidth: isActive ? 3.0 : 2.4,
                              glow: isActive,
                              child: Card(
                                color: premium
                                    ? visualTheme.cardColor
                                    : (isActive
                                        ? context.primary50
                                        : (isSelected
                                            ? context.primary50
                                                .withValues(alpha: 0.5)
                                            : null)),
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
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${food.kcalPer100g.round()} kcal / ${food.unitLabel}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.appMutedTextColor,
                                        ),
                                      ),
                                      if (restrictionMatches.isNotEmpty)
                                        Text(
                                          '${l10n.restrictionAlert}: ${restrictionMatches.map((restriction) => l10n.dietaryRestrictionShortLabel(restriction.name)).join(', ')}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.amber.shade800,
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: FoodScoreBadge(
                                          explanation:
                                              FoodScoringService.scoreFood(
                                            food,
                                            goal: prefs.nutritionGoal,
                                          ),
                                          compact: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle,
                                          color: premium
                                              ? visualTheme.primaryAccent
                                              : context.primary600)
                                      : Icon(Icons.circle_outlined,
                                          color: AppTheme.gray300),
                                  onTap: () => _selectFood(food),
                                ),
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
                          color: premium ? visualTheme.cardColor : Colors.white,
                          border: Border(
                            top: BorderSide(
                              color: premium
                                  ? visualTheme.borderColor
                                  : context.primary100,
                              width: premium ? 2 : 1,
                            ),
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
                                    Icon(Icons.check_circle,
                                        size: 16,
                                        color: premium
                                            ? visualTheme.primaryAccent
                                            : context.primary600),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_selectedLabels.length} items selected',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: premium
                                            ? visualTheme.primaryAccent
                                            : context.primary700,
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
                                            color: premium
                                                ? visualTheme.primaryAccent
                                                : context.primary700,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_restrictionMatchesForFood(
                                      _activeFood!, restrictions)
                                  .isNotEmpty) ...[
                                _ManualRestrictionAlert(
                                  alerts: _restrictionMatchesForFood(
                                          _activeFood!, restrictions)
                                      .map((restriction) =>
                                          l10n.restrictionItemAlert(
                                            _activeFood!.label,
                                            restriction.name,
                                          ))
                                      .toList(),
                                ),
                                const SizedBox(height: 12),
                              ],
                              FoodScoreBadge(
                                explanation: FoodScoringService.scoreFood(
                                  _activeFood!,
                                  goal: prefs.nutritionGoal,
                                ),
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
                                        suffixText: _activeFood?.perMl == true
                                            ? 'ml'
                                            : 'g',
                                        labelText: _activeFood?.perMl == true
                                            ? 'ml'
                                            : 'Grams',
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
                                children: [50, 100, 150, 200, 300]
                                    .map((g) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          child: _PortionChip(
                                            grams: g,
                                            label: _activeFood?.perMl == true
                                                ? '${g}ml'
                                                : '${g}g',
                                            active: _portionCtrl.text ==
                                                g.toString(),
                                            onTap: () {
                                              _portionCtrl.text = g.toString();
                                              setState(() {
                                                _sliderGrams = g.toDouble();
                                                if (_activeFood != null) {
                                                  _gramsOverrides[_activeFood!
                                                      .label] = g.toDouble();
                                                }
                                              });
                                            },
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text(
                                    '+ Log Food (${_selectedLabels.length})'),
                                onPressed: _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: premium
                                      ? visualTheme.primaryAccent
                                      : context.primary500,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
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
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    final (IconData icon, Color color) = switch (category) {
      'fruit' => (
          Icons.apple,
          premium ? visualTheme.primaryAccent : context.primary600
        ),
      'vegetable' => (
          Icons.grass,
          premium ? visualTheme.primaryAccent : context.primary500
        ),
      'grain' => (Icons.grain, AppTheme.amber700),
      'protein' => (Icons.egg, AppTheme.red500),
      'dairy' => (Icons.water_drop, AppTheme.amber500),
      'mixed' => (Icons.restaurant, AppTheme.gray700),
      'legume' => (
          Icons.eco,
          premium ? visualTheme.secondaryAccent : context.primary700
        ),
      'nut' => (Icons.filter_vintage, AppTheme.amber600),
      'snack' => (Icons.cookie, AppTheme.amber500),
      'drink' => (
          Icons.local_drink,
          premium ? visualTheme.secondaryAccent : context.primary400
        ),
      _ => (Icons.circle, AppTheme.gray400),
    };
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: premium ? 0.18 : 0.12),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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

class _ManualRestrictionAlert extends StatelessWidget {
  const _ManualRestrictionAlert({required this.alerts});
  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alerts.join('\n'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.gray700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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
    final premium = context.isPremiumTheme;
    final activeColor =
        premium ? context.visualTheme.primaryAccent : context.primary600;
    final inactiveBg = premium ? context.appSubtleFillColor : AppTheme.gray100;
    final inactiveBorder = premium ? context.appBorderColor : AppTheme.gray100;
    final inactiveFg = premium ? context.appMutedTextColor : AppTheme.gray600;
    final inactiveIcon = premium ? context.appMutedTextColor : AppTheme.gray400;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? activeColor : inactiveBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? activeColor : inactiveBorder,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : inactiveIcon),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : inactiveFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meals tab ────────────────────────────────────────────────────────────────

class _MealsTab extends ConsumerWidget {
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
    final restrictions = ref.watch(userPrefsProvider).dietaryRestrictions;
    if (meals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_outlined,
                size: 56, color: AppTheme.gray300),
            const SizedBox(height: 12),
            Text(AppLocalizations.of(context).noSavedMeals,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appMutedTextColor)),
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).createMealDesc,
                style: TextStyle(color: context.appMutedTextColor)),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.of(context).createMeal),
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
            Icon(_mealTypeIcon(type),
                size: 16, color: context.appMutedTextColor),
            const SizedBox(width: 6),
            Text(
              type.displayName,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.appMutedTextColor,
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
        final restrictionMatches = restrictions.where((restriction) {
          return meal.ingredients.any(
            (ingredient) => restriction.matchesText(ingredient.foodLabel),
          );
        }).toList(growable: false);
        sections.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                title: Text(meal.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${meal.ingredients.length} ingredient${meal.ingredients.length == 1 ? '' : 's'}  •  ${totalKcal.round()} kcal'
                      '${totalCarbs > 0 ? '  •  ${totalCarbs.toStringAsFixed(1)} g carbs' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (restrictionMatches.isNotEmpty)
                      Text(
                        'Alert: ${restrictionMatches.map((restriction) => restriction.shortLabel).join(', ')}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade800,
                        ),
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: AppLocalizations.of(context).editTooltip,
                      onPressed: () => onEdit(meal),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: AppTheme.red500),
                      tooltip: AppLocalizations.of(context).delete,
                      onPressed: () => _confirmDelete(context, meal),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(60, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12)),
                      onPressed: () => onLog(meal),
                      child: Text(AppLocalizations.of(context).log),
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
              label: Text(AppLocalizations.of(context).createNewMeal),
              onPressed: onCreate,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, CustomMeal meal) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deleteMeal),
        content: Text('${l10n.delete} "${meal.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.delete,
                  style: const TextStyle(color: AppTheme.red500))),
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
