import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/custom_meal.dart';
import '../models/dietary_restriction.dart';
import '../models/food_data.dart';
import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/user_prefs_provider.dart';
import '../services/barcode_lookup_service.dart';
import '../services/database_service.dart';
import '../services/ingredient_localizer.dart';
import '../services/recipe_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/tour_keys.dart';
import 'create_meal_screen.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _searchController = TextEditingController();
  bool _showMyMealsTab = false;
  List<CustomMeal> _customMeals = [];

  @override
  void initState() {
    super.initState();
    _loadCustomMeals();
  }

  Future<void> _loadCustomMeals() async {
    final meals = await DatabaseService.instance.getCustomMeals();
    if (mounted) setState(() => _customMeals = meals);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CustomMeal> _filteredCustomMeals(
    RecipeQueryState query,
    Set<DietaryRestriction> dietaryRestrictions,
  ) {
    final searchLower = query.search.toLowerCase();
    return _customMeals.where((meal) {
      if (searchLower.isNotEmpty &&
          !meal.name.toLowerCase().contains(searchLower)) {
        return false;
      }
      if (query.mealType != null) {
        final mealType = switch (meal.mealType) {
          MealType.breakfast => RecipeMealType.breakfast,
          MealType.lunch => RecipeMealType.lunch,
          MealType.dinner => RecipeMealType.dinner,
        };
        if (mealType != query.mealType) return false;
      }
      if (dietaryRestrictions.any((restriction) {
        return meal.ingredients.any(
          (ingredient) => restriction.matchesText(ingredient.foodLabel),
        );
      })) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openCreateMeal(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateMealScreen()),
    );
    _loadCustomMeals();
  }

  Widget _buildMyMealsTab(
    BuildContext context,
    AppLocalizations l10n,
    RecipeQueryState query,
    Set<DietaryRestriction> dietaryRestrictions,
  ) {
    final meals = _filteredCustomMeals(query, dietaryRestrictions);
    if (meals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.noSavedMeals,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.gray400),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: meals.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return _SectionHeader(
            title: l10n.myMeals,
            onAdd: () => _openCreateMeal(context),
          );
        }
        return _CustomMealCard(
          meal: meals[index - 1],
          onChanged: _loadCustomMeals,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(recipeQueryProvider);
    final resultsAsync = ref.watch(recipeResultsProvider);
    final dietaryRestrictions =
        ref.watch(userPrefsProvider).dietaryRestrictions;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recipes),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: TourKeys.recipeSearch,
              controller: _searchController,
              onChanged: (s) =>
                  ref.read(recipeQueryProvider.notifier).setSearch(s),
              decoration: InputDecoration(
                hintText: '${l10n.search} ${l10n.recipes.toLowerCase()}…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(recipeQueryProvider.notifier).setSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: context.appSubtleFillColor,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.appBorderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: context.appBorderColor),
                ),
              ),
              style: TextStyle(fontSize: 14, color: context.appTextColor),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Goal chips ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterChip(
                  label: l10n.allGoals,
                  selected: !_showMyMealsTab && query.goal == null,
                  onTap: () {
                    setState(() => _showMyMealsTab = false);
                    ref.read(recipeQueryProvider.notifier).setGoal(null);
                  },
                ),
                _FilterChip(
                  label: l10n.myMeals,
                  selected: _showMyMealsTab,
                  onTap: () {
                    setState(() => _showMyMealsTab = true);
                    ref.read(recipeQueryProvider.notifier).setGoal(null);
                  },
                ),
                for (final g in NutritionGoalType.values)
                  _FilterChip(
                    label: g.label,
                    emoji: g.emoji,
                    selected: !_showMyMealsTab && query.goal == g,
                    onTap: () {
                      setState(() => _showMyMealsTab = false);
                      ref.read(recipeQueryProvider.notifier).setGoal(g);
                    },
                  ),
              ],
            ),
          ),
          // ── Meal type chips ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterChip(
                  label: l10n.allMeals,
                  selected: query.mealType == null,
                  onTap: () =>
                      ref.read(recipeQueryProvider.notifier).setMealType(null),
                ),
                for (final m in RecipeMealType.values)
                  _FilterChip(
                    label: m.label,
                    emoji: m.emoji,
                    selected: query.mealType == m,
                    onTap: () =>
                        ref.read(recipeQueryProvider.notifier).setMealType(m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // ── Results ──
          Expanded(
            child: _showMyMealsTab
                ? _buildMyMealsTab(context, l10n, query, dietaryRestrictions)
                : resultsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (recipes) {
                      if (recipes.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              l10n.noRecipesMatch,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.gray400),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: recipes.length,
                        itemBuilder: (_, index) =>
                            _RecipeCard(recipe: recipes[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Section header ───────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onAdd});
  final String title;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.appMutedTextColor,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.primary100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14, color: context.primary700),
                    const SizedBox(width: 3),
                    Text('New',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.primary700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────── Custom meal card ───────────────────────

class _CustomMealCard extends ConsumerWidget {
  const _CustomMealCard({required this.meal, required this.onChanged});
  final CustomMeal meal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mealTypeEmoji = switch (meal.mealType) {
      MealType.breakfast => '🍳',
      MealType.lunch => '🥗',
      MealType.dinner => '🍽️',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context, ref),
        child: Row(
          children: [
            // Thumbnail
            SizedBox(
              width: 90,
              height: 90,
              child:
                  meal.imagePath != null && File(meal.imagePath!).existsSync()
                      ? Image.file(File(meal.imagePath!), fit: BoxFit.cover)
                      : Container(
                          color: context.appSubtleFillColor,
                          child: Center(
                            child: Text(mealTypeEmoji,
                                style: const TextStyle(fontSize: 28)),
                          ),
                        ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            meal.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.gray100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'My Meal',
                            style: TextStyle(
                              fontSize: 9,
                              color: context.appMutedTextColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${meal.ingredients.length} ingredient${meal.ingredients.length == 1 ? '' : 's'} · ${meal.mealType.displayName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appMutedTextColor,
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

  void _openDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomMealDetailSheet(
        meal: meal,
        onChanged: onChanged,
        onLogged: () {
          ref.read(dailyIntakeProvider.notifier).load();
          ref.read(historyProvider.notifier).load();
        },
      ),
    );
  }
}

// ─────────────────────── Custom meal detail / log sheet ───────────────────────

class _CustomMealDetailSheet extends ConsumerStatefulWidget {
  const _CustomMealDetailSheet({
    required this.meal,
    required this.onChanged,
    required this.onLogged,
  });
  final CustomMeal meal;
  final VoidCallback onChanged;
  final VoidCallback onLogged;

  @override
  ConsumerState<_CustomMealDetailSheet> createState() =>
      _CustomMealDetailSheetState();
}

class _CustomMealDetailSheetState
    extends ConsumerState<_CustomMealDetailSheet> {
  List<FoodData> _allFoods = [];
  late List<MealIngredient> _ingredients;
  late List<TextEditingController> _gramsControllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ingredients = List<MealIngredient>.from(widget.meal.ingredients);
    _gramsControllers = _ingredients
        .map((i) => TextEditingController(text: i.grams.round().toString()))
        .toList();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    final foods = await DatabaseService.instance.getAllFoods();
    if (mounted) setState(() => _allFoods = foods);
  }

  @override
  void dispose() {
    for (final c in _gramsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, double> get _kcalMap =>
      {for (final f in _allFoods) f.label: f.kcalPer100g};

  double get _totalKcal {
    final map = _kcalMap;
    double total = 0;
    for (var i = 0; i < _ingredients.length; i++) {
      final g =
          double.tryParse(_gramsControllers[i].text) ?? _ingredients[i].grams;
      total += (map[_ingredients[i].foodLabel] ?? 0) * g / 100.0;
    }
    return total;
  }

  Future<void> _logMeal() async {
    setState(() => _saving = true);
    final foods = <DetectedFood>[];
    final map = _kcalMap;
    for (var i = 0; i < _ingredients.length; i++) {
      final g =
          double.tryParse(_gramsControllers[i].text) ?? _ingredients[i].grams;
      if (g <= 0) continue;
      final label = _ingredients[i].foodLabel;
      final kcalPer100 = map[label] ?? 0.0;
      final avg = g / 100.0 * kcalPer100;
      foods.add(DetectedFood(
        label: label,
        volumeCm3: g,
        caloriesMin: avg * 0.95,
        caloriesMax: avg * 1.05,
      ));
    }
    if (foods.isEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No ingredients to log.')));
      return;
    }
    final scan = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'custom_meal',
      foods: foods,
    );
    await DatabaseService.instance.insertScanResult(scan);
    widget.onLogged();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logged "${widget.meal.name}".')));
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;
    final mealTypeEmoji = switch (widget.meal.mealType) {
      MealType.breakfast => '🍳',
      MealType.lunch => '🥗',
      MealType.dinner => '🍽️',
    };
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: context.appSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: context.appBorderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            if (widget.meal.imagePath != null &&
                File(widget.meal.imagePath!).existsSync())
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Image.file(
                  File(widget.meal.imagePath!),
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(mealTypeEmoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.meal.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  // Edit button
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CreateMealScreen(meal: widget.meal)));
                      widget.onChanged();
                    },
                  ),
                  // Delete button
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.appBorderColor),
            // Ingredients list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _ingredients.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 12, color: context.appBorderColor),
                itemBuilder: (_, i) {
                  final ing = _ingredients[i];
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          ing.foodLabel,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _gramsControllers[i],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(8))),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('g',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(height: 1, color: context.appBorderColor),
            // Bottom bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total: ${_totalKcal.round()} kcal',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _logMeal,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Log Meal'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Meal?'),
        content: Text('Remove "${widget.meal.name}" from your saved meals?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseService.instance.deleteCustomMeal(widget.meal.id!);
              widget.onChanged();
              if (mounted) Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Filter chip ───────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final maxChipWidth = (MediaQuery.sizeOf(context).width * 0.48)
        .clamp(112.0, 190.0)
        .toDouble();
    final selectedFill = visual.premium
        ? visual.primaryAccent.withValues(alpha: 0.22)
        : context.primary500;
    final selectedText = visual.premium ? visual.primaryAccent : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxChipWidth),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? selectedFill : context.appSurfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? context.primary500 : context.appBorderColor,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (emoji != null) ...[
                    Text(emoji!, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        color: selected ? selectedText : context.appTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipeBadge extends StatelessWidget {
  const _RecipeBadge({
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isPremiumTheme ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: color.withValues(alpha: context.isPremiumTheme ? 0.34 : 0.18),
        ),
      ),
      child: Text(
        label,
        maxLines: 2,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          height: 1.1,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ─────────────────────── Recipe card ───────────────────────

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Row(
          children: [
            if (recipe.image != null)
              SizedBox(
                width: 90,
                height: 90,
                child: _RecipeImage(path: recipe.image!),
              )
            else
              Container(
                width: 90,
                height: 90,
                color: context.appSubtleFillColor,
                child: Center(
                  child: Text(
                    recipe.mealType.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 13, color: context.appMutedTextColor),
                        Text('${recipe.minutes} min',
                            style: TextStyle(
                                fontSize: 11,
                                color: context.appMutedTextColor)),
                        if (recipe.hasMacros) ...[
                          Icon(Icons.local_fire_department_outlined,
                              size: 13, color: context.appMutedTextColor),
                          Text('${recipe.calories} kcal',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.appMutedTextColor)),
                          if (recipe.healthScore > 0) ...[
                            _HealthScoreChip(score: recipe.healthScore),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: recipe.goals
                          .take(3)
                          .map((g) => _RecipeBadge(
                                label: g.label,
                                color: g.color,
                                compact: true,
                              ))
                          .toList(),
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

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipe: recipe)),
    );
  }
}

// ─────────────────────── Detail page ───────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.appSubtleFillColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: context.appMutedTextColor),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.appTextColor)),
        ],
      ),
    );
  }
}

class _HealthScoreChip extends StatelessWidget {
  const _HealthScoreChip({required this.score});
  final int score;

  Color get _color {
    if (score >= 80) return AppTheme.green600;
    if (score >= 60) return AppTheme.amber600;
    if (score >= 40) return Colors.orange.shade700;
    return AppTheme.red500;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$score/100',
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecipeImage extends StatelessWidget {
  const _RecipeImage({required this.path, this.overlay = false});
  final String path;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final image = path.startsWith('assets/')
        ? Image.asset(path, fit: BoxFit.cover)
        : CachedNetworkImage(
            imageUrl: path,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                Container(color: context.appSubtleFillColor),
            errorWidget: (_, __, ___) =>
                Container(color: context.appSubtleFillColor),
          );

    if (!overlay) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Container(color: Colors.black26),
      ],
    );
  }
}

class _HealthScorePanel extends StatelessWidget {
  const _HealthScorePanel({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final score = recipe.healthScore.clamp(0, 100);
    final color = score >= 80
        ? AppTheme.green600
        : score >= 60
            ? AppTheme.amber600
            : score >= 40
                ? Colors.orange.shade700
                : AppTheme.red500;
    final reason = recipe.healthScoreReason.trim().isEmpty
        ? 'Score based on calories, protein, fiber, sugar, saturated fat, sodium, ingredient quality, and goal fit.'
        : recipe.healthScoreReason;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.appSurfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              '$score',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Food score',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.appTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: context.appMutedTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  int _selectedServings = 1;

  /// Scale an ingredient amount string by the ratio of selected/recipe servings.
  String _scaleAmount(String amount, int selected, int original) {
    if (selected == original) return amount;
    final ratio = selected / original;
    String format(double value, String suffix) {
      final text = value == value.roundToDouble()
          ? value.round().toString()
          : value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      return '$text$suffix';
    }

    // Try to find a leading number (int, decimal, fraction, or mixed fraction).
    final mixedFractionRegex = RegExp(r'^(\d+)\s+(\d+)/(\d+)(.*)$');
    final fractionRegex = RegExp(r'^(\d+)/(\d+)(.*)$');
    final numberRegex = RegExp(r'^(\d+\.?\d*)(.*)$');
    final mixedMatch = mixedFractionRegex.firstMatch(amount);
    if (mixedMatch != null) {
      final whole = int.parse(mixedMatch.group(1)!);
      final num = int.parse(mixedMatch.group(2)!);
      final den = int.parse(mixedMatch.group(3)!);
      final suffix = mixedMatch.group(4) ?? '';
      return format((whole + (num / den)) * ratio, suffix);
    }
    final fractionMatch = fractionRegex.firstMatch(amount);
    if (fractionMatch != null) {
      final num = int.parse(fractionMatch.group(1)!);
      final den = int.parse(fractionMatch.group(2)!);
      final suffix = fractionMatch.group(3) ?? '';
      return format((num / den) * ratio, suffix);
    }
    final match = numberRegex.firstMatch(amount);
    if (match != null) {
      final value = double.parse(match.group(1)!);
      final suffix = match.group(2) ?? '';
      return format(value * ratio, suffix);
    }
    return amount; // non-numeric like "to taste", "pinch"
  }

  @override
  void initState() {
    super.initState();
    _selectedServings = 1;
  }

  // Nutrition always shows 1 person's portion (recipe base serving)
  double get _carbsForServing =>
      widget.recipe.carbsPerServing(widget.recipe.servings);

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final ingredientLang = AppLocalizations.of(context).locale.languageCode;
    final prefs = ref.watch(userPrefsProvider);
    final isDiabetic = prefs.nutritionGoal == NutritionGoalType.diabetes;
    final icr = prefs.icrGramsPerUnit; // pass raw; 0.0 = not set
    final bolusUnits = _carbsForServing / (icr <= 0 ? 10.0 : icr);
    return Scaffold(
      backgroundColor: context.appPanelColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: r.image != null ? 240 : 0,
            pinned: true,
            flexibleSpace: r.image != null
                ? FlexibleSpaceBar(
                    background: _RecipeImage(path: r.image!, overlay: true),
                  )
                : null,
            title: Text(r.name, style: const TextStyle(fontSize: 15)),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Serving selector ──
                _ServingSelector(
                  servings: _selectedServings,
                  onChanged: (v) => setState(() => _selectedServings = v),
                ),
                const SizedBox(height: 16),
                // ── Meta chips ──
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(Icons.timer_outlined, '${r.minutes} min'),
                    _MetaChip(
                      Icons.restaurant,
                      '$_selectedServings ${_selectedServings == 1 ? 'serving' : 'servings'}',
                    ),
                    if (r.hasMacros) ...[
                      _MetaChip(Icons.local_fire_department_outlined,
                          '${r.caloriesPerServing(r.servings)} kcal per person'),
                    ],
                  ],
                ),
                if (r.hasMacros) ...[
                  const SizedBox(height: 16),
                  if (r.healthScore > 0) ...[
                    _HealthScorePanel(recipe: r),
                    const SizedBox(height: 16),
                  ],
                  // ── Macro bar (per person, does not change with serving selector) ──
                  Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('Per person',
                        style: TextStyle(
                            fontSize: 11, color: context.appMutedTextColor)),
                  ),
                  _NutritionTable(
                    recipe: r,
                    servings: r.servings,
                  ),
                ],
                // ── Bolus display for diabetics ──
                if (isDiabetic && r.hasMacros) ...[
                  const SizedBox(height: 12),
                  _BolusCard(
                    carbsG: _carbsForServing,
                    bolusUnits: bolusUnits,
                    icr: icr,
                    glycemicIndex: r.glycemicIndex,
                  ),
                  if (_selectedServings > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.amber100.withValues(
                          alpha: context.isPremiumTheme ? 0.16 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppTheme.amber500.withValues(alpha: 0.38),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: AppTheme.amber600),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Multiple servings: verify portion accuracy before bolusing.',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.amber700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                // ── Ingredients ──
                Text('Ingredients',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.appTextColor)),
                const SizedBox(height: 10),
                ...r.ingredients.map((i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 6, right: 10),
                            decoration: BoxDecoration(
                              color: context.primary500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: IngredientLocalizer.localize(
                                    i.name,
                                    targetLang: ingredientLang,
                                    sourceLang: r.language,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: context.appTextColor,
                                  ),
                                ),
                                if (i.amount.isNotEmpty)
                                  TextSpan(
                                    text:
                                        '  ${_scaleAmount(i.amount, _selectedServings, r.servings)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.appMutedTextColor,
                                    ),
                                  ),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 24),
                // ── Steps ──
                Text('Preparation',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.appTextColor)),
                const SizedBox(height: 10),
                ...r.steps.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: context.appSubtleFillColor,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: context.appBorderColor),
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: context.primary700,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: context.appTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
      // ── Log button + Swap ──
      bottomNavigationBar: r.hasMacros
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    // AI Swap button
                    OutlinedButton.icon(
                      onPressed: () => _showSwapSheet(context, r),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Swap'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _logRecipe(
                          context,
                          isDiabetic: isDiabetic,
                          bolusUnits: bolusUnits,
                          icr: icr,
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: Text(
                          isDiabetic
                              ? 'Log Meal · ${r.caloriesPerServing(r.servings)} kcal · ${bolusUnits.toStringAsFixed(1)}U'
                              : 'Log Meal · ${r.caloriesPerServing(r.servings)} kcal',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
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

  Future<void> _showSwapSheet(BuildContext context, Recipe current) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiSwapSheet(current: current),
    );
  }

  void _logRecipe(
    BuildContext context, {
    required bool isDiabetic,
    required double bolusUnits,
    required double icr,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogRecipeSheet(
        recipe: widget.recipe,
        servings: _selectedServings,
        isDiabetic: isDiabetic,
        bolusUnits: bolusUnits,
        icr: icr,
        carbsPerServing: _carbsForServing,
        onLogged: () {
          // Reload providers after logging
          ref.read(dailyIntakeProvider.notifier).load();
          ref.read(historyProvider.notifier).load();
        },
      ),
    );
  }
}

class _LogRecipeSheet extends ConsumerStatefulWidget {
  const _LogRecipeSheet({
    required this.recipe,
    required this.servings,
    required this.isDiabetic,
    required this.bolusUnits,
    required this.icr,
    required this.carbsPerServing,
    required this.onLogged,
  });

  final Recipe recipe;
  final int servings;
  final bool isDiabetic;
  final double bolusUnits;
  final double icr;
  final double carbsPerServing;
  final VoidCallback onLogged;

  @override
  ConsumerState<_LogRecipeSheet> createState() => _LogRecipeSheetState();
}

class _LogRecipeSheetState extends ConsumerState<_LogRecipeSheet> {
  // Mutable working copy of ingredients — user can add / remove
  late List<RecipeIngredient> _ingredients;
  final List<TextEditingController> _controllers = [];
  final List<TextEditingController> _nameControllers = [];
  List<FoodData> _allFoods = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ingredients = List<RecipeIngredient>.from(widget.recipe.ingredients);
    for (final _ in _ingredients) {
      _controllers.add(TextEditingController());
      _nameControllers.add(TextEditingController());
    }
    _initDefaults();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final c in _nameControllers) c.dispose();
    super.dispose();
  }

  void _removeIngredient(int index) {
    final ctrl = _controllers.removeAt(index);
    final nameCtrl = _nameControllers.removeAt(index);
    ctrl.dispose();
    nameCtrl.dispose();
    setState(() => _ingredients.removeAt(index));
  }

  void _addIngredient() {
    setState(() {
      _ingredients
          .add(const RecipeIngredient(name: '', amount: '', grams: 0.0));
      _controllers.add(TextEditingController(text: '100'));
      _nameControllers.add(TextEditingController());
    });
  }

  Future<void> _scanBarcodeForIngredient() async {
    // Connectivity check
    try {
      final result = await InternetAddress.lookup('world.openfoodfacts.org')
          .timeout(const Duration(seconds: 3));
      if (result.isEmpty || result[0].rawAddress.isEmpty) throw Exception();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning requires an internet connection.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await BarcodeLookupService.instance.scanAndLookup();
    if (result == null || !mounted) return;

    // Add to food DB if not already present
    var existing = await DatabaseService.instance.getFoodByLabel(result.name);
    if (existing == null) {
      final lowerName = result.name.toLowerCase();
      final isDrink = const [
        'water',
        'juice',
        'drink',
        'cola',
        'soda',
        'milk',
        'tea',
        'coffee',
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
      _allFoods = await DatabaseService.instance.getAllFoods();
    }

    final grams = result.servingGrams ?? 100.0;
    setState(() {
      _ingredients.add(RecipeIngredient(
        name: result.name,
        amount: '${grams.round()}g',
        grams: grams,
      ));
      _controllers.add(TextEditingController(text: grams.round().toString()));
      _nameControllers.add(TextEditingController(text: result.name));
    });
  }

  Future<void> _initDefaults() async {
    _allFoods = await DatabaseService.instance.getAllFoods();

    // Ensure plant milk ingredients map to liquid milk entries instead of nuts.
    final hasAlmondMilk = _allFoods.any(
      (f) => _normalizeIngredient(f.label) == 'almond milk',
    );
    if (!hasAlmondMilk) {
      _allFoods = [
        ..._allFoods,
        const FoodData(
          label: 'almond milk',
          densityMin: 1.00,
          densityMax: 1.03,
          kcalPer100g: 15,
          category: 'drink',
          proteinPer100g: 0.5,
          carbsPer100g: 0.6,
          fatPer100g: 1.2,
          perMl: true,
        ),
        const FoodData(
          label: 'almond milk unsweetened',
          densityMin: 1.00,
          densityMax: 1.03,
          kcalPer100g: 15,
          category: 'drink',
          proteinPer100g: 0.5,
          carbsPer100g: 0.6,
          fatPer100g: 1.2,
          perMl: true,
        ),
      ];
    }

    for (var i = 0; i < _ingredients.length; i++) {
      final ing = _ingredients[i];
      _nameControllers[i].text = ing.name;
      // Use the numeric grams field directly if available, otherwise parse from amount string
      final grams = ing.grams > 0
          ? (ing.grams * widget.servings / widget.recipe.servings)
          : _estimateGrams(
              ing.amount, widget.servings, widget.recipe.servings, ing.name);
      _controllers[i].text = grams.round().toString();
    }
    setState(() {});
  }

  double _estimateGrams(
      String amount, int selected, int original, String name) {
    // Scale simple numeric amounts first (fractional support)
    final fractionRegex = RegExp(r'^(\d+)\s+(\d+)/(\d+)(.*) ');
    final simpleFraction = RegExp(r'^(\d+)/(\d+)(.*) ');
    final numberRegex = RegExp(r'^(\d+\.?\d*)(.*) ');

    String scaled = amount.trim();
    if (selected != original) {
      final ratio = selected / original;
      final fracMatch = fractionRegex.firstMatch(scaled);
      if (fracMatch != null) {
        final whole = int.parse(fracMatch.group(1)!);
        final num = int.parse(fracMatch.group(2)!);
        final den = int.parse(fracMatch.group(3)!);
        final suffix = fracMatch.group(4) ?? '';
        final val = (whole + (num / den)) * ratio;
        scaled = (val == val.roundToDouble()
                ? val.round().toString()
                : val.toStringAsFixed(1)) +
            suffix;
      } else {
        final fracMatch2 = simpleFraction.firstMatch(scaled);
        if (fracMatch2 != null) {
          final num = int.parse(fracMatch2.group(1)!);
          final den = int.parse(fracMatch2.group(2)!);
          final suffix = fracMatch2.group(3) ?? '';
          final val = (num / den) * ratio;
          scaled = (val == val.roundToDouble()
                  ? val.round().toString()
                  : val.toStringAsFixed(1)) +
              suffix;
        } else {
          final match = numberRegex.firstMatch(scaled);
          if (match != null) {
            final v = double.tryParse(match.group(1)!) ?? 0.0;
            final suffix = match.group(2) ?? '';
            final val = v * ratio;
            scaled = (val == val.roundToDouble()
                    ? val.round().toString()
                    : val.toStringAsFixed(1)) +
                suffix;
          }
        }
      }
    }

    // Extract numeric value and unit
    final numMatch =
        RegExp(r'(\d+\.?\d*|\d+\/\d+|\d+\s+\d+\/\d+)').firstMatch(scaled);
    double value = 0.0;
    if (numMatch != null) {
      final raw = numMatch.group(0)!.trim();
      if (raw.contains('/')) {
        // fraction or mixed
        if (raw.contains(' ')) {
          final parts = raw.split(' ');
          final whole = double.tryParse(parts[0]) ?? 0.0;
          final fracParts = parts[1].split('/');
          final num = double.tryParse(fracParts[0]) ?? 0.0;
          final den = double.tryParse(fracParts[1]) ?? 1.0;
          value = whole + (num / den);
        } else {
          final fracParts = raw.split('/');
          final num = double.tryParse(fracParts[0]) ?? 0.0;
          final den = double.tryParse(fracParts[1]) ?? 1.0;
          value = num / den;
        }
      } else {
        value = double.tryParse(raw.replaceAll(',', '.')) ?? 0.0;
      }
    }

    final after = scaled.substring(numMatch?.end ?? 0).toLowerCase();
    final unitMatch = RegExp(r'([a-zµ]+)').firstMatch(after);
    final unit = unitMatch?.group(1) ?? '';

    double grams = 0.0;
    if (unit.contains('kg'))
      grams = value * 1000.0;
    else if (unit.contains('g'))
      grams = value;
    else if (unit.contains('ml'))
      grams = value; // assume 1 ml ≈ 1 g
    else if (unit.contains('tbsp') || unit.contains('tablespoon'))
      grams = value * 15.0;
    else if (unit.contains('tsp') || unit.contains('teaspoon'))
      grams = value * 5.0;
    else if (unit.contains('cup'))
      grams = value * 240.0;
    else if (unit.contains('oz'))
      grams = value * 28.35;
    else if (unit.contains('lb'))
      grams = value * 453.592;
    else if (value > 0) {
      final lname = name.toLowerCase();
      if (lname.contains('egg'))
        grams = value * 50.0;
      else if (lname.contains('slice'))
        grams = value * 30.0;
      else
        grams = value * 100.0; // fallback guess
    }

    // Clamp to reasonable range
    if (grams < 1) grams = 1;
    if (grams > 2000) grams = 2000;
    return grams;
  }

  /// Local copy of the serving-scale helper used in the detail screen.
  String _scaleAmountLocal(String amount, int selected, int original) {
    if (selected == original) return amount;
    final ratio = selected / original;
    final fractionRegex = RegExp(r'^(\d+)/(\d+)(.*) ');
    final numberRegex = RegExp(r'^(\d+\.?\d*)(.*) ');
    final fractionMatch = fractionRegex.firstMatch(amount);
    if (fractionMatch != null) {
      final num = int.parse(fractionMatch.group(1)!);
      final den = int.parse(fractionMatch.group(2)!);
      final scaled = (num / den) * ratio;
      final suffix = fractionMatch.group(3) ?? '';
      return scaled == scaled.roundToDouble()
          ? '${scaled.round()}$suffix'
          : '${scaled.toStringAsFixed(1)}$suffix';
    }
    final match = numberRegex.firstMatch(amount);
    if (match != null) {
      final value = double.parse(match.group(1)!);
      final suffix = match.group(2) ?? '';
      final scaled = value * ratio;
      return scaled == scaled.roundToDouble()
          ? '${scaled.round()}$suffix'
          : '${scaled.toStringAsFixed(1)}$suffix';
    }
    return amount;
  }

  double _parseControllerValue(int idx) {
    final t = _controllers[idx].text.trim();
    if (t.isEmpty) return 0.0;
    return double.tryParse(t.replaceAll(',', '.')) ?? 0.0;
  }

  String _normalizeIngredient(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  FoodData _resolveFoodMatch(String ingredientName) {
    final normalizedIngredient = _normalizeIngredient(ingredientName);
    if (normalizedIngredient.isEmpty) {
      return _allFoods.firstWhere(
        (f) => f.label.toLowerCase() == 'others',
        orElse: () => _allFoods.first,
      );
    }

    FoodData? exactMatch;
    for (final food in _allFoods) {
      if (_normalizeIngredient(food.label) == normalizedIngredient) {
        exactMatch = food;
        break;
      }
    }
    if (exactMatch != null) return exactMatch;

    final isMilkIngredient = normalizedIngredient.contains('milk');
    FoodData? best;
    double bestScore = -1;

    for (final food in _allFoods) {
      final labelNorm = _normalizeIngredient(food.label);
      if (labelNorm.isEmpty) continue;

      if (!normalizedIngredient.contains(labelNorm) &&
          !labelNorm.contains(normalizedIngredient)) {
        continue;
      }

      final ingredientTokens =
          normalizedIngredient.split(' ').where((t) => t.isNotEmpty).toSet();
      final labelTokens =
          labelNorm.split(' ').where((t) => t.isNotEmpty).toSet();
      final overlap = ingredientTokens.intersection(labelTokens).length;
      var score = overlap * 100 + labelNorm.length;

      if (isMilkIngredient && !labelNorm.contains('milk')) {
        score -= 500;
      }
      if (normalizedIngredient.contains('almond milk') &&
          labelNorm == 'almond') {
        score -= 1000;
      }

      if (score > bestScore) {
        bestScore = score.toDouble();
        best = food;
      }
    }

    if (best != null) return best;

    return _allFoods.firstWhere(
      (f) => f.label.toLowerCase() == 'others',
      orElse: () => _allFoods.first,
    );
  }

  double get _totalKcal {
    if (_allFoods.isEmpty) return 0.0;
    double sum = 0.0;
    for (var i = 0; i < _ingredients.length; i++) {
      final g = _parseControllerValue(i);
      if (g <= 0) continue;
      final name = _nameControllers[i].text.trim().isEmpty
          ? _ingredients[i].name
          : _nameControllers[i].text.trim();
      final fd = _resolveFoodMatch(name.toLowerCase());
      sum += g / 100.0 * fd.kcalPer100g;
    }
    return sum;
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final foods = <DetectedFood>[];

    if (_allFoods.isEmpty) {
      _allFoods = await DatabaseService.instance.getAllFoods();
    }

    for (var i = 0; i < _ingredients.length; i++) {
      final grams = _parseControllerValue(i);
      if (grams <= 0) continue;
      final ingredientName = _nameControllers[i].text.trim().isEmpty
          ? _ingredients[i].name
          : _nameControllers[i].text.trim();
      final fd = _resolveFoodMatch(ingredientName);

      final kcalAvg = grams / 100.0 * fd.kcalPer100g;
      final kcalMin = kcalAvg * 0.95;
      final kcalMax = kcalAvg * 1.05;

      foods.add(DetectedFood(
        label: fd.label,
        volumeCm3: grams,
        caloriesMin: double.parse(kcalMin.toStringAsFixed(1)),
        caloriesMax: double.parse(kcalMax.toStringAsFixed(1)),
      ));
    }

    if (foods.isEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No ingredient amounts provided.')));
      return;
    }

    final scan = ScanResult(
        timestamp: DateTime.now(), depthMode: 'recipe', foods: foods);
    try {
      await DatabaseService.instance.insertScanResult(scan);
      widget.onLogged();
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Logged recipe.')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to log recipe: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(top: BorderSide(color: context.appBorderColor)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('Log: ${widget.recipe.name}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700))),
                    // Dismiss keyboard button
                    if (keyboardVisible)
                      IconButton(
                        icon: const Icon(Icons.keyboard_hide, size: 22),
                        tooltip: 'Dismiss keyboard',
                        onPressed: () => FocusScope.of(context).unfocus(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'Adjust grams per ingredient (cooking for ${widget.servings})',
                    style: TextStyle(color: context.appMutedTextColor)),
                if (widget.isDiabetic) ...[
                  const SizedBox(height: 10),
                  // ICR-not-set warning
                  if (widget.icr <= 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.red100.withValues(
                          alpha: context.isPremiumTheme ? 0.18 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red.shade600, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Your ICR is not set. Bolus calculations will be inaccurate.\n'
                              'Go to Settings → Diabetes to set your personal ICR.',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _BolusCard(
                    carbsG: widget.carbsPerServing,
                    bolusUnits: widget.bolusUnits,
                    icr: widget.icr <= 0 ? 10.0 : widget.icr,
                    glycemicIndex: widget.recipe.glycemicIndex,
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _ingredients.length + 1, // +1 for add row
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      // Last slot = "Add ingredient" buttons
                      if (i == _ingredients.length) {
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _scanBarcodeForIngredient,
                              icon: const Icon(Icons.qr_code_scanner, size: 18),
                              label: const Text('Scan Barcode'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addIngredient,
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Add Manually'),
                            ),
                          ],
                        );
                      }
                      final ing = _ingredients[i];
                      return Row(
                        children: [
                          // Remove button
                          GestureDetector(
                            onTap: () => _removeIngredient(i),
                            child: const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 20),
                          ),
                          const SizedBox(width: 8),
                          // Name field (editable)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _nameControllers[i],
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    hintText: ing.name.isEmpty
                                        ? 'Ingredient name'
                                        : ing.name,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 0, vertical: 4),
                                    border: InputBorder.none,
                                  ),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                if (ing.amount.isNotEmpty)
                                  Text(
                                    _scaleAmountLocal(
                                        ing.amount,
                                        widget.servings,
                                        widget.recipe.servings),
                                    style: TextStyle(
                                        color: context.appMutedTextColor,
                                        fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Grams field
                          SizedBox(
                            width: 90,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controllers[i],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textInputAction: TextInputAction.done,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(8))),
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('g',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text('Total: ${_totalKcal.round()} kcal',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700))),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Log Meal'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── Serving selector ───────────────────────

class _ServingSelector extends StatelessWidget {
  const _ServingSelector({required this.servings, required this.onChanged});
  final int servings;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          'Cooking for',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.appTextColor,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.appSubtleFillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.appBorderColor),
          ),
          child: Wrap(
            children: List.generate(6, (i) {
              final n = i + 1;
              final selected = n == servings;
              return GestureDetector(
                onTap: () => onChanged(n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? context.primary500 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : context.appMutedTextColor,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────── Nutrition table ───────────────────────

class _NutritionTable extends StatefulWidget {
  const _NutritionTable({required this.recipe, required this.servings});
  final Recipe recipe;
  final int servings;

  @override
  State<_NutritionTable> createState() => _NutritionTableState();
}

class _NutritionTableState extends State<_NutritionTable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final s = widget.servings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSubtleFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorderColor),
      ),
      child: Column(
        children: [
          _NutrientRow('Protein', r.proteinPerServing(s), 'g'),
          _NutrientRow('Carbs', r.carbsPerServing(s), 'g'),
          _NutrientRow('Fat', r.fatPerServing(s), 'g'),
          if (r.fiberG > 0) _NutrientRow('Fiber', r.fiberPerServing(s), 'g'),
          if (r.sugarG > 0) _NutrientRow('Sugar', r.sugarPerServing(s), 'g'),
          if (_expanded) ...[
            const Divider(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Vitamins & Minerals',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            if (r.vitaminAUg > 0)
              _NutrientRow('Vitamin A', r.vitaminAUg / s, 'µg'),
            if (r.vitaminCMg > 0)
              _NutrientRow('Vitamin C', r.vitaminCMg / s, 'mg'),
            if (r.vitaminDUg > 0)
              _NutrientRow('Vitamin D', r.vitaminDUg / s, 'µg'),
            if (r.vitaminEMg > 0)
              _NutrientRow('Vitamin E', r.vitaminEMg / s, 'mg'),
            if (r.vitaminKUg > 0)
              _NutrientRow('Vitamin K', r.vitaminKUg / s, 'µg'),
            if (r.vitaminB12Ug > 0)
              _NutrientRow('Vitamin B12', r.vitaminB12Ug / s, 'µg'),
            if (r.folateUg > 0) _NutrientRow('Folate', r.folateUg / s, 'µg'),
            if (r.calciumMg > 0) _NutrientRow('Calcium', r.calciumMg / s, 'mg'),
            if (r.ironMg > 0) _NutrientRow('Iron', r.ironMg / s, 'mg'),
            if (r.magnesiumMg > 0)
              _NutrientRow('Magnesium', r.magnesiumMg / s, 'mg'),
            if (r.potassiumMg > 0)
              _NutrientRow('Potassium', r.potassiumMg / s, 'mg'),
            if (r.zincMg > 0) _NutrientRow('Zinc', r.zincMg / s, 'mg'),
            if (r.sodiumMg > 0) _NutrientRow('Sodium', r.sodiumMg / s, 'mg'),
          ],
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _expanded ? 'Show less' : 'Vitamins & minerals',
                  style:
                      TextStyle(fontSize: 11, color: context.appMutedTextColor),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: context.appMutedTextColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow(this.label, this.value, this.unit);
  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: context.appMutedTextColor,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('${value.round()}$unit',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─────────────────────── Bolus card ───────────────────────

class _BolusCard extends StatelessWidget {
  const _BolusCard({
    required this.carbsG,
    required this.bolusUnits,
    required this.icr,
    this.glycemicIndex = 0,
  });
  final double carbsG;
  final double bolusUnits;
  final double icr;
  final int glycemicIndex;

  @override
  Widget build(BuildContext context) {
    String giLabel = '';
    if (glycemicIndex > 0) {
      if (glycemicIndex <= 35)
        giLabel = 'Low GI ($glycemicIndex)';
      else if (glycemicIndex <= 55)
        giLabel = 'Medium GI ($glycemicIndex)';
      else
        giLabel = 'High GI ($glycemicIndex)';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.primary50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.primary200),
      ),
      child: Row(
        children: [
          Icon(Icons.water_drop, size: 18, color: context.primary600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested bolus: ${bolusUnits.toStringAsFixed(1)} U',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.primary700,
                  ),
                ),
                Text(
                  '${carbsG.round()}g carbs ÷ ICR ${icr.round()}${giLabel.isNotEmpty ? ' · $giLabel' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.primary600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── AI Meal Swap Sheet ───────────────────────────────────

/// Professional bottom sheet that surfaces up to 5 nutritionally-smart
/// alternative recipes for the currently-viewed recipe.
///
/// Swap logic:
///   • Same meal type as the current recipe
///   • Matches the same nutrition goals
///   • Sorted by a benefit score:  Δprotein×2 − Δcalories×0.5 − Δcarbs×0.3
///   • Each card shows a before→after macro diff with coloured indicators
class _AiSwapSheet extends ConsumerStatefulWidget {
  const _AiSwapSheet({required this.current});
  final Recipe current;

  @override
  ConsumerState<_AiSwapSheet> createState() => _AiSwapSheetState();
}

class _AiSwapSheetState extends ConsumerState<_AiSwapSheet> {
  List<_SwapCandidate>? _candidates;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    try {
      final all = await RecipeRepository.instance.query(
        mealType: widget.current.mealType,
        limit: 200,
      );

      final current = widget.current;
      final swaps = <_SwapCandidate>[];

      for (final r in all) {
        if (r.id == current.id) continue;
        if (!r.hasMacros) continue;

        // Build benefit reasons
        final reasons = <String>[];
        final deltaProtein = r.proteinG - current.proteinG;
        final deltaCalories = r.calories - current.calories;
        final deltaCarbs = r.carbsG - current.carbsG;
        final deltaFat = r.fatG - current.fatG;
        final deltaFiber = r.fiberG - current.fiberG;

        // Score: reward protein gain, penalise calorie & carb increase
        final score = deltaProtein * 2 -
            deltaCalories * 0.5 -
            deltaCarbs * 0.3 +
            deltaFiber * 1.5;

        if (deltaProtein > 3) {
          reasons.add('+${deltaProtein.abs().round()}g protein');
        }
        if (deltaCalories < -50) {
          reasons.add('−${deltaCalories.abs().round()} kcal');
        }
        if (deltaCarbs < -10) {
          reasons.add('−${deltaCarbs.abs().round()}g carbs');
        }
        if (deltaFiber > 2) {
          reasons.add('+${deltaFiber.abs().round()}g fiber');
        }
        if (deltaFat < -5) {
          reasons.add('−${deltaFat.abs().round()}g fat');
        }
        if (r.minutes < current.minutes - 5) {
          reasons.add('${r.minutes} min prep');
        }

        if (reasons.isEmpty && score < 0) continue; // not beneficial enough

        swaps.add(_SwapCandidate(
          recipe: r,
          score: score,
          deltaCalories: deltaCalories,
          deltaProtein: deltaProtein,
          deltaCarbs: deltaCarbs,
          deltaFat: deltaFat,
          deltaFiber: deltaFiber,
          reasons: reasons.take(3).toList(),
        ));
      }

      swaps.sort((a, b) => b.score.compareTo(a.score));

      setState(() {
        _candidates = swaps.take(5).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: context.appBorderColor)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appBorderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.primary100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.auto_awesome,
                        size: 20, color: context.primary600),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Meal Swap',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Smarter alternatives to "${widget.current.name}"',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.gray500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Current recipe mini card
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _CurrentRecipeMini(recipe: widget.current),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('Better alternatives',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.gray400,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Error: $_error'))
                      : (_candidates?.isEmpty ?? true)
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No better alternatives found for this recipe.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppTheme.gray500),
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: ctrl,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _candidates!.length,
                              itemBuilder: (_, i) => _SwapCard(
                                candidate: _candidates![i],
                                current: widget.current,
                                onTap: () {
                                  Navigator.pop(context);
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailScreen(
                                          recipe: _candidates![i].recipe),
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapCandidate {
  final Recipe recipe;
  final double score;
  final int deltaCalories;
  final double deltaProtein;
  final double deltaCarbs;
  final double deltaFat;
  final double deltaFiber;
  final List<String> reasons;

  const _SwapCandidate({
    required this.recipe,
    required this.score,
    required this.deltaCalories,
    required this.deltaProtein,
    required this.deltaCarbs,
    required this.deltaFat,
    required this.deltaFiber,
    required this.reasons,
  });
}

class _CurrentRecipeMini extends StatelessWidget {
  const _CurrentRecipeMini({required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSubtleFillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorderColor),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: recipe.image != null
                ? CachedNetworkImage(
                    imageUrl: recipe.image!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: context.appSubtleFillColor,
                        child: Center(
                            child: Text(recipe.mealType.emoji,
                                style: const TextStyle(fontSize: 20)))),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: context.appSubtleFillColor,
                    child: Center(
                        child: Text(recipe.mealType.emoji,
                            style: const TextStyle(fontSize: 20))),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current',
                    style: TextStyle(
                        fontSize: 10,
                        color: context.appMutedTextColor,
                        fontWeight: FontWeight.w600)),
                Text(recipe.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  '${recipe.calories} kcal · P${recipe.proteinG.round()}g · C${recipe.carbsG.round()}g · F${recipe.fatG.round()}g',
                  style:
                      TextStyle(fontSize: 10, color: context.appMutedTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapCard extends StatelessWidget {
  const _SwapCard({
    required this.candidate,
    required this.current,
    required this.onTap,
  });

  final _SwapCandidate candidate;
  final Recipe current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = candidate.recipe;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: r.image != null
                    ? CachedNetworkImage(
                        imageUrl: r.image!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: context.appSubtleFillColor,
                            child: Center(
                                child: Text(r.mealType.emoji,
                                    style: const TextStyle(fontSize: 24)))),
                      )
                    : Container(
                        width: 72,
                        height: 72,
                        color: context.appSubtleFillColor,
                        child: Center(
                            child: Text(r.mealType.emoji,
                                style: const TextStyle(fontSize: 24))),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    // Macro diff row
                    _MacroDiffRow(candidate: candidate, current: current),
                    const SizedBox(height: 6),
                    // Benefit chips
                    if (candidate.reasons.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: candidate.reasons
                            .map((r) => _BenefitChip(label: r))
                            .toList(),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: context.appMutedTextColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroDiffRow extends StatelessWidget {
  const _MacroDiffRow({required this.candidate, required this.current});
  final _SwapCandidate candidate;
  final Recipe current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DiffBadge(
          label: 'kcal',
          current: current.calories.toDouble(),
          next: candidate.recipe.calories.toDouble(),
          isInteger: true,
          lowerIsBetter: true,
        ),
        const SizedBox(width: 4),
        _DiffBadge(
          label: 'P',
          current: current.proteinG,
          next: candidate.recipe.proteinG,
          lowerIsBetter: false,
        ),
        const SizedBox(width: 4),
        _DiffBadge(
          label: 'C',
          current: current.carbsG,
          next: candidate.recipe.carbsG,
          lowerIsBetter: true,
        ),
        const SizedBox(width: 4),
        _DiffBadge(
          label: 'F',
          current: current.fatG,
          next: candidate.recipe.fatG,
          lowerIsBetter: true,
        ),
      ],
    );
  }
}

class _DiffBadge extends StatelessWidget {
  const _DiffBadge({
    required this.label,
    required this.current,
    required this.next,
    this.lowerIsBetter = true,
    this.isInteger = false,
  });

  final String label;
  final double current;
  final double next;
  final bool lowerIsBetter;
  final bool isInteger;

  @override
  Widget build(BuildContext context) {
    final delta = next - current;
    final improved = lowerIsBetter ? delta < -1 : delta > 1;
    final worsened = lowerIsBetter ? delta > 1 : delta < -1;

    Color bg;
    Color fg;
    if (improved) {
      bg = AppTheme.green100;
      fg = AppTheme.green700;
    } else if (worsened) {
      bg = AppTheme.red100;
      fg = AppTheme.red700;
    } else {
      bg = context.appSubtleFillColor;
      fg = context.appMutedTextColor;
    }

    final sign = delta > 0 ? '+' : '';
    final deltaStr = isInteger
        ? '$sign${delta.round()}'
        : '$sign${delta.toStringAsFixed(1)}g';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$label $deltaStr',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _BenefitChip extends StatelessWidget {
  const _BenefitChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.primary100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: context.primary700,
        ),
      ),
    );
  }
}
