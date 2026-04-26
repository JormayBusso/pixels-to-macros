import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../services/database_service.dart';

/// Holds the list of past scan results loaded from SQLite.
class HistoryState {
  final bool loading;
  final List<ScanResult> scans;

  const HistoryState({this.loading = false, this.scans = const []});

  HistoryState copyWith({bool? loading, List<ScanResult>? scans}) {
    return HistoryState(
      loading: loading ?? this.loading,
      scans: scans ?? this.scans,
    );
  }
}

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier() : super(const HistoryState());

  Future<void> load() async {
    state = state.copyWith(loading: true);
    final scans = await DatabaseService.instance.getAllScanResults();
    state = HistoryState(scans: scans);
  }

  Future<void> addScan(ScanResult result) async {
    await DatabaseService.instance.insertScanResult(result);
    await load(); // refresh
  }

  Future<void> deleteScan(int scanId) async {
    await DatabaseService.instance.deleteScanResult(scanId);
    await load();
  }

  /// Delete a single detected food from a scan and refresh.
  Future<void> deleteDetectedFood(int detectedFoodId) async {
    await DatabaseService.instance.deleteDetectedFood(detectedFoodId);
    await load();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryState>(
  (ref) => HistoryNotifier(),
);
