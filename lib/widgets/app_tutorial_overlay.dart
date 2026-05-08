import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scroll_trigger_provider.dart';
import '../theme/app_theme.dart';
import 'tour_keys.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Step-by-step guided tour overlay for the main shell.
///
/// Spotlight positions are measured at runtime via [RenderBox.localToGlobal]
/// on [GlobalKey]s attached to the actual target widgets — no hard-coded
/// offsets or normalized coordinate guesses.
class AppTutorialOverlay extends ConsumerStatefulWidget {
  const AppTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.onNavigateToTab,
  });

  final VoidCallback onDismiss;
  final ValueChanged<int> onNavigateToTab;

  @override
  ConsumerState<AppTutorialOverlay> createState() => _AppTutorialOverlayState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Step definitions
// ─────────────────────────────────────────────────────────────────────────────

enum _ScrollTarget { none, hydration, recommendations, weeklyReview, vacation }

/// A single tour step.
///
/// Spotlight is determined at runtime by one of:
/// * [targetKey] — measure the widget's exact [RenderBox] in global coords.
/// * [navItemIndex] — derive from the [TourKeys.navBar] render box, divided
///   equally among [_kNumNavItems] items (Material 3 NavigationBar layout).
/// If both are null, no spotlight is shown (centred tooltip only).
class _Step {
  final String title;
  final String body;
  final int tab;

  /// [GlobalKey] of the widget to spotlight. Measured via [RenderBox].
  final GlobalKey? targetKey;

  /// Index (0-based) of a NavigationBar destination to spotlight.
  final int? navItemIndex;

  /// Place the tooltip card *below* the spotlight instead of above it.
  final bool tipBelow;

  final _ScrollTarget scroll;

  const _Step({
    required this.title,
    required this.body,
    this.tab = 0,
    this.targetKey,
    this.navItemIndex,
    this.tipBelow = false,
    this.scroll = _ScrollTarget.none,
  });
}

const _kNumNavItems = 6;

