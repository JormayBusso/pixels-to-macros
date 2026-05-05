import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nutrition_goal.dart';
import '../models/recipe.dart';

/// Loads the bundled `assets/recipes.json` lazily and caches it for the app
/// lifetime. The whole list (~1.5 MB) is parsed once on first access.
class RecipeRepository {
  RecipeRepository._();
  static final RecipeRepository instance = RecipeRepository._();

  List<Recipe>? _cache;
  Future<List<Recipe>>? _inFlight;

  Future<List<Recipe>> all() {
    if (_cache != null) return Future.value(_cache);
    return _inFlight ??= _load();
  }

  Future<List<Recipe>> _load() async {
    final raw = await rootBundle.loadString('assets/recipes.json');
    final list = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(Recipe.fromJson)
        .toList(growable: false);
    _cache = list;
    _inFlight = null;
    return list;
  }

  /// Filter + score for ranking. Recipes matching all selected facets win.
  Future<List<Recipe>> query({
    NutritionGoalType? goal,
    RecipeMealType? mealType,
    String? search,
    int maxMinutes = 0,
    int limit = 100,
  }) async {
    final list = await all();
    final q = (search ?? '').trim().toLowerCase();
    final filtered = <Recipe>[];
    for (final r in list) {
      if (goal != null && !r.goals.contains(goal)) continue;
      if (mealType != null && r.mealType != mealType) continue;
      if (maxMinutes > 0 && r.minutes > maxMinutes) continue;
      if (q.isNotEmpty) {
        final hay = '${r.name.toLowerCase()} '
            '${r.tags.join(' ').toLowerCase()} '
            '${r.ingredients.map((i) => i.name).join(' ').toLowerCase()}';
        if (!hay.contains(q)) continue;
      }
      filtered.add(r);
    }
    // Stable, deterministic ordering: recipes with image first, then with
    // macros, then by shortest prep time.
    filtered.sort((a, b) {
      final imgCmp = (b.image != null ? 1 : 0) - (a.image != null ? 1 : 0);
      if (imgCmp != 0) return imgCmp;
      final macroCmp = (b.hasMacros ? 1 : 0) - (a.hasMacros ? 1 : 0);
      if (macroCmp != 0) return macroCmp;
      return a.minutes.compareTo(b.minutes);
    });
    if (filtered.length > limit) return filtered.sublist(0, limit);
    return filtered;
  }
}

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepository.instance,
);

class RecipeQueryState {
  const RecipeQueryState({
    this.goal,
    this.mealType,
    this.search = '',
    this.maxMinutes = 0,
  });
  final NutritionGoalType? goal;
  final RecipeMealType? mealType;
  final String search;
  final int maxMinutes;

  RecipeQueryState copyWith({
    NutritionGoalType? goal,
    RecipeMealType? mealType,
    String? search,
    int? maxMinutes,
    bool clearGoal = false,
    bool clearMealType = false,
  }) =>
      RecipeQueryState(
        goal: clearGoal ? null : (goal ?? this.goal),
        mealType: clearMealType ? null : (mealType ?? this.mealType),
        search: search ?? this.search,
        maxMinutes: maxMinutes ?? this.maxMinutes,
      );
}

class RecipeQueryNotifier extends StateNotifier<RecipeQueryState> {
  RecipeQueryNotifier() : super(const RecipeQueryState());

  void setGoal(NutritionGoalType? g) =>
      state = state.copyWith(goal: g, clearGoal: g == null);
  void setMealType(RecipeMealType? m) =>
      state = state.copyWith(mealType: m, clearMealType: m == null);
  void setSearch(String s) => state = state.copyWith(search: s);
  void setMaxMinutes(int m) => state = state.copyWith(maxMinutes: m);
  void clear() => state = const RecipeQueryState();
}

final recipeQueryProvider =
    StateNotifierProvider<RecipeQueryNotifier, RecipeQueryState>(
  (_) => RecipeQueryNotifier(),
);

final recipeResultsProvider = FutureProvider<List<Recipe>>((ref) async {
  final q = ref.watch(recipeQueryProvider);
  return RecipeRepository.instance.query(
    goal: q.goal,
    mealType: q.mealType,
    search: q.search,
    maxMinutes: q.maxMinutes,
  );
});
