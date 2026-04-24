import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/scan_state.dart';

/// Notifier that drives the scanning state machine (Part 4).
///
/// The UI observes this to show the correct screen / instructions.
class ScanStateNotifier extends StateNotifier<ScanState> {
  ScanStateNotifier() : super(ScanState.waitingForTopView);

  // ── Happy-path transitions ───────────────────────────────────────────────

  /// Session started — waiting for user to point phone down.
  void sessionReady()      => state = ScanState.waitingForTopView;
  /// Top-view detected — ready to record (or auto-start).
  void topViewDetected()   => state = ScanState.readyToRecord;
  void startedRecording()  => state = ScanState.recording;
  void recordingStopped()  => state = ScanState.calculating;
  void calculationDone()   => state = ScanState.done;

  // ── Legacy single-frame transitions (kept for compatibility) ─────────────
  void topAligned()        => state = ScanState.captureTop;
  void topCaptured()       => state = ScanState.moveSide;
  void sideReady()         => state = ScanState.captureSide;
  void sideCaptured()      => state = ScanState.calculating;

  // ── Error transitions ────────────────────────────────────────────────────

  void depthFailed() => state = ScanState.depthFailed;
  void modelFailed() => state = ScanState.modelFailed;
  void plateNotDetected() => state = ScanState.plateNotDetected;

  // ── Retry / reset ────────────────────────────────────────────────────────

  void reset() => state = ScanState.waitingForTopView;
}

/// Global provider for the scanning state machine.
final scanStateProvider =
    StateNotifierProvider<ScanStateNotifier, ScanState>(
  (ref) => ScanStateNotifier(),
);
