import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_diagnostics.dart';

/// Keeps the most recent scanner diagnostics snapshots in memory so they can be
/// inspected from the diagnostics screen during a validation session. Capped to
/// avoid unbounded growth; not persisted (diagnostics are a debugging aid).
class ScanDiagnosticsNotifier extends StateNotifier<List<ScanDiagnostics>> {
  ScanDiagnosticsNotifier() : super(const []);

  static const int maxEntries = 25;

  void add(ScanDiagnostics diagnostics) {
    final next = [diagnostics, ...state];
    state = next.length > maxEntries ? next.sublist(0, maxEntries) : next;
  }

  void clear() => state = const [];

  ScanDiagnostics? get latest => state.isEmpty ? null : state.first;
}

final scanDiagnosticsProvider =
    StateNotifierProvider<ScanDiagnosticsNotifier, List<ScanDiagnostics>>(
  (ref) => ScanDiagnosticsNotifier(),
);
