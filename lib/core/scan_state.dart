/// All possible states in the scanning flow.
///
/// The Flutter UI drives transitions; heavy work happens natively via
/// MethodChannel.
enum ScanState {
  // ── Happy path ──────────────────────────────────────────────────────────────
  /// Prompt user to hold phone above plate.
  alignTop,

  /// Capture top-down RGB frame.
  captureTop,

  /// Show animated arrow — "move phone to the side".
  moveSide,

  /// Capture side frame + depth map.
  captureSide,

  /// Processing — run ML inference & volume calculation.
  calculating,

  /// Results ready — navigate to result screen.
  done,

  // ── Failure states ──────────────────────────────────────────────────────────
  /// Depth data could not be acquired (no LiDAR + no fallback).
  depthFailed,

  /// CoreML model failed to load or inference crashed.
  modelFailed,

  /// Plate boundary was not detected in the frame.
  plateNotDetected,
}

/// Human-readable label for each state (used for on-screen instructions).
extension ScanStateLabel on ScanState {
  String get label {
    switch (this) {
      case ScanState.alignTop:
        return 'Hold phone above plate';
      case ScanState.captureTop:
        return 'Capturing top view…';
      case ScanState.moveSide:
        return 'Move phone smoothly to the side';
      case ScanState.captureSide:
        return 'Capturing side view…';
      case ScanState.calculating:
        return 'Calculating nutrition…';
      case ScanState.done:
        return 'Done!';
      case ScanState.depthFailed:
        return 'Depth capture failed — try again';
      case ScanState.modelFailed:
        return 'Model error — please restart';
      case ScanState.plateNotDetected:
        return 'Plate not found — reposition';
    }
  }

  /// Whether this state is a failure that can be retried.
  bool get isError {
    return this == ScanState.depthFailed ||
        this == ScanState.modelFailed ||
        this == ScanState.plateNotDetected;
  }
}
