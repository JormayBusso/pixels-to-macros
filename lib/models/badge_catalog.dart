import 'package:flutter/material.dart';

/// Static, display-only metadata for every badge the app can award.
///
/// Keyed by the stable badge id used in [WeeklyBadge] and the `earned_badges`
/// table. Icons are referenced as const `Icons.*` so the icon font tree-shaker
/// retains the glyphs (avoids dynamic `IconData`, which breaks release builds).
/// Localized title/subtitle come from `AppLocalizations.weeklyBadgeText(id)`.
class BadgeCatalogEntry {
  const BadgeCatalogEntry({
    required this.id,
    required this.icon,
    required this.color,
  });

  final String id;
  final IconData icon;
  final Color color;
}

/// All badges, in the order they should appear in the collection.
const List<BadgeCatalogEntry> kBadgeCatalog = [
  BadgeCatalogEntry(
    id: 'perfect_log_week',
    icon: Icons.verified_outlined,
    color: Color(0xFF2E7D32),
  ),
  BadgeCatalogEntry(
    id: 'steady_tracker',
    icon: Icons.event_available_outlined,
    color: Color(0xFF00897B),
  ),
  BadgeCatalogEntry(
    id: 'streak_builder',
    icon: Icons.local_fire_department_outlined,
    color: Color(0xFFEF6C00),
  ),
  BadgeCatalogEntry(
    id: 'scanner_momentum',
    icon: Icons.camera_alt_outlined,
    color: Color(0xFF1565C0),
  ),
  BadgeCatalogEntry(
    id: 'protein_focus',
    icon: Icons.fitness_center_outlined,
    color: Color(0xFF6A1B9A),
  ),
  BadgeCatalogEntry(
    id: 'balanced_plate',
    icon: Icons.donut_large_outlined,
    color: Color(0xFF455A64),
  ),
  BadgeCatalogEntry(
    id: 'micronutrient_pro',
    icon: Icons.spa_outlined,
    color: Color(0xFF558B2F),
  ),
  BadgeCatalogEntry(
    id: 'hydration_rhythm',
    icon: Icons.water_drop_outlined,
    color: Color(0xFF0277BD),
  ),
];

/// Lookup map for O(1) access by badge id.
final Map<String, BadgeCatalogEntry> kBadgeCatalogById = {
  for (final entry in kBadgeCatalog) entry.id: entry,
};
