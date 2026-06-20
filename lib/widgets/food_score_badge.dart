import 'package:flutter/material.dart';

import '../core/app_localizations.dart';
import '../services/food_scoring_service.dart';
import '../theme/app_theme.dart';

class FoodScoreBadge extends StatelessWidget {
  const FoodScoreBadge({
    super.key,
    required this.explanation,
    this.compact = false,
  });

  final FoodScoreExplanation explanation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _scoreColor(explanation.score, context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _showDetails(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_alt_outlined, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              '${explanation.score}/100',
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(
                l10n.foodScoreTitle(explanation.titleKey),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _scoreColor(explanation.score, context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.psychology_alt_outlined, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.foodScore,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.gray500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${explanation.score}/100 - ${l10n.foodScoreTitle(explanation.titleKey)}',
                        style: TextStyle(
                          fontSize: 18,
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.whyThisScore,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ...explanation.reasons.map(
              (reason) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline, size: 17, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.foodScoreReason(reason),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppTheme.gray700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(int score, BuildContext context) {
    if (score >= 75) return context.primary600;
    if (score >= 50) return AppTheme.amber700;
    return AppTheme.red500;
  }
}
