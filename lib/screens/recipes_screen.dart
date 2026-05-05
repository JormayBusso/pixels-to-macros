import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/food_data.dart';
import '../models/nutrition_goal.dart';
import '../models/recipe.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/database_service.dart';
import '../services/recipe_repository.dart';
import '../theme/app_theme.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(recipeQueryProvider);
    final resultsAsync = ref.watch(recipeResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (s) =>
                  ref.read(recipeQueryProvider.notifier).setSearch(s),
              decoration: InputDecoration(
                hintText: 'Search recipes or ingredients…',
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
                fillColor: AppTheme.gray100,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Goal chips ──
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(
                  label: 'All goals',
                  selected: query.goal == null,
                  onTap: () =>
                      ref.read(recipeQueryProvider.notifier).setGoal(null),
                ),
                for (final g in NutritionGoalType.values)
                  _FilterChip(
                    label: g.label,
                    emoji: g.emoji,
                    selected: query.goal == g,
                    onTap: () =>
                        ref.read(recipeQueryProvider.notifier).setGoal(g),
                  ),
              ],
            ),
          ),
          // ── Meal type chips ──
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _FilterChip(
                  label: 'All meals',
                  selected: query.mealType == null,
                  onTap: () =>
                      ref.read(recipeQueryProvider.notifier).setMealType(null),
                ),
                for (final m in RecipeMealType.values.where((t) => t != RecipeMealType.snack))
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
            child: resultsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (recipes) {
                if (recipes.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No recipes match your filters.\nTry widening your search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.gray400),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount: recipes.length,
                  itemBuilder: (_, i) =>
                      _RecipeCard(recipe: recipes[i]),
                );
              },
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? context.primary500 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? context.primary500 : AppTheme.gray200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppTheme.gray700,
                ),
              ),
            ],
          ),
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
                child: CachedNetworkImage(
                  imageUrl: recipe.image!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppTheme.gray100),
                  errorWidget: (_, __, ___) =>
                      Container(color: AppTheme.gray100),
                ),
              )
            else
              Container(
                width: 90,
                height: 90,
                color: AppTheme.gray100,
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
                    Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 13, color: AppTheme.gray400),
                        const SizedBox(width: 3),
                        Text('${recipe.minutes} min',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.gray500)),
                        const SizedBox(width: 10),
                        if (recipe.hasMacros) ...[
                          Icon(Icons.local_fire_department_outlined,
                              size: 13, color: AppTheme.gray400),
                          const SizedBox(width: 3),
                          Text('${recipe.calories} kcal',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.gray500)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: recipe.goals
                          .take(3)
                          .map((g) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: g.color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  g.label,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: g.color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
      MaterialPageRoute(builder: (_) => _RecipeDetailScreen(recipe: recipe)),
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
        color: AppTheme.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.gray500),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.gray700)),
        ],
      ),
    );
  }
}

class _RecipeDetailScreen extends ConsumerStatefulWidget {
  const _RecipeDetailScreen({required this.recipe});
  final Recipe recipe;