const _kSteps = [
  // 0 – Welcome (no spotlight)
  _Step(
    title: 'Welcome to Pixels to Macros! 👋',
    body: "Let's take a quick tour so you know where everything is.",
    tab: 0,
  ),
  // 1 – AI Scan button
  _Step(
    title: 'AI Scan 📷',
    body:
        'Tap AI Scan to open the camera.\nPoint at your plate and get instant calories & macros!\nIncludes flashlight toggle and low-light warnings.',
    tab: 0,
    targetKey: TourKeys.scanFab,
  ),
  // 2 – AI Speech button
  _Step(
    title: 'AI Speech 🎤',
    body:
        'Tap AI Speech to log food by voice in English.\nSay "200 grams of chicken and a banana" — it matches your food database automatically.',
    tab: 0,
    targetKey: TourKeys.speechFab,
  ),
  // 3 – Manual Log button
  _Step(
    title: 'Log Food Manually ✏️',
    body:
        'Search foods, pick from My Meals, or scan a barcode.\nBarcode scanning shows a health score (0-100) before logging.',
    tab: 0,
    targetKey: TourKeys.manualFab,
  ),
  // 4 – Streak badge (top-right in greeting row)
  _Step(
    title: 'Daily Streak 🔥',
    body:
        'Your streak badge is now bigger and easier to spot. Keep logging daily to build momentum.',
    tab: 0,
    targetKey: TourKeys.streakBadge,
    tipBelow: true,
  ),
  // 5 – Body map icon (AppBar action)
  _Step(
    title: 'Body Map 🫀',
    body:
        'Tap the body icon to open the anatomy map.\nBrain, eyes, heart, lungs, gut, bones, muscles, skin, blood, and immune regions are tappable and color-coded from your nutrient intake.',
    tab: 0,
    targetKey: TourKeys.bodyMapIcon,
    tipBelow: true,
  ),
  // 6 – Nutrition button (leaf icon, rightmost AppBar action)
  _Step(
    title: "Today's Nutrition 🌿",
    body:
        'The leaf icon opens your full nutrition dashboard with macros, vitamins, minerals, and the upgraded micronutrient wheel.',
    tab: 0,
    targetKey: TourKeys.nutritionIcon,
    tipBelow: true,
  ),
  // 7 – Hydration card add-drink button
  _Step(
    title: 'Hydration Tracking 💧',
    body:
        'The hydration card tracks your daily water intake.\nUse the + drink button to log water, coffee, tea, and more.',
    tab: 0,
    targetKey: TourKeys.hydrationAddDrink,
    scroll: _ScrollTarget.hydration,
  ),
  // 8 – Hydration quick +200 button
  _Step(
    title: 'Quick Add +200 ml',
    body:
        'Need a fast water log? Tap +200 ml for one-tap hydration updates.',
    tab: 0,
    targetKey: TourKeys.hydrationQuickAdd200,
    scroll: _ScrollTarget.hydration,
  ),
  // 9 – Smart recommendations card
  _Step(
    title: 'Smart Nutrition Coach 🧠',
    body:
        'Recommendations now adapt to your goal and nutrient gaps (like low iron, vitamin D, B12, calcium, and more).',
    tab: 0,
    targetKey: TourKeys.recommendationsCard,
    scroll: _ScrollTarget.recommendations,
  ),
  // 10 – Analytics tab
  _Step(
    title: 'Analytics 📊',
    body: 'Track weekly & monthly calorie and macro trends here.',
    tab: 1,
    navItemIndex: 1,
  ),
  // 11 – Recipes tab button
  _Step(
    title: 'Recipes 🍽️',
    body:
        'Browse recipes tailored to your nutrition goal and log meals quickly.',
    tab: 2,
    navItemIndex: 2,
  ),
  // 12 – Recipes search bar
  _Step(
    title: 'Recipe Search',
    body:
        'Use search + goal filters to find recipes that match your needs faster.',
    tab: 2,
    targetKey: TourKeys.recipeSearch,
    tipBelow: true,
  ),
  // 13 – Recipes with photos (no precise target — content varies)
  _Step(
    title: 'Recipe Photos 📸',
    body:
        'Recipes now show matching food photos to make selection easier and more intuitive.',
    tab: 2,
  ),
  // 14 – Groceries tab
  _Step(
    title: 'Grocery List 🛒',
    body:
        'Add items manually or get smart suggestions based on your scan history.',
    tab: 3,
    navItemIndex: 3,
  ),
  // 15 – Settings tab
  _Step(
    title: 'Settings ⚙️',
    body:
        'Change your nutrition goal, color theme, mascot, text size, weekly badge recap, and more.\nDiabetes users can set ICR for bolus calculations.',
    tab: 5,
    navItemIndex: 5,
  ),
  // 16 – Weekly badge recap setting
  _Step(
    title: 'Weekly Badges 🏅',
    body:
        'At the start of each week, the app can show the badges you earned last week.\nUse this setting to turn that recap on or off.',
    tab: 5,
    targetKey: TourKeys.weeklyReviewCard,
    scroll: _ScrollTarget.weeklyReview,
  ),
  // 17 – Vacation mode
  _Step(
    title: 'Vacation Mode 🏖️',
    body:
        'Protect your streak while you\'re away.\nTap the toggle to activate Vacation Mode.\nYou can also adjust your daily water goal and Glycemic Load settings here.',
    tab: 5,
    targetKey: TourKeys.vacationModeCard,
    scroll: _ScrollTarget.vacation,
  ),
  // 18 – Outro
  _Step(
    title: 'You\'re All Set! 🚀',
    body:
        'Start scanning your first meal — or speak it!\n\nTip: you can replay this tour anytime from Settings → About.',
    tab: 0,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _AppTutorialOverlayState extends ConsumerState<AppTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.forward();
    // Navigate to first step's tab
    widget.onNavigateToTab(_kSteps[0].tab);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _next() async {
    if (_step < _kSteps.length - 1) {
      await _ctrl.reverse();
      setState(() => _step++);
      final step = _kSteps[_step];
      widget.onNavigateToTab(step.tab);
      if (step.scroll == _ScrollTarget.hydration) {
        ref.read(scrollToHydrationProvider.notifier).state++;
      } else if (step.scroll == _ScrollTarget.recommendations) {
        ref.read(scrollToRecommendationsProvider.notifier).state++;
      } else if (step.scroll == _ScrollTarget.weeklyReview) {
        ref.read(scrollToWeeklyReviewProvider.notifier).state++;
      } else if (step.scroll == _ScrollTarget.vacation) {
        ref.read(scrollToVacationProvider.notifier).state++;
      }
      if (step.scroll != _ScrollTarget.none) {
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
      // Re-measure after layout settles so the spotlight uses the final position.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      unawaited(_ctrl.forward());
    } else {
      await _ctrl.reverse();
      widget.onDismiss();
    }
  }

  void _skip() {
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  // ── Spotlight measurement ──────────────────────────────────────────────────

  /// Returns the exact bounding [Rect] of the step's target in global screen
  /// coordinates, measured via [RenderBox.localToGlobal]. No offsets added.
  ///
  /// Returns `null` when the target key has no context (widget not in tree).
  Rect? _measureStep(_Step step) {
    if (step.navItemIndex != null) return _navItemRect(step.navItemIndex!);
    if (step.targetKey != null) return _keyRect(step.targetKey!);
    return null;
  }

  /// Exact bounding box of [key]'s widget in global screen coordinates.
  Rect? _keyRect(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Computes the bounding rect for [NavigationBar] destination at [index].
  ///
  /// Material 3 [NavigationBar] lays out destinations as equal-width columns
  /// inside a bar of [_kNavBarVisualHeight] logical pixels.
  Rect? _navItemRect(int index) {
    final navBox =
        TourKeys.navBar.currentContext?.findRenderObject() as RenderBox?;
    if (navBox == null || !navBox.hasSize) return null;
    final navOffset = navBox.localToGlobal(Offset.zero);
    final itemWidth = navBox.size.width / _kNumNavItems;
    return Rect.fromLTWH(
      navOffset.dx + index * itemWidth,
      navOffset.dy,
      itemWidth,
      _kNavBarVisualHeight,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final step = _kSteps[_step];
    final isLast = _step == _kSteps.length - 1;
    final spotRect = _measureStep(step);

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // ── Dark overlay with measured spotlight cutout ───────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // absorb all taps
              child: CustomPaint(
                painter: _SpotlightPainter(spotRect: spotRect),
              ),
            ),
          ),

          // ── Skip button ───────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextButton(
                  onPressed: _skip,
                  child: const Text('Skip',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ),
              ),
            ),
          ),

          // ── Tooltip card ──────────────────────────────────────────────
          _TooltipCard(
            step: step,
            stepIndex: _step,
            totalSteps: _kSteps.length,
            screenSize: size,
            spotRect: spotRect,
            isLast: isLast,
            onNext: _next,
          ),
        ],
      ),
    );
  }
}

