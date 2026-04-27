import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Step-by-step guided tour overlay for the main shell.
///
/// Each step:
///  1. Navigates to the relevant tab automatically.
///  2. Draws a spotlight cutout over the highlighted element.
///  3. Shows a tooltip bubble above or below the cutout.
///
/// Positions are expressed as fractions of screen width/height so they
/// adapt to any device size.
class AppTutorialOverlay extends StatefulWidget {
  const AppTutorialOverlay({
    super.key,
    required this.onDismiss,
    required this.onNavigateToTab,
  });

  final VoidCallback onDismiss;
  final ValueChanged<int> onNavigateToTab;

  @override
  State<AppTutorialOverlay> createState() => _AppTutorialOverlayState();
}

// ─────────────────────────────────────────────────────────────────────────────
// Step definitions
// ─────────────────────────────────────────────────────────────────────────────

/// Where to draw the spotlight cutout (normalised 0–1 coords).
/// [cx], [cy] = centre; [w], [h] = size; [r] = corner radius fraction.
class _SpotRect {
  final double cx, cy, w, h, r;
  const _SpotRect(this.cx, this.cy, this.w, this.h, {this.r = 0.06});
}

class _Step {
  final String title;
  final String body;
  final int tab; // which bottom-tab to navigate to (-1 = keep current)
  final _SpotRect? spot; // null = no spotlight (intro/outro step)
  final bool tipBelow; // show tooltip below the spotlight?

  const _Step({
    required this.title,
    required this.body,
    this.tab = 0,
    this.spot,
    this.tipBelow = false,
  });
}

const _kSteps = [
  // 0 – Welcome (no spotlight)
  _Step(
    title: 'Welcome to Pixels to Macros! 👋',
    body: "Let's take a quick tour so you know where everything is.",
    tab: 0,
  ),
  // 1 – Scan button (FAB bottom-right on Home)
  _Step(
    title: 'AI Scan 📷',
    body: 'Tap AI Scan to open the camera.\nPoint at your plate and get instant calories & macros!\nIncludes flashlight toggle and low-light warnings.',
    tab: 0,
    spot: _SpotRect(0.80, 0.88, 0.44, 0.08),
  ),
  // 2 – Voice entry (small FAB above manual)
  _Step(
    title: 'Voice Logging 🎤',
    body: 'Tap the mic button to log food by speaking in English.\nSay "200 grams of chicken and a banana" — it matches your food database automatically.',
    tab: 0,
    spot: _SpotRect(0.88, 0.71, 0.14, 0.07),
  ),
  // 3 – Manual log (small FAB above voice)
  _Step(
    title: 'Log Food Manually ✏️',
    body: 'Search foods, pick from My Meals, scan a barcode, or quick-add a drink.\nBarcode scanning shows a health score (0-100) before logging.',
    tab: 0,
    spot: _SpotRect(0.88, 0.79, 0.14, 0.07),
  ),
  // 4 – Body map icon (top-left of AppBar actions)
  _Step(
    title: 'Body Map 🫀',
    body: 'Tap the body icon (top-right) to see a 2D interactive body map.\nEach organ glows based on your nutrient intake — tap to learn why!',
    tab: 0,
    spot: _SpotRect(0.70, 0.075, 0.13, 0.055),
    tipBelow: true,
  ),
  // 5 – Nutrition button (leaf icon on Home)
  _Step(
    title: "Today's Nutrition 🌿",
    body: 'The leaf icon shows a full breakdown of vitamins, minerals, macros and your micronutrient wheel.',
    tab: 0,
    spot: _SpotRect(0.88, 0.075, 0.13, 0.055),
    tipBelow: true,
  ),
  // 7 – Hydration card on home screen
  _Step(
    title: 'Stay Hydrated 💧',
    body: 'The hydration card on the home screen tracks your water intake.\nTap the quick-add buttons (150 / 250 / 500 ml) to log glasses throughout the day.',
    tab: 0,
  ),
  // 8 – Analytics tab
  _Step(
    title: 'Analytics 📊',
    body: 'Track weekly & monthly calorie and macro trends here.',
    tab: 1,
    spot: _SpotRect(0.30, 0.965, 0.22, 0.07),
  ),
  // 9 – Groceries tab
  _Step(
    title: 'Grocery List 🛒',
    body: 'Add items manually or get smart suggestions based on your scan history.',
    tab: 2,
    spot: _SpotRect(0.50, 0.965, 0.22, 0.07),
  ),
  // 10 – Settings tab
  _Step(
    title: 'Settings ⚙️',
    body: 'Change your nutrition goal, color theme, mascot, text size, and more.\nDiabetes users can set ICR for bolus calculations.',
    tab: 4,
    spot: _SpotRect(0.90, 0.965, 0.22, 0.07),
  ),
  // 11 – Vacation mode & advanced settings
  _Step(
    title: 'Vacation Mode & More 🏖️',
    body: "Turn on Vacation Mode in Settings → Account to protect your streak while you're away.\nYou can also adjust your daily water goal and Glycemic Load thermometer (diabetes).",
    tab: 4,
  ),
  // 12 – Outro
  _Step(
    title: "You're All Set! 🚀",
    body: "Start scanning your first meal — or speak it!\n\nTip: you can replay this tour anytime from Settings → About.",
    tab: 0,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _AppTutorialOverlayState extends State<AppTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _spotScale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _spotScale = Tween<double>(begin: 1.15, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
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
      widget.onNavigateToTab(_kSteps[_step].tab);
      _ctrl.forward();
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
          // ── Full-screen dark overlay (always blocks touches) ──────────
          Positioned.fill(
            child: GestureDetector(
              // Absorb all taps on the dimmed area so nothing behind fires.
              onTap: () {},
              child: step.spot != null
                  ? ScaleTransition(
                      scale: _spotScale,
                      child: CustomPaint(
                        size: size,
                        painter: _SpotlightPainter(
                          spot: step.spot!,
                          screenSize: size,
                        ),
                      ),
                    )
                  : Container(color: Colors.black.withValues(alpha: 0.82)),
            ),
          ),

          // ── Skip button ───────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
// Spotlight painter
// ─────────────────────────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final _SpotRect spot;
  final Size screenSize;

  const _SpotlightPainter({required this.spot, required this.screenSize});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = spot.cx * size.width;
    final cy = spot.cy * size.height;
    final w = spot.w * size.width;
    final h = spot.h * size.height;
    final r = spot.r * math.min(size.width, size.height);

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: w + 16, height: h + 16),
      Radius.circular(r),
    );

    // Dark overlay with cutout
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.82);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Bright highlight ring around the spotlight
    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    // Outer glow
    canvas.drawRRect(
      rect.inflate(6),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.spot != spot || old.screenSize != screenSize;
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


