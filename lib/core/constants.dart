/// App-wide constants.
class AppConstants {
  AppConstants._();

  /// Default plate diameter in cm — used when plate detection
  /// cannot determine the size automatically.
  static const double defaultPlateDiameterCm = 26.0;

  /// Maximum number of frames kept in memory at any time.
  static const int maxFramesInMemory = 2;

  /// Maximum frame resolution passed to CoreML (width × height).
  static const int maxFrameWidth = 640;
  static const int maxFrameHeight = 480;

  /// Target CoreML inference latency.
  static const Duration maxInferenceTime = Duration(milliseconds: 200);

  /// Target total scan time.
  static const Duration maxScanTime = Duration(seconds: 3);

  /// MethodChannel name shared with the native Swift side.
  static const String methodChannelName = 'com.pixelstomacros/scanner';

  /// SQLite database file name.
  static const String databaseName = 'pixels_to_macros.db';
}

/// Depth mode detected at runtime (Part 2 of the architecture).
enum DepthMode {
  /// ARKit LiDAR sceneDepth (best accuracy).
  lidar,

  /// Camera-based depth estimation (mid accuracy).
  cameraDepth,

  /// 2D plate-scale fallback (lowest accuracy).
  plateFallback,
}
