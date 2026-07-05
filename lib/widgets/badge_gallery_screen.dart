import 'package:flutter/material.dart';

import '../core/app_localizations.dart';
import '../models/badge_catalog.dart';
import '../models/earned_badge.dart';
import '../services/weekly_badge_service.dart';
import '../theme/app_theme.dart';

/// Full-screen gallery of every badge the app can award, showing which ones
/// the user has collected and which are still locked. Opened from Settings.
class BadgeGalleryScreen extends StatefulWidget {
  const BadgeGalleryScreen({super.key});

  @override
  State<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends State<BadgeGalleryScreen> {
  late Future<List<EarnedBadge>> _future;

  @override
  void initState() {
    super.initState();
    _future = WeeklyBadgeService.instance.earnedBadges();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.badgeCollectionTitle),
      ),
      body: FutureBuilder<List<EarnedBadge>>(
        future: _future,
        builder: (context, snapshot) {
          final earned = snapshot.data ?? const <EarnedBadge>[];
          final earnedIds = earned.map((b) => b.badgeId).toSet();
          final total = kBadgeCatalog.length;
          final pct = total == 0 ? 0.0 : earnedIds.length / total;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _CollectionHeader(
                earned: earnedIds.length,
                total: total,
                pct: pct,
              ),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 18,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
                children: kBadgeCatalog.map((entry) {
                  final unlocked = earnedIds.contains(entry.id);
                  return _GalleryMedallion(
                    entry: entry,
                    unlocked: unlocked,
                    onTap: () => _showBadgeDetail(context, entry, unlocked),
                  );
                }).toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.earned,
    required this.total,
    required this.pct,
  });

  final int earned;
  final int total;
  final double pct;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = context.primary500;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.04),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, Color.lerp(accent, Colors.black, 0.28)!],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.badgeCollectionCount(earned, total),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: context.appTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: context.appSubtleFillColor,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryMedallion extends StatelessWidget {
  const _GalleryMedallion({
    required this.entry,
    required this.unlocked,
    required this.onTap,
  });

  final BadgeCatalogEntry entry;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.weeklyBadgeText(entry.id).title;
    final muted = context.appMutedTextColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: unlocked
                ? _UnlockedMedallion(color: entry.color, icon: entry.icon)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: muted.withValues(alpha: 0.12),
                      border: Border.all(color: muted.withValues(alpha: 0.28)),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: muted.withValues(alpha: 0.7),
                      size: 26,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              fontWeight: unlocked ? FontWeight.w700 : FontWeight.w500,
              color: unlocked ? context.appTextColor : muted,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            unlocked ? l10n.badgeEarnedLabel : l10n.badgeLockedLabel,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: unlocked
                  ? entry.color
                  : muted.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collected badge medallion: gradient fill, drop shadow, and a soft shine
/// highlight for a polished, "premium" look.
class _UnlockedMedallion extends StatelessWidget {
  const _UnlockedMedallion({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.15)!,
            color,
            Color.lerp(color, Colors.black, 0.32)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: const Alignment(-0.4, -0.5),
            child: FractionallySizedBox(
              widthFactor: 0.42,
              heightFactor: 0.32,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
          Icon(icon, color: Colors.white, size: 30),
        ],
      ),
    );
  }
}

void _showBadgeDetail(
  BuildContext context,
  BadgeCatalogEntry entry,
  bool unlocked,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) =>
        _BadgeDetailSheet(entry: entry, unlocked: unlocked),
  );
}

class _BadgeDetailSheet extends StatelessWidget {
  const _BadgeDetailSheet({required this.entry, required this.unlocked});

  final BadgeCatalogEntry entry;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = l10n.weeklyBadgeText(entry.id);
    final muted = context.appMutedTextColor;

    return Container(
      decoration: BoxDecoration(
        color: context.appSurfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 92,
                height: 92,
                child: unlocked
                    ? _UnlockedMedallion(color: entry.color, icon: entry.icon)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: muted.withValues(alpha: 0.12),
                          border:
                              Border.all(color: muted.withValues(alpha: 0.28)),
                        ),
                        child: Icon(
                          Icons.lock_outline,
                          color: muted.withValues(alpha: 0.7),
                          size: 40,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                text.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: context.appTextColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: unlocked
                      ? entry.color.withValues(alpha: 0.14)
                      : muted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      unlocked ? Icons.check_circle : Icons.lock_outline,
                      size: 15,
                      color: unlocked ? entry.color : muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      unlocked ? l10n.badgeEarnedLabel : l10n.badgeLockedLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: unlocked ? entry.color : muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (unlocked)
                Text(
                  text.subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: context.appTextColor,
                  ),
                )
              else ...[
                Text(
                  l10n.badgeHowToEarnLabel.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.weeklyBadgeHowTo(entry.id),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: context.appTextColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