// Visual height of Material 3 NavigationBar (destinations live within this).
const double _kNavBarVisualHeight = 80.0;

// ─────────────────────────────────────────────────────────────────────────────
// Spotlight painter: dark overlay with a transparent rounded-rect cutout.
// The cutout rect is measured at runtime — no hard-coded offsets.
// ─────────────────────────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  /// Exact bounding box of the target widget in global screen coordinates.
  /// `null` → plain dark overlay (no cutout).
  final Rect? spotRect;

  const _SpotlightPainter({this.spotRect});

  @override
  void paint(Canvas canvas, Size size) {
    if (spotRect == null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.78),
      );
      return;
    }

    // Corner radius: proportional to the smaller dimension, clamped to [8, 20].
    final r = math.min(spotRect!.width, spotRect!.height) * 0.15;
    final cornerRadius = r.clamp(8.0, 20.0);

    final spotRRect = RRect.fromRectAndRadius(
      spotRect!,
      Radius.circular(cornerRadius),
    );

    // evenOdd fill: full-screen rect minus the cutout hole = dark area.
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(spotRRect);

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );

    // Bright border traces the exact widget edge.
    canvas.drawRRect(
      spotRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.spotRect != spotRect;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tooltip card
// ─────────────────────────────────────────────────────────────────────────────

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.screenSize,
    required this.spotRect,
    required this.isLast,
    required this.onNext,
  });

  final _Step step;
  final int stepIndex;
  final int totalSteps;
  final Size screenSize;
  final Rect? spotRect; // measured rect — null for steps without a target
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Vertical placement: opposite side of the spotlight.
    // No spotlight → centre vertically.
    double? top, bottom;
    if (spotRect == null) {
      top = screenSize.height * 0.25;
    } else if (step.tipBelow) {
      top = spotRect!.bottom + 12;
    } else {
      bottom = screenSize.height - spotRect!.top + 12;
      }
    }

    return Positioned(
      left: 20,
      right: 20,
      top: top,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                step.title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E)),
              ),
              const SizedBox(height: 8),
              // Body
              Text(
                step.body,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.gray600, height: 1.45),
              ),
              const SizedBox(height: 16),
              // Progress dots + button row
              Row(
                children: [
                  // Dots
                  Expanded(
                    child: Row(
                      children: List.generate(totalSteps, (i) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 4),
                          width: i == stepIndex ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == stepIndex
                                ? context.primary500
                                : AppTheme.gray200,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                  // Next / Done
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(84, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text(
                      isLast ? 'Done ✓' : 'Next →',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
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
