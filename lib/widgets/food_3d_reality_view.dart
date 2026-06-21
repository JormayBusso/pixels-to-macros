import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Embeds the native RealityKit premium food viewer (Step 3).
///
/// iOS 18+ renders with SwiftUI `RealityView`; iOS 17 falls back to a
/// RealityKit `ARView`. Both load the textured `.usdz` produced by the scan
/// pipeline and support touch rotate / pinch-zoom. Pass the local file path.
///
/// This is the viewer the upcoming Review & Edit (pre-log) screen embeds at the
/// top; it is intentionally separate from the existing [Scan3DViewer] SceneKit
/// widget used by scan history.
class Food3DRealityView extends StatelessWidget {
  const Food3DRealityView({super.key, required this.modelPath});

  final String? modelPath;

  static const String _viewType = 'com.pixelstomacros/food_3d_realityview';

  @override
  Widget build(BuildContext context) {
    final path = modelPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return const _ViewerPlaceholder(message: 'No 3D model available');
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        creationParams: <String, dynamic>{'modelPath': path},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    return const _ViewerPlaceholder(
      message: '3D viewer is only available on iOS',
    );
  }
}

class _ViewerPlaceholder extends StatelessWidget {
  const _ViewerPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF101010),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}
