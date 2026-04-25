/// All possible states in the scanning flow.
///
/// The Flutter UI drives transitions; heavy work happens natively via
/// MethodChannel.
enum ScanState {
  // ── Happy path ──────────────────────────────────────────────────────────────
  /// Session started — waiting for user to point phone straight down at food.
  waitingForTopView,

  /// Session started — user can press button to begin recording (manual fallback).
  readyToRecord,

  /// Short video sweep is being recorded (auto-started at top-view).
  recording,

  /// Processing — run ML inference & 3-D volume calculation.
  calculating,

  /// Results ready — navigate to result screen.
  done,

  // ── Legacy single-frame states (kept for backward compatibility) ────────────
  /// Prompt user to hold phone above plate.
  alignTop,
  /// Capture top-down RGB frame.
  captureTop,
  /// Show animated arrow — "move phone to the side".
  moveSide,
  /// Capture side frame + depth map.
  captureSide,

  // ── Failure states ──────────────────────────────────────────────────────────
  /// Depth data could not be acquired.
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
      case ScanState.waitingForTopView:
        return 'Hold your phone flat, pointing straight down at the food';
      case ScanState.readyToRecord:
        return 'Press the button to start scanning';
      case ScanState.recording:
        return 'Slowly tilt your phone upright (~2 seconds)…';
      case ScanState.calculating:
        return 'Building 3-D model & calculating nutrition…';
      case ScanState.done:
        return 'Done!';
      case ScanState.alignTop:
        return 'Hold phone above plate';
      case ScanState.captureTop:
        return 'Capturing top view…';
      case ScanState.moveSide:
        return 'Move phone smoothly to the side';
      case ScanState.captureSide:
        return 'Capturing side view…';
      case ScanState.depthFailed:
        return 'Camera session failed — tap \'Try again\'';
      case ScanState.modelFailed:
        return 'Analysis error — tap Retry to try again';
      case ScanState.plateNotDetected:
        return 'No food detected — make sure food fills the frame, then try again';
    }
  }

  /// Whether this state is a failure that can be retried.
  bool get isError {
    return this == ScanState.depthFailed ||
        this == ScanState.modelFailed ||
        this == ScanState.plateNotDetected;
  }
}
