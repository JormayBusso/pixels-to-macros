import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/custom_meal.dart';
import '../models/dietary_restriction.dart';
import '../models/food_data.dart';
import '../models/meal_plan.dart';
import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../providers/meal_planner_provider.dart';
import '../providers/grocery_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/pantry_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/database_service.dart';
import '../services/recipe_repository.dart';
import '../services/recipe_swap_service.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_theme_effects.dart';
import 'recipes_screen.dart';

/// Converts a [CustomMeal] to a [Recipe] for use in the meal planner UI.
Recipe _customMealToRecipe(CustomMeal meal, List<FoodData> foods) {
  final kcalMap = {for (final f in foods) f.label: f.kcalPer100g};
  final proteinMap = {for (final f in foods) f.label: f.proteinPer100g};
  final carbsMap = {for (final f in foods) f.label: f.carbsPer100g};
  final fatMap = {for (final f in foods) f.label: f.fatPer100g};
  double kcal = 0, protein = 0, carbs = 0, fat = 0;
  for (final ing in meal.ingredients) {
    final g = ing.grams / 100.0;
    kcal += (kcalMap[ing.foodLabel] ?? 0) * g;
    protein += (proteinMap[ing.foodLabel] ?? 0) * g;
    carbs += (carbsMap[ing.foodLabel] ?? 0) * g;
    fat += (fatMap[ing.foodLabel] ?? 0) * g;
  }
  final mealType = switch (meal.mealType) {
    MealType.breakfast => RecipeMealType.breakfast,
    MealType.lunch => RecipeMealType.lunch,
    MealType.dinner => RecipeMealType.dinner,
  };
  return Recipe(
    id: 'custom:${meal.id ?? 0}',
    name: meal.name,
    image: meal.imagePath,
    mealType: mealType,
    goals: const {},
    minutes: 0,
    servings: 1,
    calories: kcal.round(),
    proteinG: protein,
    carbsG: carbs,
    fatG: fat,
    fiberG: 0,
    sugarG: 0,
    tags: const ['custom'],
    ingredients: meal.ingredients
        .map((i) => RecipeIngredient(
              name: i.foodLabel,
              amount: '${i.grams.round()}g',
              grams: i.grams,
            ))
        .toList(),
    steps: const [],
    source: 'custom',
  );
}

/// The nutrition goal the weekly planner is currently planning for. Defaults to
/// the user's global goal; can be overridden per session from the planner's
/// goal chips. A null value means "All goals" (no eligibility filter — every
/// recipe qualifies), exactly like the Recipes screen's "All goals" option.
final plannerGoalProvider = StateProvider<NutritionGoalType?>(
    (ref) => ref.read(userPrefsProvider).nutritionGoal);

String _localizedGoalLabel(AppLocalizations l10n, NutritionGoalType goal) {
  return switch (goal) {
    NutritionGoalType.muscleGrowth => l10n.muscleGrowth,
    NutritionGoalType.diabetes => l10n.diabetes,
    NutritionGoalType.vegan => l10n.veganDiet,
    NutritionGoalType.vegetarian => l10n.vegetarianDiet,
    NutritionGoalType.pescatarian => l10n.pescatarian,
    NutritionGoalType.mediterranean => l10n.mediterranean,
    NutritionGoalType.weightLoss => l10n.weightLoss,
    NutritionGoalType.keto => l10n.keto,
    NutritionGoalType.maintain => l10n.maintainWeight,
  };
}

String _localizedMealTypeLabel(AppLocalizations l10n, RecipeMealType mealType) {
  return switch (mealType) {
    RecipeMealType.breakfast => l10n.breakfast,
    RecipeMealType.lunch => l10n.lunch,
    RecipeMealType.dinner => l10n.dinner,
    RecipeMealType.snack => l10n.snack,
    RecipeMealType.dessert => l10n.dessert,
  };
}

/// Full-screen smart weekly meal planner.
class MealPlannerScreen extends ConsumerStatefulWidget {
  const MealPlannerScreen({super.key});

  @override
  ConsumerState<MealPlannerScreen> createState() => _MealPlannerScreenState();
}

