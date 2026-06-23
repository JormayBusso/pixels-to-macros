import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../providers/progress_story_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_theme_effects.dart';

class ProgressStoryScreen extends ConsumerStatefulWidget {
  const ProgressStoryScreen({super.key});

  @override
  ConsumerState<ProgressStoryScreen> createState() =>
      _ProgressStoryScreenState();
}

class _ProgressStoryScreenState extends ConsumerState<ProgressStoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(progressStoryProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final story = ref.watch(progressStoryProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.progressStoryTitle),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: () => ref.read(progressStoryProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: story.loading
          ? const Center(child: CircularProgressIndicator())
          : story.error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 40,
                          color: AppTheme.red500,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.progressStoryLoadFailed,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.gray700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () =>
                              ref.read(progressStoryProvider.notifier).load(),
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(progressStoryProvider.notifier).load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _HeroStoryCard(story: story),
                      const SizedBox(height: 14),
                      _StoryTile(
                        icon: Icons.camera_alt_outlined,
                        title: l10n.storyTotalScans(story.totalScans),
                        body: l10n.storyTotalScansBody,
                        color: AppTheme.green600,
                      ),
                      _StoryTile(
                        icon: Icons.calendar_today_outlined,
                        title: l10n.storyLoggedDays(story.loggedDays30),
                        body: l10n.storyLoggedDaysBody,
                        color: Colors.blue.shade600,
                      ),
                      _StoryTile(
                        icon: Icons.local_fire_department_outlined,
                        title: l10n.storyAverageCalories(
                          story.averageCalories30.round(),
                        ),
                        body: l10n.storyAverageCaloriesBody,
                        color: Colors.orange.shade700,
                      ),
                      _StoryTile(
                        icon: Icons.monitor_weight_outlined,
                        title: l10n.storyWeightTrend(
                          story.monthlyWeightChangeKg,
                        ),
                        body: l10n.storyWeightTrendBody,
                        color: Colors.purple.shade500,
                      ),
                      _StoryTile(
                        icon: Icons.restaurant_menu_outlined,
                        title: l10n.storyPlannedMeals(
                          story.plannedMealsThisWeek,
                        ),
                        body: l10n.storyPlannedMealsBody,
                        color: Colors.teal.shade600,
                      ),
                      _StoryTile(
                        icon: Icons.kitchen_outlined,
                        title:
                            l10n.storyPantryItems(story.availablePantryItems),
                        body: l10n.storyPantryItemsBody,
                        color: Colors.brown.shade500,
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _HeroStoryCard extends StatelessWidget {
  const _HeroStoryCard({required this.story});

  final ProgressStoryState story;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final momentum = (story.loggedDays30 / 30).clamp(0.0, 1.0);
    return PremiumSurface(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.progressStorySubtitle,
            style: TextStyle(
              fontSize: 13,
              color: context.appMutedTextColor,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: momentum,
              minHeight: 10,
              backgroundColor: context.primary100,
              valueColor: AlwaysStoppedAnimation(context.primary600),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.progressMomentum((momentum * 100).round()),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.primary700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.gray600,
                      height: 1.3,
                    ),
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
