import 'package:flutter/material.dart';

/// Hosts the native SceneKit 3-D food-model view (a rotatable reconstruction
/// of the most recently scanned food, built from the same height-field data
/// used to compute its volume).
///
/// The user can pinch to zoom and drag to rotate. Available on iOS only;
/// renders a neutral placeholder on other platforms.
class Food3DView extends StatelessWidget {
  const Food3DView({super.key, this.height = 260});

  final double height;

  static const _viewType = 'com.pixelstomacros/food_model';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Theme.of(context).platform == TargetPlatform.iOS
            ? const UiKitView(viewType: _viewType)
            : Container(
                color: const Color(0xFF121212),
                alignment: Alignment.center,
                child: const Text(
                  '3-D model available on device',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
      ),
    );
  }
}
