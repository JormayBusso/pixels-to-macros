/// A persisted achievement badge the user has earned.
///
/// Only stable, display-independent data is stored: the badge [id] (used to
/// look up the icon/colour/title from a const catalog and localization), the
/// [weekKey] it was earned for (the previous-week Monday, so each badge is
/// earned at most once per week), the dynamic [metric] string captured at award
/// time, and [earnedAt].
class EarnedBadge {
  const EarnedBadge({
    this.id,
    required this.badgeId,
    required this.weekKey,
    required this.metric,
    required this.earnedAt,
  });

  final int? id;
  final String badgeId;
  final String weekKey;
  final String metric;
  final DateTime earnedAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'badge_id': badgeId,
        'week_key': weekKey,
        'metric': metric,
        'earned_at': earnedAt.toIso8601String(),
      };

  factory EarnedBadge.fromMap(Map<String, dynamic> map) => EarnedBadge(
        id: map['id'] as int?,
        badgeId: map['badge_id'] as String,
        weekKey: map['week_key'] as String? ?? '',
        metric: map['metric'] as String? ?? '',
        earnedAt: DateTime.tryParse(map['earned_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
