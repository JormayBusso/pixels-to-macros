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

/// The scanning strategy selected for the current device.
///
/// Only two tiers exist on the supported device range (iPhone 15+):
///   • [lidar]  — Pro models with a LiDAR sensor (real depth + 3-D mesh).
///   • [camera] — non-Pro models (monocular camera + reference-scale).
enum ScanTier {
  lidar,
  camera;

  static ScanTier fromRaw(String raw) =>
      raw == 'lidar' ? ScanTier.lidar : ScanTier.camera;

  bool get hasLiDAR => this == ScanTier.lidar;
}

/// Snapshot of the current device's scanning capabilities, mirrored from the
/// native `DepthModeDetector.DeviceCapabilities`.
class DeviceCapabilities {
  final ScanTier tier;
  final bool hasLiDAR;
  final bool supportsSceneDepth;
  final bool supportsMesh;

  /// Pre-programmed hold distance (cm) the camera tier assumes when deriving
  /// real-world scale from the camera intrinsics.
  final double assumedDistanceCm;

  const DeviceCapabilities({
    required this.tier,
    required this.hasLiDAR,
    required this.supportsSceneDepth,
    required this.supportsMesh,
    required this.assumedDistanceCm,
  });

  /// Safe default used before native detection completes (assume non-Pro so
  /// the camera-tier guidance shows).
  factory DeviceCapabilities.unknown() => const DeviceCapabilities(
        tier: ScanTier.camera,
        hasLiDAR: false,
        supportsSceneDepth: false,
        supportsMesh: false,
        assumedDistanceCm: 30.0,
      );

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    return DeviceCapabilities(
      tier: ScanTier.fromRaw(json['tier'] as String? ?? 'camera'),
      hasLiDAR: json['hasLiDAR'] as bool? ?? false,
      supportsSceneDepth: json['supportsSceneDepth'] as bool? ?? false,
      supportsMesh: json['supportsMesh'] as bool? ?? false,
      assumedDistanceCm:
          (json['assumedDistanceCm'] as num?)?.toDouble() ?? 30.0,
    );
  }
}
