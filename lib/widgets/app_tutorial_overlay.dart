import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scroll_trigger_provider.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Step-by-step guided tour overlay for the main shell.
///
/// Each step:
///  1. Navigates to the relevant tab automatically.
///  2. Shows a pointer marker over the target button.
///  3. Shows a tooltip bubble above or below that marker.
///
/// Positions are expressed as fractions of screen width/height so they
/// adapt to any device size.
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

/// Highlight rect in normalised 0–1 coords.
/// [cx], [cy] = centre; [w], [h] = size; [r] = corner radius fraction.
class _SpotRect {
  final double cx, cy, w, h, r;
  // ignore: unused_element_parameter
  const _SpotRect(this.cx, this.cy, this.w, this.h, {this.r = 0.06});
}

enum _ScrollTarget { none, hydration, recommendations, weeklyReview, vacation }

class _Step {
  final String title;
  final String body;
  final int tab;
  final _SpotRect? spot;
  final bool tipBelow;
  final _ScrollTarget scroll;

  const _Step({
    required this.title,
    required this.body,
    this.tab = 0,
    this.spot,
    this.tipBelow = false,
    this.scroll = _ScrollTarget.none,
  });
}

const _kSteps = [
  // 0 – Welcome (no spotlight)
  _Step(
    title: 'Welcome to Pixels to Macros! 👋',
    body: "Let's take a quick tour so you know where everything is.",
    tab: 0,
  ),
  // 1 – AI Scan button (extended FAB, bottom-right)
  _Step(
    title: 'AI Scan 📷',
    body:
        'Tap AI Scan to open the camera.\nPoint at your plate and get instant calories & macros!\nIncludes flashlight toggle and low-light warnings.',
    tab: 0,
    spot: _SpotRect(0.835, 0.895, 0.33, 0.056, r: 0.035),
  ),
  // 2 – AI Speech (extended FAB, above scan)
  _Step(
    title: 'AI Speech 🎤',
    body:
        'Tap AI Speech to log food by voice in English.\nSay "200 grams of chicken and a banana" — it matches your food database automatically.',
    tab: 0,
    spot: _SpotRect(0.835, 0.735, 0.33, 0.056, r: 0.035),
  ),
  // 3 – Manual Log (extended FAB, between speech and scan)
  _Step(
    title: 'Log Food Manually ✏️',
    body:
        'Search foods, pick from My Meals, or scan a barcode.\nBarcode scanning shows a health score (0-100) before logging.',
    tab: 0,
    spot: _SpotRect(0.835, 0.815, 0.33, 0.056, r: 0.035),
  ),
  // 4 – Streak badge (top-right in greeting row)
  _Step(
    title: 'Daily Streak 🔥',
    body:
        'Your streak badge is now bigger and easier to spot. Keep logging daily to build momentum.',
    tab: 0,
    spot: _SpotRect(0.78, 0.182, 0.34, 0.07, r: 0.035),
    tipBelow: true,
  ),
  // 5 – Body map icon (AppBar action)
  _Step(
    title: 'Body Map 🫀',
    body:
        'Tap the body icon to open the anatomy map.\nBrain, eyes, heart, lungs, gut, bones, muscles, skin, blood, and immune regions are tappable and color-coded from your nutrient intake.',
    tab: 0,
    spot: _SpotRect(0.84, 0.066, 0.11, 0.045, r: 0.025),
    tipBelow: true,
  ),
  // 6 – Nutrition button (leaf icon, rightmost AppBar action)
  _Step(
    title: "Today's Nutrition 🌿",
    body:
        'The leaf icon opens your full nutrition dashboard with macros, vitamins, minerals, and the upgraded micronutrient wheel.',
    tab: 0,
    spot: _SpotRect(0.955, 0.066, 0.09, 0.045, r: 0.025),
    tipBelow: true,
  ),
  // 7 – Hydration card add-drink button (scrolls home screen first)
  _Step(
    title: 'Hydration Tracking 💧',
    body:
        'The hydration card tracks your daily water intake.\nUse the + drink button to log water, coffee, tea, and more.',
    tab: 0,
    spot: _SpotRect(0.84, 0.305, 0.12, 0.055, r: 0.025),
    scroll: _ScrollTarget.hydration,
  ),
  // 8 – Hydration quick +200 button
  _Step(
    title: 'Quick Add +200 ml',
    body:
        'Need a fast water log? Tap +200 ml for one-tap hydration updates.',
    tab: 0,
    spot: _SpotRect(0.37, 0.548, 0.23, 0.052, r: 0.02),
    scroll: _ScrollTarget.hydration,
  ),
  // 9 – Smart recommendations card
  _Step(
    title: 'Smart Nutrition Coach 🧠',
    body:
        'Recommendations now adapt to your goal and nutrient gaps (like low iron, vitamin D, B12, calcium, and more).',
    tab: 0,
    spot: _SpotRect(0.50, 0.575, 0.88, 0.12, r: 0.03),
    scroll: _ScrollTarget.recommendations,
  ),
  // 10 – Analytics tab
  _Step(
    title: 'Analytics 📊',
    body: 'Track weekly & monthly calorie and macro trends here.',
    tab: 1,
    spot: _SpotRect(0.25, 0.965, 0.155, 0.055, r: 0.02),
  ),
  // 11 – Recipes tab button
  _Step(
    title: 'Recipes 🍽️',
    body:
        'Browse recipes tailored to your nutrition goal and log meals quickly.',
    tab: 2,
    spot: _SpotRect(0.417, 0.965, 0.155, 0.055, r: 0.02),
  ),
  // 12 – Recipes search bar
  _Step(
    title: 'Recipe Search',
    body:
        'Use search + goal filters to find recipes that match your needs faster.',
    tab: 2,
    spot: _SpotRect(0.50, 0.162, 0.90, 0.07, r: 0.03),
    tipBelow: true,
  ),
  // 13 – Recipes with photos
  _Step(
    title: 'Recipe Photos 📸',
    body:
        'Recipes now show matching food photos to make selection easier and more intuitive.',
    tab: 2,
    spot: _SpotRect(0.50, 0.40, 0.90, 0.18, r: 0.03),
    tipBelow: true,
  ),
  // 14 – Groceries tab (tab index 3, center = 0.583)
  _Step(
    title: 'Grocery List 🛒',
    body:
        'Add items manually or get smart suggestions based on your scan history.',
    tab: 3,
    spot: _SpotRect(0.583, 0.965, 0.155, 0.055, r: 0.02),
  ),
  // 15 – Settings tab (tab index 5, center = 0.917)
  _Step(
    title: 'Settings ⚙️',
    body:
        'Change your nutrition goal, color theme, mascot, text size, weekly badge recap, and more.\nDiabetes users can set ICR for bolus calculations.',
    tab: 5,
    spot: _SpotRect(0.917, 0.965, 0.155, 0.055, r: 0.02),
  ),
  // 16 – Weekly badge recap setting
  _Step(
    title: 'Weekly Badges 🏅',
    body:
        'At the start of each week, the app can show the badges you earned last week.\nUse this setting to turn that recap on or off.',
    tab: 5,
    spot: _SpotRect(0.87, 0.45, 0.18, 0.07, r: 0.035),
    scroll: _ScrollTarget.weeklyReview,
  ),
  // 17 – Vacation mode (scrolls to it in Settings)
  _Step(
    title: 'Vacation Mode 🏖️',
    body:
        'Protect your streak while you\'re away.\nTap the toggle to activate Vacation Mode.\nYou can also adjust your daily water goal and Glycemic Load settings here.',
    tab: 5,
    spot: _SpotRect(0.87, 0.46, 0.18, 0.07, r: 0.035),
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
      unawaited(_ctrl.forward());
    } else {
      await _ctrl.reverse();
      widget.onDismiss();
    }
  }

  void _skip() {
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final step = _kSteps[_step];
    final isLast = _step == _kSteps.length - 1;

    return FadeTransition(
      opacity: _fade,
      child: Stack(
        children: [
          // ── Dark overlay (no spotlight cutout) ──────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // absorb all taps
              child: Container(color: Colors.black.withValues(alpha: 0.80)),
            ),
          ),

          if (step.spot != null)
            _PointerMarker(
              spot: step.spot!,
              screenSize: size,
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
            isLast: isLast,
            onNext: _next,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pointer marker: highlights target location without a spotlight cutout.
// ─────────────────────────────────────────────────────────────────────────────

class _PointerMarker extends StatelessWidget {
  final _SpotRect spot;
  final Size screenSize;

  const _PointerMarker({required this.spot, required this.screenSize});

  @override
  Widget build(BuildContext context) {
    final cx = spot.cx * screenSize.width;
    final cy = spot.cy * screenSize.height;
    return Positioned(
      left: cx - 18,
      top: cy - 42,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.9, end: 1.1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFA000),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFA000).withValues(alpha: 0.5),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.touch_app, color: Colors.white, size: 20),
              ),
            ),
            Container(
              width: 3,
              height: 8,
              color: const Color(0xFFFFA000),
            ),
          ],
        ),
      ),
    );
  }
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
    required this.isLast,
    required this.onNext,
  });

  final _Step step;
  final int stepIndex;
  final int totalSteps;
  final Size screenSize;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Position: if there's a spotlight, place card on opposite side.
    // Otherwise centre vertically.
    double? top, bottom;
    if (step.spot == null) {
      // Centred — use absolute positioning
      top = screenSize.height * 0.25;
    } else {
      final cy = step.spot!.cy * screenSize.height;
      final halfH = step.spot!.h * screenSize.height / 2 + 24;
      if (step.tipBelow) {
        top = cy + halfH + 12;
      } else {
        bottom = screenSize.height - (cy - halfH) + 12;
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
