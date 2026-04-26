import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Step-by-step first-launch tutorial overlay for the main shell.
/// Highlights key UI elements and explains navigation.
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

class _AppTutorialOverlayState extends State<AppTutorialOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  static const _steps = [
    _TutorialStep(
      title: 'Welcome to Pixels to Macros! 🎉',
      description:
          'Let\'s take a quick tour so you know where everything is.\n\n'
          'You\'re on the Home tab — this is your daily dashboard with '
          'calorie tracking, streak, and food breakdown.',
      icon: Icons.home,
      highlightArea: _HighlightArea.homeTab,
    ),
    _TutorialStep(
      title: 'Scan Your Food 📷',
      description:
          'Tap the big "Scan" button to open the camera and instantly '
          'scan your meal. Just point, sweep, and get calories + macros!',
      icon: Icons.camera_alt,
      highlightArea: _HighlightArea.scanButton,
    ),
    _TutorialStep(
      title: 'Log Food Manually ✏️',
      description:
          'The small button above the Scan button lets you manually add '
          'food from the database. You can select multiple items at once!',
      icon: Icons.edit_note,
      highlightArea: _HighlightArea.manualButton,
    ),
    _TutorialStep(
      title: 'Today\'s Nutrition 🌿',
      description:
          'Tap the leaf icon in the top-right corner or tap your mascot '
          'to see a full breakdown: vitamins, minerals, and macros.',
      icon: Icons.eco,
      highlightArea: _HighlightArea.nutritionButton,
    ),
    _TutorialStep(
      title: 'Analytics 📊',
      description:
          'The Analytics tab shows your weekly and monthly trends — '
          'calories, macros, and scan history over time.',
      icon: Icons.bar_chart,
      highlightArea: _HighlightArea.analyticsTab,
    ),
    _TutorialStep(
      title: 'Grocery List 🛒',
      description:
          'The Groceries tab helps you plan your shopping. Add items '
          'manually or get smart suggestions based on your meal history.',
      icon: Icons.shopping_cart,
      highlightArea: _HighlightArea.groceriesTab,
    ),
    _TutorialStep(
      title: 'Settings ⚙️',
      description:
          'In Settings you can change your app color theme, choose your '
          'mascot, update your nutrition goal, and adjust macro targets.',
      icon: Icons.settings,
      highlightArea: _HighlightArea.settingsTab,
    ),
    _TutorialStep(
      title: 'You\'re All Set! 🚀',
      description:
          'Start scanning your first meal to begin tracking.\n\n'
          'Tip: The more you scan, the smarter your recommendations get!',
      icon: Icons.rocket_launch,
      highlightArea: _HighlightArea.none,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      // Navigate to the relevant tab for context
      final step = _steps[_step];
      switch (step.highlightArea) {
        case _HighlightArea.homeTab:
        case _HighlightArea.scanButton:
        case _HighlightArea.manualButton:
        case _HighlightArea.nutritionButton:
          widget.onNavigateToTab(0);
        case _HighlightArea.analyticsTab:
          widget.onNavigateToTab(1);
        case _HighlightArea.groceriesTab:
          widget.onNavigateToTab(2);
        case _HighlightArea.settingsTab:
          widget.onNavigateToTab(4);
        case _HighlightArea.none:
          widget.onNavigateToTab(0);
      }
    } else {
      _dismiss();
    }
  }

  void _dismiss() {
    _fadeCtrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;

    return FadeTransition(
      opacity: _fade,
      child: Material(
        color: Colors.black.withValues(alpha: 0.75),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _dismiss,
                    child: const Text(
                      'Skip Tour',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Step content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    key: ValueKey(_step),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: context.primary500.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          step.icon,
                          size: 40,
                          color: context.primary400,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        step.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Description
                      Text(
                        step.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Progress dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _step ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _step
                          ? context.primary400
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              // Next / Done button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primary500,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isLast ? 'Start Scanning!' : 'Next',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Step counter
              Text(
                '${_step + 1} of ${_steps.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HighlightArea {
  none,
  homeTab,
  scanButton,
  manualButton,
  nutritionButton,
  analyticsTab,
  groceriesTab,
  settingsTab,
}

class _TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final _HighlightArea highlightArea;

  const _TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.highlightArea,
  });
}