class _MealPlannerScreenState extends ConsumerState<MealPlannerScreen> {
  static const _mealTypes = [
    RecipeMealType.breakfast,
    RecipeMealType.lunch,
    RecipeMealType.dinner,
    RecipeMealType.snack,
    RecipeMealType.dessert,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final goal = ref.read(userPrefsProvider).nutritionGoal;
      ref.read(mealPlanProvider.notifier).languageCode =
          ref.read(localeProvider).code;
      ref.read(mealPlanProvider.notifier).load(goal);
      ref.read(pantryProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(mealPlanProvider);
    final prefs = ref.watch(userPrefsProvider);
    // The planner can target any nutrition goal (defaults to the global one),
    // or "All goals" (null) for no filter. The AI autopilot + Smart Swap then
    // pick ONLY recipes eligible for the chosen goal.
    final plannerGoalRaw = ref.watch(plannerGoalProvider);
    final isAllGoals = plannerGoalRaw == null;
    // "All goals" maps to maintain for filtering (every recipe qualifies).
    final selectedGoal = plannerGoalRaw ?? NutritionGoalType.maintain;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.weeklyMealPlanner,
                maxLines: 2,
                softWrap: true,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(
              'Week ${plan.weekNumber}, ${plan.year}',
              style: TextStyle(fontSize: 11, color: context.appMutedTextColor),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.mealPlanAutopilot,
            onPressed: () => _runAutopilot(context),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          if (plan.assignments.isNotEmpty)
            TextButton.icon(
              onPressed: () => _generateGroceryList(context),
              icon: const Icon(Icons.shopping_basket_outlined, size: 18),
              label: Text(l10n.groceryList),
              style: TextButton.styleFrom(
                foregroundColor: context.primary500,
              ),
            ),
        ],
      ),
      body: plan.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Goal banner ──
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.isPremiumTheme
                        ? context.primary50
                        : selectedGoal.lightColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selectedGoal.color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(selectedGoal.emoji,
                          style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAllGoals
                                  ? l10n.allGoals
                                  : l10n.personalisedFor(
                                      _localizedGoalLabel(l10n, selectedGoal),
                                    ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selectedGoal.color,
                              ),
                            ),
                            Text(
                              l10n.mealPlannerInstructions,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.appMutedTextColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // ── Goal selector (mirrors the Recipes screen): the AI plans
                // and swaps pull ONLY meals eligible for the chosen goal. ──
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            l10n.allGoals,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          selected: isAllGoals,
                          showCheckmark: false,
                          onSelected: (_) => ref
                              .read(plannerGoalProvider.notifier)
                              .state = null,
                        ),
                      ),
                      for (final g in NutritionGoalType.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${g.emoji} ${_localizedGoalLabel(l10n, g)}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            selected: plannerGoalRaw == g,
                            showCheckmark: false,
                            onSelected: (_) => ref
                                .read(plannerGoalProvider.notifier)
                                .state = g,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // ── Dietary / allergy chips (matching allergens are hidden) ──
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Center(
                          child: Icon(Icons.no_food_outlined,
                              size: 16, color: context.appMutedTextColor),
                        ),
                      ),
                      for (final r in DietaryRestriction.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              l10n.dietaryRestrictionLabel(r.name),
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: prefs.dietaryRestrictions.contains(r),
                            onSelected: (_) {
                              final updated = {...prefs.dietaryRestrictions};
                              if (updated.contains(r)) {
                                updated.remove(r);
                              } else {
                                updated.add(r);
                              }
                              ref.read(userPrefsProvider.notifier).update(
                                  prefs.copyWith(
                                      dietaryRestrictions: updated));
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _PlannerActionBar(onAutopilot: () => _runAutopilot(context)),
                const SizedBox(height: 8),
                // ── Day list ──
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: 7,
                    itemBuilder: (context, index) {
                      final dayIndex = index + 1; // 1=Mon, 7=Sun
                      return _DayCard(
                        dayIndex: dayIndex,
                        dayName: kWeekDays[index],
                        mealTypes: _mealTypes,
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: plan.assignments.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _confirmClear(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.red500,
                          side: const BorderSide(color: AppTheme.red500),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(l10n.clearWeek),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => _generateGroceryList(context),
                        icon: const Icon(Icons.shopping_basket_outlined,
                            size: 18),
                        label: Text(l10n.generateGroceryList),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _runAutopilot(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(userPrefsProvider);
    final pantryMode = ref.read(pantryModeProvider);
    final pantryNames =
        pantryMode ? ref.read(pantryProvider).availableNames : const <String>{};
    await ref.read(mealPlanProvider.notifier).autoFillWeek(
          goal: ref.read(plannerGoalProvider) ?? NutritionGoalType.maintain,
          dailyCalorieGoal: prefs.dailyCalorieGoal,
          dietaryRestrictions: prefs.dietaryRestrictions,
          pantryNames: pantryNames,
          // Re-running the AI planner reshuffles the entire week so every day
          // gets a fresh, different set of dishes.
          replaceExisting: true,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.mealPlanAutopilotDone),
        backgroundColor: context.isPremiumTheme
            ? context.visualTheme.primaryAccent
            : AppTheme.green600,
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearWeekPlan),
        content: Text(l10n.deleteScanDesc),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(mealPlanProvider.notifier).clearWeek();
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.red500),
            child: Text(l10n.clearWeek),
          ),
        ],
      ),
    );
  }

  Future<void> _generateGroceryList(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final plan = ref.read(mealPlanProvider);
    if (plan.assignments.isEmpty) return;

    // Days that actually have a meal planned.
    final daysWithMeals = <int>{
      for (final key in plan.assignments.keys)
        int.tryParse(key.split('_').first) ?? 1,
    }.toList()
      ..sort();

    // Ask how many people each planned day is cooking for.
    final people = await showDialog<Map<int, int>>(
      context: context,
      builder: (_) => _PeoplePerDayDialog(days: daysWithMeals),
    );
    if (people == null || !context.mounted) return;

    // Aggregate REAL purchase quantities. Each planned slot is one serving, so
    // per-ingredient grams = recipe ingredient grams / recipe servings, scaled
    // by that slot's portion multiplier and the people cooking that day. Summed
    // across the week and keyed by a normalised name.
    final gramsByItem = <String, double>{};
    final displayName = <String, String>{};
    plan.assignments.forEach((key, recipe) {
      final day = int.tryParse(key.split('_').first) ?? 1;
      final portion = plan.portionMultipliers[key] ?? 1.0;
      final ppl = (people[day] ?? 1).clamp(1, 50);
      final factor = portion * ppl;
      final servings = recipe.servings <= 0 ? 1 : recipe.servings;
      for (final ing in recipe.ingredients) {
        final nm = _normaliseGroceryIngredient(ing.name);
        final k = nm.toLowerCase().trim();
        gramsByItem[k] =
            (gramsByItem[k] ?? 0) + (ing.grams / servings) * factor;
        displayName.putIfAbsent(k, () => nm);
      }
    });

    final aggs = <_AggIngredient>[];
    gramsByItem.forEach((k, grams) {
      final line = _groceryLine(displayName[k] ?? k, grams);
      if (line != null) {
        aggs.add(_AggIngredient(
          name: line.name,
          quantity: line.quantity,
          unit: line.unit,
          totalGrams: grams,
        ));
      }
    });

    if (!context.mounted || aggs.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroceryPreviewSheet(
        ingredients: aggs,
        onClearList: () async {
          await ref.read(groceryProvider.notifier).clearAll();
        },
        onAdd: () async {
          final notifier = ref.read(groceryProvider.notifier);
          final items = aggs
              .map((agg) => (
                    name: agg.name,
                    category: _guessCategory(agg.name),
                    quantity: agg.quantity,
                    unit: agg.unit.isEmpty ? null : agg.unit,
                  ))
              .toList();
          await notifier.addItems(items);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.itemsAdded(aggs.length)),
                backgroundColor: AppTheme.green600,
              ),
            );
            Navigator.pop(context);
          }
        },
      ),
    );
  }

  /// Normalise an ingredient name into a single, clean grocery key. Recipe
  /// ingredient names are scraped freeform phrases ("Warm mustard", "toasted
  /// sesame oil", "small ripe avocados, sliced"), so we strip preparation notes
  /// (anything after a comma/parenthesis) and descriptor words (warm, ripe,
  /// sliced, fresh, …) to leave just the shoppable item ("mustard", "sesame
  /// oil", "avocados"). Egg and garlic variants collapse so quantities
  /// aggregate and convert to natural units (cloves, pieces).
  static const Set<String> _ingredientNoiseWords = {
    'warm', 'cold', 'hot', 'fresh', 'freshly', 'ripe', 'large', 'small',
    'medium', 'big', 'extra', 'organic', 'raw', 'cooked', 'boiled', 'baked',
    'roasted', 'grilled', 'fried', 'toasted', 'chopped', 'sliced', 'diced',
    'minced', 'grated', 'shredded', 'crushed', 'ground', 'peeled', 'halved',
    'quartered', 'cubed', 'crumbled', 'melted', 'softened', 'drained', 'rinsed',
    'dried', 'frozen', 'canned', 'jarred', 'smoked', 'lean', 'boneless',
    'skinless', 'virgin', 'unsalted', 'salted', 'plain', 'whole', 'light',
    'optional', 'taste', 'finely', 'roughly', 'thinly', 'thickly', 'good',
    'quality', 'your', 'favourite', 'favorite', 'some', 'few', 'little',
    'pinch', 'of', 'a', 'an', 'the', 'for', 'and', 'with', 'into', 'about',
    'approximately', 'to', 'or', 'plus', 'pieces', 'piece', 'slices', 'slice',
    'beaten', 'warmed', 'room', 'temperature', 'packed', 'level', 'heaped',
  };

  static String _normaliseGroceryIngredient(String name) {
    // Drop preparation notes after a comma / parenthesis / "—".
    var core = name.toLowerCase().split(RegExp(r'[,(\u2013\u2014/]')).first;
    // Keep only letters/spaces/hyphens, then drop descriptor noise words.
    final tokens = core
        .replaceAll(RegExp(r'[^a-z\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_ingredientNoiseWords.contains(t))
        .toList();
    var cleaned = tokens.join(' ').trim();
    if (cleaned.isEmpty) cleaned = name.toLowerCase().trim();

    if (RegExp(r'\begg\s*(white|yolk|whites|yolks)\b').hasMatch(cleaned)) {
      return 'eggs';
    }
    if (cleaned == 'egg' || cleaned == 'eggs') return 'eggs';
    if (cleaned.contains('garlic')) return 'garlic';

    // Title-case for a tidy shopping list ("sesame oil" -> "Sesame Oil").
    return cleaned
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Convert summed grams for a (normalised) ingredient into a purchasable
  /// quantity + unit, e.g. garlic -> cloves, eggs -> pieces, everything else
  /// -> grams rounded to a sensible amount. Returns null for trace/"to taste"
  /// amounts and for water (not something you shop for).
  static ({int quantity, String unit, String name})? _groceryLine(
      String name, double grams) {
    final l = name.toLowerCase().trim();
    if (l == 'water' || grams < 1) return null;
    if (l == 'garlic') {
      var cloves = (grams / 5).round();
      cloves = cloves.clamp(1, 40);
      return (
        quantity: cloves,
        unit: cloves == 1 ? 'clove' : 'cloves',
        name: 'garlic'
      );
    }
    if (l == 'eggs') {
      final n = (grams / 50).round().clamp(1, 60);
      return (quantity: n, unit: n == 1 ? 'pc' : 'pcs', name: 'eggs');
    }
    int g;
    if (grams < 50) {
      g = (grams / 5).round() * 5;
    } else if (grams < 500) {
      g = (grams / 10).round() * 10;
    } else {
      g = (grams / 25).round() * 25;
    }
    if (g < 1) g = 1;
    return (quantity: g, unit: 'g', name: name);
  }

  String _guessCategory(String name) {
    final l = name.toLowerCase();
    const fruits = [
      'apple',
      'banana',
      'berry',
      'orange',
      'grape',
      'mango',
      'peach',
      'pear',
      'melon',
      'kiwi',
      'lemon',
      'cherry',
      'avocado'
    ];
    const vegs = [
      'broc',
      'carrot',
      'pepper',
      'tomato',
      'onion',
      'lettuce',
      'spinach',
      'cucumber',
      'zucchini',
      'kale',
      'celery',
      'potato',
      'pea',
      'bean',
      'asparagus',
      'corn'
    ];
    const proteins = [
      'chicken',
      'beef',
      'pork',
      'salmon',
      'tuna',
      'shrimp',
      'egg',
      'tofu',
      'steak',
      'fish',
      'lamb',
      'turkey',
      'tempeh'
    ];
    const dairy = ['milk', 'cheese', 'yogurt', 'cream', 'butter', 'whey'];
    const grains = [
      'rice',
      'pasta',
      'bread',
      'oat',
      'cereal',
      'quinoa',
      'wheat',
      'flour',
      'noodle',
      'tortilla'
    ];
    if (fruits.any(l.contains)) return 'Fruits';
    if (vegs.any(l.contains)) return 'Vegetables';
    if (proteins.any(l.contains)) return 'Protein';
    if (dairy.any(l.contains)) return 'Dairy';
    if (grains.any(l.contains)) return 'Grains';
    return 'Other';
  }
}

class _PlannerActionBar extends ConsumerWidget {
  const _PlannerActionBar({required this.onAutopilot});

  final VoidCallback onAutopilot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pantryMode = ref.watch(pantryModeProvider);
    final pantry = ref.watch(pantryProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: PremiumMotionSurface(
              borderRadius: BorderRadius.circular(12),
              glow: true,
              animate: true,
              borderWidth: 3.4,
              child: FilledButton.icon(
                onPressed: onAutopilot,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(l10n.mealPlanAutopilot),
                style: FilledButton.styleFrom(
                  backgroundColor: context.isPremiumTheme
                      ? context.visualTheme.cardColor
                      : context.primary500,
                  foregroundColor: context.isPremiumTheme
                      ? context.visualTheme.primaryAccent
                      : Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: l10n.pantryMode,
            child: FilterChip(
              avatar: Icon(
                Icons.kitchen_outlined,
                size: 17,
                color:
                    pantryMode ? context.primary700 : context.appMutedTextColor,
              ),
              label: Text(
                pantryMode
                    ? '${l10n.pantryMode} (${pantry.availableItems.length})'
                    : l10n.pantryMode,
              ),
              labelStyle: TextStyle(color: context.appTextColor),
              backgroundColor: context.appSubtleFillColor,
              selected: pantryMode,
              selectedColor: context.primary500.withValues(alpha: 0.20),
              checkmarkColor: context.primary700,
              side: BorderSide(color: context.appBorderColor),
              onSelected: (value) async {
                ref.read(pantryModeProvider.notifier).state = value;
                if (!value) return;
                final pantryState = ref.read(pantryProvider);
                final messenger = ScaffoldMessenger.of(context);
                if (pantryState.availableItems.isEmpty) {
                  // Turning Pantry Mode on with an empty pantry would otherwise
                  // do nothing — open the manager so the user can add items.
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.pantryModeEmptyHint)),
                  );
                  await showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const _PantrySheet(),
                  );
                } else {
                  // Make the effect visible: offer to re-run Autopilot so the
                  // plan actually shifts toward the user's ingredients.
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.pantryModeReadyHint(
                            pantryState.availableItems.length),
                      ),
                      action: SnackBarAction(
                        label: l10n.mealPlanAutopilot,
                        onPressed: onAutopilot,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          IconButton.filledTonal(
            tooltip: l10n.managePantry,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _PantrySheet(),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
        ],
      ),
    );
  }
}

// ── Day card ─────────────────────────────────────────────────────────────────

class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.dayIndex,
    required this.dayName,
    required this.mealTypes,
  });

  final int dayIndex;
  final String dayName;
  final List<RecipeMealType> mealTypes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(mealPlanProvider);
    final prefs = ref.watch(userPrefsProvider);
    final l10n = AppLocalizations.of(context);
    final hasAny = mealTypes.any((m) => plan.isEnabled(dayIndex, m));

    // Sum calories for this day
    int dayCal = 0;
    for (final m in mealTypes) {
      final r = plan.recipeFor(dayIndex, m);
      if (r != null && plan.isEnabled(dayIndex, m)) {
        final mult = plan.portionMultiplierFor(dayIndex, m);
        dayCal += (r.caloriesPerServing(r.servings) * mult).round();
      }
    }
    final dailyGoal = prefs.dailyCalorieGoal;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: hasAny ? 2 : 0.5,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Row(
              children: [
                Text(
                  dayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: hasAny ? context.primary500 : AppTheme.gray700,
                  ),
                ),
                const Spacer(),
                if (hasAny && dayCal > 0) ...[
                  Text(
                    '$dayCal / $dailyGoal kcal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: dayCal > dailyGoal * 1.1
                          ? Colors.red.shade600
                          : dayCal > dailyGoal * 0.9
                              ? Colors.green.shade600
                              : context.appMutedTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  hasAny
                      ? l10n.nMeals(
                          mealTypes
                              .where((m) => plan.isEnabled(dayIndex, m))
                              .length,
                        )
                      : l10n.tapToAddMeals,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appMutedTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Meal slot rows
            ...mealTypes.map((mealType) => _MealSlotRow(
                  dayIndex: dayIndex,
                  mealType: mealType,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Meal slot row ─────────────────────────────────────────────────────────────

class _MealSlotRow extends ConsumerWidget {
  const _MealSlotRow({required this.dayIndex, required this.mealType});

  final int dayIndex;
  final RecipeMealType mealType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(mealPlanProvider);
    final isEnabled = plan.isEnabled(dayIndex, mealType);
    final recipe = plan.recipeFor(dayIndex, mealType);
    final portionMultiplier = plan.portionMultiplierFor(dayIndex, mealType);
    final prefs = ref.watch(userPrefsProvider);
    final l10n = AppLocalizations.of(context);
    final goal = ref.watch(plannerGoalProvider) ?? NutritionGoalType.maintain;
    final dailyCal = prefs.dailyCalorieGoal;
    final restrictions = prefs.dietaryRestrictions;
    final pantryMode = ref.watch(pantryModeProvider);
    final pantryNames = pantryMode
        ? ref.watch(pantryProvider).availableNames
        : const <String>{};

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isEnabled
              ? context.primary500.withValues(alpha: 0.06)
              : context.appSubtleFillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEnabled
                ? context.primary500.withValues(alpha: 0.25)
                : context.appBorderColor,
          ),
        ),
        child: Column(
          children: [
            // Slot header toggle
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => ref.read(mealPlanProvider.notifier).toggleSlot(
                  dayIndex, mealType, goal,
                  dailyCalorieGoal: dailyCal,
                  dietaryRestrictions: restrictions,
                  pantryNames: pantryNames),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Text(mealType.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      _localizedMealTypeLabel(l10n, mealType),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isEnabled
                            ? context.primary500
                            : context.appMutedTextColor,
                      ),
                    ),
                    const Spacer(),
                    if (isEnabled && recipe != null)
                      GestureDetector(
                        onTap: () => ref
                            .read(mealPlanProvider.notifier)
                            .shuffleSlot(dayIndex, mealType, goal,
                                dailyCalorieGoal: dailyCal,
                                dietaryRestrictions: restrictions,
                                pantryNames: pantryNames),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.primary500.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.shuffle_rounded,
                              size: 22, color: context.primary500),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: isEnabled,
                      onChanged: (_) => ref
                          .read(mealPlanProvider.notifier)
                          .toggleSlot(dayIndex, mealType, goal,
                              dailyCalorieGoal: dailyCal,
                              dietaryRestrictions: restrictions,
                              pantryNames: pantryNames),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),
            ),
            // Assigned recipe preview
            if (isEnabled && recipe != null)
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(10)),
                onTap: () => _openDetail(context, recipe),
                child: Container(
                  decoration: BoxDecoration(
                    color: context.appSurfaceColor.withValues(alpha: 0.92),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10)),
                  ),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(10),
                        ),
                        child: recipe.image != null
                            ? (recipe.id.startsWith('custom:')
                                ? Image.file(
                                    File(recipe.image!),
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                        width: 60,
                                        height: 60,
                                        color: context.appSubtleFillColor,
                                        child: Center(
                                          child: Text(mealType.emoji,
                                              style: const TextStyle(
                                                  fontSize: 22)),
                                        )),
                                  )
                                : CachedNetworkImage(
                                    imageUrl: recipe.image!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => Container(
                                        width: 60,
                                        height: 60,
                                        color: context.appSubtleFillColor),
                                    errorWidget: (_, __, ___) => Container(
                                        width: 60,
                                        height: 60,
                                        color: context.appSubtleFillColor,
                                        child: Center(
                                          child: Text(mealType.emoji,
                                              style: const TextStyle(
                                                  fontSize: 22)),
                                        )),
                                  ))
                            : Container(
                                width: 60,
                                height: 60,
                                color: context.appSubtleFillColor,
                                child: Center(
                                  child: Text(mealType.emoji,
                                      style: const TextStyle(fontSize: 22)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recipe.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Icon(
                                      Icons.local_fire_department_outlined,
                                      size: 11,
                                      color: context.appMutedTextColor),
                                  const SizedBox(width: 2),
                                  Text(
                                      '${(recipe.caloriesPerServing(recipe.servings) * portionMultiplier).round()} kcal',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: context.appMutedTextColor)),
                                  if (portionMultiplier > 1.05) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      'x${portionMultiplier.toStringAsFixed(1)} ${l10n.portion}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  _MacroBadge(
                                      'P', recipe.proteinG, Colors.blue),
                                  const SizedBox(width: 4),
                                  _MacroBadge(
                                      'C', recipe.carbsG, Colors.orange),
                                  const SizedBox(width: 4),
                                  _MacroBadge('F', recipe.fatG, Colors.red),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Swap recipe button (AI Swap)
                      PremiumMotionSurface(
                        borderRadius: BorderRadius.circular(40),
                        glow: true,
                        animate: true,
                        borderWidth: 3.4,
                        child: GestureDetector(
                          onTap: () => _showSmartSwapSheet(context, ref, goal),
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: context.primary500.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.auto_awesome,
                                size: 24, color: context.primary500),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (isEnabled && recipe == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_empty,
                        size: 14, color: context.appMutedTextColor),
                    const SizedBox(width: 6),
                    Text(l10n.findingRecipe,
                        style: TextStyle(
                            fontSize: 11, color: context.appMutedTextColor)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSmartSwapSheet(
    BuildContext context,
    WidgetRef ref,
    NutritionGoalType goal,
  ) async {
    final prefs = ref.read(userPrefsProvider);
    final pantryMode = ref.read(pantryModeProvider);
    final pantryNames =
        pantryMode ? ref.read(pantryProvider).availableNames : const <String>{};
    final choice = await showModalBottomSheet<_SwapChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SmartSwapSheet(mealType: mealType),
    );
    if (choice == null) return;
    if (choice.manualPick) {
      if (!context.mounted) return;
      await _pickDifferentRecipe(context, ref, goal);
      return;
    }
    // Intent chosen → show the FULL ranked alternative list for that intent so
    // the user can browse the whole valid selection (not a single auto-swap).
    final ranked = await ref.read(mealPlanProvider.notifier).swapCandidates(
          dayIndex,
          mealType,
          goal,
          intent: choice.intent,
          dietaryRestrictions: prefs.dietaryRestrictions,
          pantryNames: pantryNames,
          limit: 30,
        );
    if (!context.mounted) return;
    if (ranked.isEmpty) {
      await ref.read(mealPlanProvider.notifier).smartSwapSlot(
            dayIndex,
            mealType,
            goal,
            intent: choice.intent,
            dailyCalorieGoal: prefs.dailyCalorieGoal,
            dietaryRestrictions: prefs.dietaryRestrictions,
            pantryNames: pantryNames,
          );
      return;
    }
    final picked = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickRecipeSheet(candidates: ranked, mealType: mealType),
    );
    if (picked != null) {
      await ref.read(mealPlanProvider.notifier).assignRecipe(
            dayIndex,
            mealType,
            picked,
            goal: goal,
            dailyCalorieGoal: prefs.dailyCalorieGoal,
          );
    }
  }

  void _openDetail(BuildContext context, Recipe recipe) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe)),
    );
  }

  Future<void> _pickDifferentRecipe(
    BuildContext context,
    WidgetRef ref,
    goal,
  ) async {
    final prefs = ref.read(userPrefsProvider);
    final candidates = await RecipeRepository.instance.query(
      goal: goal,
      mealType: mealType,
      limit: 1000,
      includeGenerated: true,
      language: ref.read(localeProvider).code,
      dietaryRestrictions: prefs.dietaryRestrictions,
    );
    // Also include custom meals that match this meal type
    final allCustom = await DatabaseService.instance.getCustomMeals();
    final allFoods = await DatabaseService.instance.getAllFoods();
    final matchingCustom = allCustom.where((m) {
      final mt = switch (m.mealType) {
        MealType.breakfast => RecipeMealType.breakfast,
        MealType.lunch => RecipeMealType.lunch,
        MealType.dinner => RecipeMealType.dinner,
      };
      return mt == mealType;
    }).toList();
    final customAsRecipes = matchingCustom
        .map((m) => _customMealToRecipe(m, allFoods))
        .where((recipe) => RecipeRepository.instance
            .isAllowedByRestrictions(recipe, prefs.dietaryRestrictions))
        .toList();
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickRecipeSheet(
        candidates: [...customAsRecipes, ...candidates],
        mealType: mealType,
      ),
    );
    if (picked != null) {
      await ref.read(mealPlanProvider.notifier).assignRecipe(
          dayIndex, mealType, picked,
          goal: goal, dailyCalorieGoal: prefs.dailyCalorieGoal);
    }
  }
}

