/// A user-logged actual insulin dose.
///
/// This is the *actual* insulin the user reports having taken — it is only ever
/// created after an explicit user confirmation (see the dose-logging UI and
/// [confirmed]). It feeds future insulin-on-board (IOB) calculations.
///
/// The app never auto-logs a calculated estimate as a taken dose.
class InsulinDoseLog {
  const InsulinDoseLog({
    this.id,
    required this.units,
    required this.timestamp,
    required this.confirmed,
    this.notes,
    this.calculationId,
  });

  final int? id;

  /// Actual units the user reports taking.
  final double units;

  /// When the dose was taken (local time).
  final DateTime timestamp;

  /// True only when the user ticked "I confirm I took this dose". A row is not
  /// persisted as a real dose unless this is true.
  final bool confirmed;

  /// Optional free-text note.
  final String? notes;

  /// Optional link back to the bolus audit record that suggested this dose.
  final String? calculationId;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'units': units,
        'timestamp': timestamp.toIso8601String(),
        'confirmed': confirmed ? 1 : 0,
        'notes': notes,
        'calculation_id': calculationId,
      };

  factory InsulinDoseLog.fromMap(Map<String, dynamic> m) => InsulinDoseLog(
        id: m['id'] as int?,
        units: (m['units'] as num).toDouble(),
        timestamp: DateTime.parse(m['timestamp'] as String),
        confirmed: (m['confirmed'] as int?) == 1,
        notes: m['notes'] as String?,
        calculationId: m['calculation_id'] as String?,
      );
}
