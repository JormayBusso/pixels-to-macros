import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../providers/challenge_provider.dart';
import '../theme/app_theme.dart';
import 'premium_theme_effects.dart';

/// Compact card showing this week's 3 challenges with progress.
class WeeklyChallengesCard extends ConsumerWidget {
  const WeeklyChallengesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weeklyChallengeProvider);
    if (state.activeChallenges.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final completed = state.completedCount();

    return PremiumSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.weeklyChallengesTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
            final title = l10n.weeklyChallengeText(c.type.name).title;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showChallengeDetail(context, c, progress),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(c.icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                                color: done
                                    ? context.appMutedTextColor
                                    : context.appTextColor,
                              ),
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 4,
                                backgroundColor: context.appSubtleFillColor,
                                color:
                                    done ? Colors.green : context.primary500,
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
                          color:
                              done ? Colors.green : context.appMutedTextColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color:
                            context.appMutedTextColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

void _showChallengeDetail(
  BuildContext context,
  Challenge challenge,
  int progress,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _ChallengeDetailSheet(challenge: challenge, progress: progress),
  );
}

class _ChallengeDetailSheet extends StatelessWidget {
  const _ChallengeDetailSheet({
    required this.challenge,
    required this.progress,
  });

  final Challenge challenge;
  final int progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = l10n.weeklyChallengeText(challenge.type.name);
    final done = progress >= challenge.target;
    final pct = (progress / challenge.target).clamp(0.0, 1.0);
    final accent = context.primary500;

    return Container(
      decoration: BoxDecoration(
        color: context.appSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appMutedTextColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent,
                          Color.lerp(accent, Colors.black, 0.28)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Text(
                      challenge.icon,
                      style: const TextStyle(fontSize: 26),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      text.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: context.appTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                l10n.challengeHowToTitle.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: context.appMutedTextColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text.howTo,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: context.appTextColor,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: context.appSubtleFillColor,
                  color: done ? Colors.green : accent,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$progress / ${challenge.target}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.appTextColor,
                    ),
                  ),
                  if (done)
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          l10n.challengeCompletedLabel,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ],
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
              : context.appSubtleFillColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ac_unit,
              size: 14,
              color: freeze.remaining > 0 ? Colors.blue : context.appMutedTextColor,
            ),
            const SizedBox(width: 3),
            Text(
              '${freeze.remaining}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: freeze.remaining > 0 ? Colors.blue : context.appMutedTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