class _SwapChoice {
  const _SwapChoice.intent(this.intent) : manualPick = false;
  const _SwapChoice.manual()
      : intent = SmartSwapIntent.balanced,
        manualPick = true;

  final SmartSwapIntent intent;
  final bool manualPick;
}

class _SmartSwapSheet extends StatelessWidget {
  const _SmartSwapSheet({required this.mealType});

  final RecipeMealType mealType;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(mealType.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Text(
                  l10n.smartSwap,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.smartSwapSubtitle,
              style: TextStyle(fontSize: 12, color: context.appMutedTextColor),
            ),
            const SizedBox(height: 12),
            ...SmartSwapIntent.values.map(
              (intent) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_swapIcon(intent), color: context.primary600),
                title: Text(l10n.smartSwapIntentLabel(intent.name),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l10n.smartSwapIntentDescription(intent.name)),
                onTap: () => Navigator.pop(context, _SwapChoice.intent(intent)),
              ),
            ),
            const Divider(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.search_outlined, color: context.primary600),
              title: Text(
                  l10n.pickRecipe(_localizedMealTypeLabel(l10n, mealType)),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(l10n.manualRecipePicker),
              onTap: () => Navigator.pop(context, const _SwapChoice.manual()),
            ),
          ],
        ),
      ),
    );
  }

  IconData _swapIcon(SmartSwapIntent intent) {
    switch (intent) {
      case SmartSwapIntent.balanced:
        return Icons.tune_outlined;
      case SmartSwapIntent.higherProtein:
        return Icons.fitness_center_outlined;
      case SmartSwapIntent.lowerCarb:
        return Icons.grain_outlined;
      case SmartSwapIntent.faster:
        return Icons.timer_outlined;
      case SmartSwapIntent.pantryFirst:
        return Icons.kitchen_outlined;
    }
  }
}

