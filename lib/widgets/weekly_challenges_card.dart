import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/challenge_provider.dart';
import '../theme/app_theme.dart';

/// Compact card showing this week's 3 challenges with progress.
class WeeklyChallengesCard extends ConsumerWidget {
  const WeeklyChallengesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weeklyChallengeProvider);
    if (state.activeChallenges.isEmpty) return const SizedBox.shrink();

    final completed = state.completedCount();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Weekly Challenges',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: completed == state.activeChallenges.length
                      ? Colors.green.withValues(alpha: 0.12)
                      : context.primary100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$completed/${state.activeChallenges.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: completed == state.activeChallenges.length
                        ? Colors.green
                        : context.primary600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...state.activeChallenges.map((c) {
            final progress = state.progress[c.type] ?? 0;
            final done = progress >= c.target;
            final pct = (progress / c.target).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(c.icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            color: done ? AppTheme.gray400 : AppTheme.gray800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 4,
                            backgroundColor: AppTheme.gray100,
                            color: done ? Colors.green : context.primary500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    done ? '✓' : '$progress/${c.target}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: done ? Colors.green : AppTheme.gray500,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Small pill showing streak freeze count.
class StreakFreezeIndicator extends ConsumerWidget {
  const StreakFreezeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freeze = ref.watch(streakFreezeProvider);
    return Tooltip(
      message: '${freeze.remaining} streak freezes left this week',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: freeze.remaining > 0
              ? Colors.blue.withValues(alpha: 0.10)
              : AppTheme.gray100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ac_unit,
              size: 14,
              color: freeze.remaining > 0 ? Colors.blue : AppTheme.gray400,
            ),
            const SizedBox(width: 3),
            Text(
              '${freeze.remaining}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: freeze.remaining > 0 ? Colors.blue : AppTheme.gray400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
