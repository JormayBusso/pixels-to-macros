import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One reconstructed food object passed from the native pipeline. Mirrors
/// `lastModel3DObjects` produced by `InferencePipeline` so the Flutter UI
/// and the SceneKit scene graph stay in sync via stable cluster `id`s.
@immutable
class Scan3DObject {
  const Scan3DObject({
    required this.id,
    required this.label,
    required this.volumeCm3,
    required this.voxelCount,
    required this.confidence,
  });

  factory Scan3DObject.fromMap(Map<String, dynamic> m) {
    return Scan3DObject(
      id: m['id'] as String? ?? '',
      label: m['label'] as String? ?? '',
      volumeCm3: (m['volume_cm3'] as num?)?.toDouble() ?? 0.0,
      voxelCount: (m['voxel_count'] as num?)?.toInt() ?? 0,
      confidence: (m['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Stable cluster id of the form `"<label>_<instanceIndex>"`.
  final String id;
  final String label;
  final double volumeCm3;
  final int voxelCount;
  final double confidence;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'label': label,
        'volume_cm3': volumeCm3,
        'voxel_count': voxelCount,
        'confidence': confidence,
      };
}

/// View modes mirror the native `ViewMode` enum in `Scan3DViewerPlugin`.
enum Scan3DViewMode { combined, isolated }

/// Imperative handle for driving an embedded [Scan3DViewer]. Provided to
/// [Scan3DViewer]'s `onControllerReady` callback so the parent screen can
/// push selection / mode changes into the SceneKit scene.
class Scan3DViewerController {
  Scan3DViewerController._(this._channel);

  final MethodChannel _channel;

  /// Select a food object by stable cluster id. Pass `null` to deselect.
  Future<void> select(String? id) async {
    await _channel.invokeMethod('selectObject', {'id': id});
  }

  /// Select + re-frame the camera on the given object.
  Future<void> focus(String id) async {
    await _channel.invokeMethod('focusObject', {'id': id});
  }

  Future<void> clearSelection() async {
    await _channel.invokeMethod('clearSelection');
  }

  Future<void> setViewMode(Scan3DViewMode mode) async {
    await _channel.invokeMethod('setViewMode', {'mode': mode.name});
  }

  /// Toggle per-object wireframe + floating volume labels for debugging.
  Future<void> setDebugOverlay({bool? wireframe, bool? labels}) async {
    await _channel.invokeMethod('setDebugOverlay', <String, Object?>{
      if (wireframe != null) 'wireframe': wireframe,
      if (labels != null) 'labels': labels,
    });
  }

  Future<void> resetCamera() async {
    await _channel.invokeMethod('resetCamera');
  }
}

/// Renders a USDZ / OBJ scan via the native SceneKit platform view on iOS.
/// On other platforms (or when no model path is provided) it shows a
/// neutral placeholder.
///
/// Stage 3: the widget now wires a per-view `MethodChannel` so callers can
/// drive selection / view mode / debug overlays and receive selection
/// callbacks from native taps.
class Scan3DViewer extends StatefulWidget {
  const Scan3DViewer({
    super.key,
    required this.modelPath,
    this.objects = const [],
    this.onControllerReady,
    this.onSelectionChanged,
    this.onObjectsReady,
    this.onError,
  });

  final String? modelPath;

  /// Metadata for each food object in the scene. Passed to the native
  /// viewer at construction time so floating labels can be rendered
  /// without an extra round-trip.
  final List<Scan3DObject> objects;

  final ValueChanged<Scan3DViewerController>? onControllerReady;

  /// Fired when the user taps an object in the scene (or empty space).
  final ValueChanged<String?>? onSelectionChanged;

  /// Fired once the native scene has indexed its food nodes — emits the
  /// list of cluster ids that were successfully bound. Lets callers
  /// reconcile their UI list with the actual scene graph.
  final ValueChanged<List<String>>? onObjectsReady;

  /// Fired when native SceneKit reports a hard viewer error such as
  /// `invalid_model` or scene/metadata desync.
  final ValueChanged<Map<String, dynamic>>? onError;

  static const String _viewType = 'com.pixelstomacros/scan_3d_viewer';

  @override
  State<Scan3DViewer> createState() => _Scan3DViewerState();
}

class _Scan3DViewerState extends State<Scan3DViewer> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    final path = widget.modelPath;
    debugPrint('3D MODEL PATH: $path');
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return const _Placeholder(
        message: 'No 3D model available for this scan.',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: Scan3DViewer._viewType,
        creationParams: <String, dynamic>{
          'modelPath': path,
          'objects': widget.objects.map((o) => o.toMap()).toList(),
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    }

    return const _Placeholder(
      message: '3D viewer is only available on iOS for now.',
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('com.pixelstomacros/scan_3d_viewer/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSelectionChanged':
          final id = (call.arguments as Map?)?['id'] as String?;
          widget.onSelectionChanged?.call(id);
          break;
        case 'onObjectsReady':
          final raw = (call.arguments as Map?)?['ids'] as List?;
          final ids = raw?.cast<String>() ?? const <String>[];
          widget.onObjectsReady?.call(ids);
          break;
        case 'onError':
          final raw = call.arguments as Map?;
          final error = raw == null
              ? <String, dynamic>{'error': 'unknown'}
              : raw.map((k, v) => MapEntry(k.toString(), v));
          debugPrint('[Scan3DViewer] native error: $error');
          widget.onError?.call(error);
          break;
      }
      return null;
    });
    widget.onControllerReady?.call(Scan3DViewerController._(channel));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101010),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
    );
  }
}