class _PantrySheet extends ConsumerStatefulWidget {
  const _PantrySheet();

  @override
  ConsumerState<_PantrySheet> createState() => _PantrySheetState();
}

class _PantrySheetState extends ConsumerState<_PantrySheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(pantryProvider.notifier).load(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    await ref.read(pantryProvider.notifier).addItem(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(pantryProvider);
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.42,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: context.primary600),
                      const SizedBox(width: 8),
                      Text(
                        l10n.managePantry,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.pantryModeDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appMutedTextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            hintText: l10n.addPantryItem,
                            prefixIcon: const Icon(Icons.add_outlined),
                            filled: true,
                            fillColor: context.appSubtleFillColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _add, child: Text(l10n.add)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : state.items.isEmpty
                      ? Center(
                          child: Text(
                            l10n.emptyPantry,
                            style: TextStyle(color: context.appMutedTextColor),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: state.items.length,
                          itemBuilder: (_, index) {
                            final item = state.items[index];
                            return ListTile(
                              leading: Checkbox(
                                value: item.available,
                                onChanged: (_) => ref
                                    .read(pantryProvider.notifier)
                                    .toggleAvailable(item),
                              ),
                              title: Text(item.name),
                              subtitle: Text(item.available
                                  ? l10n.availableForPlanning
                                  : l10n.hiddenFromPlanning),
                              trailing: IconButton(
                                tooltip: l10n.delete,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(pantryProvider.notifier)
                                    .deleteItem(item),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Macro badge ───────────────────────────────────────────────────────────────

class _MacroBadge extends StatelessWidget {
  const _MacroBadge(this.label, this.grams, this.color);
  final String label;
  final double grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label ${grams.round()}g',
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ── Grocery preview sheet ─────────────────────────────────────────────────────

class _AggIngredient {
  final String name;
  final int quantity;
  final String unit;
  final double totalGrams;
  const _AggIngredient({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.totalGrams,
  });

  String get amountLabel => unit.isEmpty ? '$quantity' : '$quantity $unit';
}

/// Lets the user choose how many people each planned day is cooking for, so the
/// grocery quantities are multiplied accurately per day.
class _PeoplePerDayDialog extends StatefulWidget {
  const _PeoplePerDayDialog({required this.days});
  final List<int> days;

  @override
  State<_PeoplePerDayDialog> createState() => _PeoplePerDayDialogState();
}

class _PeoplePerDayDialogState extends State<_PeoplePerDayDialog> {
  late final Map<int, int> _counts = {for (final d in widget.days) d: 1};

  void _setAll(int value) => setState(() {
        for (final d in widget.days) {
          _counts[d] = value;
        }
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.appSurfaceColor,
      title: Text(AppLocalizations.of(context).howManyPeople),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).peopleCountHelp,
                style: TextStyle(fontSize: 12, color: context.appMutedTextColor),
              ),
              const SizedBox(height: 8),
              ...widget.days.map((d) {
                final label = kWeekDays[(d - 1).clamp(0, 6)];
                return Row(
                  children: [
                    Expanded(child: Text(label)),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _counts[d]! > 1
                          ? () => setState(() => _counts[d] = _counts[d]! - 1)
                          : null,
                    ),
                    SizedBox(
                      width: 22,
                      child: Text('${_counts[d]}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _counts[d]! < 20
                          ? () => setState(() => _counts[d] = _counts[d]! + 1)
                          : null,
                    ),
                  ],
                );
              }),
              const Divider(),
              Row(
                children: [
                  Expanded(
                      child: Text(AppLocalizations.of(context).setAllDays)),
                  TextButton(onPressed: () => _setAll(1), child: const Text('1')),
                  TextButton(onPressed: () => _setAll(2), child: const Text('2')),
                  TextButton(onPressed: () => _setAll(4), child: const Text('4')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _counts),
          child: Text(AppLocalizations.of(context).generate),
        ),
      ],
    );
  }
}

class _GroceryPreviewSheet extends StatelessWidget {
  const _GroceryPreviewSheet({
    required this.ingredients,
    required this.onAdd,
    required this.onClearList,
  });

  final List<_AggIngredient> ingredients;
  final VoidCallback onAdd;
  final Future<void> Function() onClearList;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sorted = [...ingredients]
      ..sort((a, b) => b.totalGrams.compareTo(a.totalGrams));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.shopping_basket_outlined, size: 20),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.weeklyGroceryList,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('${sorted.length} ${l10n.ingredientsFromPlan}',
                          style: TextStyle(
                              fontSize: 12, color: context.appMutedTextColor)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final agg = sorted[i];
                  return ListTile(
                    minVerticalPadding: 8,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.green100.withValues(
                          alpha: context.isPremiumTheme ? 0.18 : 1,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shopping_basket_outlined,
                          size: 16, color: AppTheme.green700),
                    ),
                    title: Text(agg.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    trailing: Text(
                      agg.amountLabel,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.primary600),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_shopping_cart_outlined,
                          size: 18),
                      label: Text(l10n.addItemsToGroceryList(sorted.length)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () async {
                        await onClearList();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(AppLocalizations.of(context)
                                    .groceryListEmptied)),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label:
                          Text(AppLocalizations.of(context).emptyGroceryList),
                      style:
                          TextButton.styleFrom(foregroundColor: AppTheme.red500),
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

// ── Pick recipe sheet ──────────────────────────────────────────────────────────

class _PickRecipeSheet extends StatefulWidget {
  const _PickRecipeSheet({required this.candidates, required this.mealType});
  final List<Recipe> candidates;
  final RecipeMealType mealType;

  @override
  State<_PickRecipeSheet> createState() => _PickRecipeSheetState();
}

class _PickRecipeSheetState extends State<_PickRecipeSheet> {
  final _ctrl = TextEditingController();
  List<Recipe> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.candidates;
  }

  void _filter(String q) {
    final lower = q.toLowerCase();
    setState(() {
      _filtered = widget.candidates
          .where((r) =>
              lower.isEmpty ||
              r.name.toLowerCase().contains(lower) ||
              r.tags.any((t) => t.toLowerCase().contains(lower)))
          .toList();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(widget.mealType.emoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        l10n.pickRecipe(
                          _localizedMealTypeLabel(l10n, widget.mealType),
                        ),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                onChanged: _filter,
                decoration: InputDecoration(
                  hintText: l10n.searchRecipes,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: context.appSubtleFillColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final r = _filtered[i];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: r.image != null
                          ? (r.id.startsWith('custom:')
                              ? Image.file(
                                  File(r.image!),
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 52,
                                    height: 52,
                                    color: context.appSubtleFillColor,
                                    child: Center(
                                        child: Text(widget.mealType.emoji,
                                            style:
                                                const TextStyle(fontSize: 20))),
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: r.image!,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => Container(
                                      width: 52,
                                      height: 52,
                                      color: context.appSubtleFillColor),
                                  errorWidget: (_, __, ___) => Container(
                                    width: 52,
                                    height: 52,
                                    color: context.appSubtleFillColor,
                                    child: Center(
                                        child: Text(widget.mealType.emoji,
                                            style:
                                                const TextStyle(fontSize: 20))),
                                  ),
                                ))
                          : Container(
                              width: 52,
                              height: 52,
                              color: context.appSubtleFillColor,
                              child: Center(
                                  child: Text(widget.mealType.emoji,
                                      style: const TextStyle(fontSize: 20))),
                            ),
                    ),
                    title: Text(r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: r.hasMacros
                        ? Text(
                            '${r.calories} kcal · P${r.proteinG.round()}g · C${r.carbsG.round()}g · F${r.fatG.round()}g',
                            style: TextStyle(
                                fontSize: 10, color: context.appMutedTextColor))
                        : null,
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.pop(context, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