  @override
  ConsumerState<_RecipeDetailScreen> createState() =>
      _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<_RecipeDetailScreen> {
  int _selectedServings = 1;
  bool _isDiabetic = false;
  double _icr = 10.0; // insulin-to-carb ratio

  /// Scale an ingredient amount string by the ratio of selected/recipe servings.
  String _scaleAmount(String amount, int selected, int original) {
    if (selected == original) return amount;
    final ratio = selected / original;
    // Try to find a leading number (int or decimal, possibly fractional like "1/2")
    final fractionRegex = RegExp(r'^(\d+)/(\d+)(.*)$');
    final numberRegex = RegExp(r'^(\d+\.?\d*)(.*)$');
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
    return amount; // non-numeric like "to taste", "pinch"
  }

  @override
  void initState() {
    super.initState();
    _selectedServings = widget.recipe.servings;
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDiabetic = prefs.getBool('is_diabetic') ?? false;
      _icr = prefs.getDouble('insulin_carb_ratio') ?? 10.0;
    });
  }

  // Nutrition always shows 1 person's portion (recipe base serving)
  double get _carbsForServing =>
      widget.recipe.carbsPerServing(widget.recipe.servings);
  double get _bolusUnits => _carbsForServing / _icr;

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: r.image != null ? 240 : 0,
            pinned: true,
            flexibleSpace: r.image != null
                ? FlexibleSpaceBar(
                    background: CachedNetworkImage(
                      imageUrl: r.image!,
                      fit: BoxFit.cover,
                      color: Colors.black26,
                      colorBlendMode: BlendMode.darken,
                    ),
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
                Row(
                  children: [
                    _MetaChip(Icons.timer_outlined, '${r.minutes} min'),
                    const SizedBox(width: 8),
                    _MetaChip(Icons.restaurant, '${r.servings} servings'),
                    if (r.hasMacros) ...[
                      const SizedBox(width: 8),
                      _MetaChip(Icons.local_fire_department_outlined,
                          '${r.caloriesPerServing(r.servings)} kcal per person'),
                    ],
                  ],
                ),
                if (r.hasMacros) ...[
                  const SizedBox(height: 16),
                  // ── Macro bar (per person, does not change with serving selector) ──
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('Per person',
                        style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                  ),
                  _NutritionTable(
                    recipe: r,
                    servings: r.servings,
                  ),
                ],
                // ── Bolus display for diabetics ──
                if (_isDiabetic && r.hasMacros) ...[
                  const SizedBox(height: 12),
                  _BolusCard(
                    carbsG: _carbsForServing,
                    bolusUnits: _bolusUnits,
                    icr: _icr,
                  ),
                  if (_selectedServings > 1) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Multiple servings: verify portion accuracy before bolusing.',
                              style: TextStyle(fontSize: 11, color: Colors.brown),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                // ── Ingredients ──
                const Text('Ingredients',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
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
                              color: AppTheme.gray400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: i.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (i.amount.isNotEmpty)
                                  TextSpan(
                                    text: '  ${_scaleAmount(i.amount, _selectedServings, r.servings)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.gray500,
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
                const Text('Preparation',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
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
                                color: AppTheme.gray100,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${e.key + 1}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.gray700,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.55,
                                  color: Color(0xFF333333),
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
      // ── Log button ──
      bottomNavigationBar: r.hasMacros
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: FilledButton.icon(
                  onPressed: () => _logRecipe(context),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: Text(
                    _isDiabetic
                        ? 'Log Meal · ${r.caloriesPerServing(r.servings)} kcal · ${_bolusUnits.toStringAsFixed(1)}U'
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
            )
          : null,
    );
  }

  void _logRecipe(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LogRecipeSheet(
        recipe: widget.recipe,
        servings: _selectedServings,
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
    required this.onLogged,
  });

  final Recipe recipe;
  final int servings;
  final VoidCallback onLogged;

  @override
  ConsumerState<_LogRecipeSheet> createState() => _LogRecipeSheetState();
}

class _LogRecipeSheetState extends ConsumerState<_LogRecipeSheet> {
  final List<TextEditingController> _controllers = [];
  List<FoodData> _allFoods = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final _ in widget.recipe.ingredients) {
      _controllers.add(TextEditingController());
    }
    _initDefaults();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  Future<void> _initDefaults() async {
    _allFoods = await DatabaseService.instance.getAllFoods();

    for (var i = 0; i < widget.recipe.ingredients.length; i++) {
      final ing = widget.recipe.ingredients[i];
      final grams = _estimateGrams(ing.amount, widget.servings, widget.recipe.servings, ing.name);
      _controllers[i].text = grams.round().toString();
    }
    setState(() {});
  }

  double _estimateGrams(String amount, int selected, int original, String name) {
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
        scaled = (val == val.roundToDouble() ? val.round().toString() : val.toStringAsFixed(1)) + suffix;
      } else {
        final fracMatch2 = simpleFraction.firstMatch(scaled);
        if (fracMatch2 != null) {
          final num = int.parse(fracMatch2.group(1)!);
          final den = int.parse(fracMatch2.group(2)!);
          final suffix = fracMatch2.group(3) ?? '';
          final val = (num / den) * ratio;
          scaled = (val == val.roundToDouble() ? val.round().toString() : val.toStringAsFixed(1)) + suffix;
        } else {
          final match = numberRegex.firstMatch(scaled);
          if (match != null) {
            final v = double.tryParse(match.group(1)!) ?? 0.0;
            final suffix = match.group(2) ?? '';
            final val = v * ratio;
            scaled = (val == val.roundToDouble() ? val.round().toString() : val.toStringAsFixed(1)) + suffix;
          }
        }
      }
    }

    // Extract numeric value and unit
    final numMatch = RegExp(r'(\d+\.?\d*|\d+\/\d+|\d+\s+\d+\/\d+)').firstMatch(scaled);
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
    if (unit.contains('kg')) grams = value * 1000.0;
    else if (unit.contains('g')) grams = value;
    else if (unit.contains('ml')) grams = value; // assume 1 ml ≈ 1 g
    else if (unit.contains('tbsp') || unit.contains('tablespoon')) grams = value * 15.0;
    else if (unit.contains('tsp') || unit.contains('teaspoon')) grams = value * 5.0;
    else if (unit.contains('cup')) grams = value * 240.0;
    else if (unit.contains('oz')) grams = value * 28.35;
    else if (unit.contains('lb')) grams = value * 453.592;
    else if (value > 0) {
      final lname = name.toLowerCase();
      if (lname.contains('egg')) grams = value * 50.0;
      else if (lname.contains('slice')) grams = value * 30.0;
      else grams = value * 100.0; // fallback guess
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

  double get _totalKcal {
    if (_allFoods.isEmpty) return 0.0;
    double sum = 0.0;
    for (var i = 0; i < widget.recipe.ingredients.length; i++) {
      final g = _parseControllerValue(i);
      if (g <= 0) continue;
      final ingName = widget.recipe.ingredients[i].name.toLowerCase();
      FoodData? fd;
      try {
        fd = _allFoods.firstWhere((f) => f.label.toLowerCase() == ingName);
      } catch (_) {}
      if (fd == null) {
        try {
          fd = _allFoods.firstWhere((f) => ingName.contains(f.label.toLowerCase()) || f.label.toLowerCase().contains(ingName));
        } catch (_) {}
      }
      fd ??= _allFoods.firstWhere((f) => f.label.toLowerCase() == 'others', orElse: () => _allFoods.first);
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

    for (var i = 0; i < widget.recipe.ingredients.length; i++) {
      final grams = _parseControllerValue(i);
      if (grams <= 0) continue;
      final ing = widget.recipe.ingredients[i];
      final ingName = ing.name.toLowerCase();

      FoodData? fd;
      try {
        fd = _allFoods.firstWhere((f) => f.label.toLowerCase() == ingName);
      } catch (_) {}
      if (fd == null) {
        try {
          fd = _allFoods.firstWhere((f) => ingName.contains(f.label.toLowerCase()) || f.label.toLowerCase().contains(ingName));
        } catch (_) {}
      }
      fd ??= _allFoods.firstWhere((f) => f.label.toLowerCase() == 'others', orElse: () => _allFoods.first);

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No ingredient amounts provided.')));
      return;
    }

    final scan = ScanResult(timestamp: DateTime.now(), depthMode: 'recipe', foods: foods);
    try {
      await DatabaseService.instance.insertScanResult(scan);
      widget.onLogged();
      if (mounted) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged recipe.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to log recipe: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.85;
    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
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
                      child: Text('Log: ${widget.recipe.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Text('Adjust grams per ingredient (cooking for ${widget.servings})', style: const TextStyle(color: Color(0xFF666666))),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.recipe.ingredients.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final ing = widget.recipe.ingredients[i];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ing.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (ing.amount.isNotEmpty)
                                Text(_scaleAmountLocal(ing.amount, widget.servings, widget.recipe.servings), style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _controllers[i],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('g', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  Expanded(child: Text('Total: ${_totalKcal.round()} kcal', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Log Meal'),
                  ),
                ],
              ),
            ],
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
    return Row(
      children: [
        Text('Cooking for',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.gray700)),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.gray100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
                      color: selected ? Colors.white : AppTheme.gray600,
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

class _NutritionTable extends StatelessWidget {
  const _NutritionTable({required this.recipe, required this.servings});
  final Recipe recipe;
  final int servings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _NutrientRow('Protein', recipe.proteinPerServing(servings), 'g'),
          _NutrientRow('Carbs', recipe.carbsPerServing(servings), 'g'),
          _NutrientRow('Fat', recipe.fatPerServing(servings), 'g'),
          if (recipe.fiberG > 0)
            _NutrientRow('Fiber', recipe.fiberPerServing(servings), 'g'),
          if (recipe.sugarG > 0)
            _NutrientRow('Sugar', recipe.sugarPerServing(servings), 'g'),
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
                  color: AppTheme.gray600,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text('${value.round()}$unit',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
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
  });
  final double carbsG;
  final double bolusUnits;
  final double icr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop, size: 18, color: Color(0xFF1976D2)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested bolus: ${bolusUnits.toStringAsFixed(1)} U',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1565C0),
                  ),
                ),
                Text(
                  '${carbsG.round()}g carbs ÷ ICR ${icr.round()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF42A5F5),
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
