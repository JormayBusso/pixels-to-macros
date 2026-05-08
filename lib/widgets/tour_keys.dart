import 'package:flutter/material.dart';

/// Central registry of [GlobalKey]s used by [AppTutorialOverlay] to measure
/// target widgets with pixel-perfect accuracy via [RenderBox.localToGlobal].
///
/// Each key is attached (via `key:`) to a specific widget in the tree.
/// The overlay calls [BuildContext.findRenderObject] on the key's context to
/// obtain the exact bounding box in global screen coordinates — no hard-coded
/// offsets or normalized guesses.
abstract final class TourKeys {
  // ── Main Shell ─────────────────────────────────────────────────────────────

  /// The [NavigationBar] widget — used to derive per-item spotlight rects.
  static final navBar = GlobalKey(debugLabel: 'tour_nav_bar');

  /// AI Scan extended FAB.
  static final scanFab = GlobalKey(debugLabel: 'tour_scan_fab');

  /// AI Speech extended FAB.
  static final speechFab = GlobalKey(debugLabel: 'tour_speech_fab');

  /// Manual Log extended FAB.
  static final manualFab = GlobalKey(debugLabel: 'tour_manual_fab');

  // ── Home Screen ────────────────────────────────────────────────────────────

  /// Daily streak badge (only in tree when streak > 0).
  static final streakBadge = GlobalKey(debugLabel: 'tour_streak_badge');

  /// Body-map icon button in the AppBar.
  static final bodyMapIcon = GlobalKey(debugLabel: 'tour_body_map_icon');

  /// Nutrition (eco) icon button in the AppBar.
  static final nutritionIcon = GlobalKey(debugLabel: 'tour_nutrition_icon');

  /// Hydration card container (scroll-to + spotlight target).
  static final hydrationCard = GlobalKey(debugLabel: 'tour_hydration_card');

  /// "Add drink" icon button inside the hydration card.
  static final hydrationAddDrink =
      GlobalKey(debugLabel: 'tour_hydration_add_drink');

  /// "+200 ml" quick-add water button inside the hydration card.
  static final hydrationQuickAdd200 =
      GlobalKey(debugLabel: 'tour_hydration_quick_200');

  /// Smart recommendations card container.
  static final recommendationsCard =
      GlobalKey(debugLabel: 'tour_recommendations_card');

  // ── Recipes Screen ─────────────────────────────────────────────────────────

  /// Recipe search bar TextField.
  static final recipeSearch = GlobalKey(debugLabel: 'tour_recipe_search');

  // ── Settings Screen ────────────────────────────────────────────────────────

  /// Weekly badge recap card container.
  static final weeklyReviewCard =
      GlobalKey(debugLabel: 'tour_weekly_review_card');

  /// Vacation-mode card container.
  static final vacationModeCard =
      GlobalKey(debugLabel: 'tour_vacation_mode_card');
}
