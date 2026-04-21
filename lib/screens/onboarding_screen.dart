import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_prefs_provider.dart';
import '../theme/app_theme.dart';

/// First-launch onboarding: collects name and daily calorie goal.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  // Page 1: name
  final _nameCtrl = TextEditingController();

  // Page 2: calorie goal
  int _selectedGoal = 2000;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 2) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    await ref.read(userPrefsProvider.notifier).completeOnboarding(
          name: _nameCtrl.text.trim(),
          dailyCalorieGoal: _selectedGoal,
        );
    // Parent widget (app.dart) will react to onboardingComplete becoming true.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.green50,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _page == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _page == i ? AppTheme.green600 : AppTheme.green200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                onPageChanged: (i) => setState(() => _page = i),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomePage(onNext: _next),
                  _NamePage(
                    controller: _nameCtrl,
                    onNext: _next,
                  ),
                  _GoalPage(
                    selectedGoal: _selectedGoal,
                    onGoalChanged: (g) => setState(() => _selectedGoal = g),
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 0: Welcome ──────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext});
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.green100,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.green300, width: 3),
            ),
            child: const Icon(Icons.eco, size: 56, color: AppTheme.green600),
          ),
          const SizedBox(height: 32),
          const Text(
            'Pixels to Macros',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppTheme.green700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scan your food with your camera and get\n'
            'instant calorie estimates — 100% offline.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.gray400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Get Started'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 1: Name ─────────────────────────────────────────────────────────────

class _NamePage extends StatelessWidget {
  const _NamePage({required this.controller, required this.onNext});
  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_outline, size: 56, color: AppTheme.green500),
          const SizedBox(height: 24),
          const Text(
            'What\'s your name?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'We\'ll use it to personalise your dashboard.',
            style: TextStyle(fontSize: 14, color: AppTheme.gray400),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Page 2: Calorie Goal ─────────────────────────────────────────────────────

class _GoalPage extends StatelessWidget {
  const _GoalPage({
    required this.selectedGoal,
    required this.onGoalChanged,
    required this.onFinish,
  });
  final int selectedGoal;
  final ValueChanged<int> onGoalChanged;
  final VoidCallback onFinish;

  static const _presets = [
    (1500, 'Weight loss', Icons.trending_down),
    (1800, 'Mild deficit', Icons.remove_circle_outline),
    (2000, 'Maintain', Icons.balance),
    (2200, 'Mild surplus', Icons.add_circle_outline),
    (2500, 'Muscle gain', Icons.trending_up),
    (3000, 'Bulking', Icons.fitness_center),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_outlined, size: 56, color: AppTheme.green500),
          const SizedBox(height: 24),
          const Text(
            'Daily calorie goal',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$selectedGoal kcal / day',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.green700,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _presets.map((p) {
              final isActive = p.$1 == selectedGoal;
              return ChoiceChip(
                avatar: Icon(p.$3,
                    size: 18,
                    color: isActive ? AppTheme.green700 : AppTheme.gray400),
                label: Text('${p.$1}'),
                selected: isActive,
                selectedColor: AppTheme.green200,
                onSelected: (_) => onGoalChanged(p.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onFinish,
              child: const Text('Start Scanning!'),
            ),
          ),
        ],
      ),
    );
  }
}
