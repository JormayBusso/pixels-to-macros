import 'dart:convert';
import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Thin wrapper around [MethodChannel] for communicating with the
/// native Swift scanner pipeline.
///
/// All heavy processing (ARKit, CoreML, depth, volume) runs in Swift.
/// Flutter only sends commands and receives JSON results.
class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  final _channel = const MethodChannel(AppConstants.methodChannelName);

  // ── Device capabilities (Part 2) ─────────────────────────────────────────

  /// Ask native side which depth mode is available.
  /// Returns one of: "lidar", "camera_depth", "plate_fallback".
  Future<String> getDepthMode() async {
    final result = await _channel.invokeMethod<String>('getDepthMode');
    return result ?? 'plate_fallback';
  }

  // ── Scanning lifecycle ───────────────────────────────────────────────────

  /// Start the ARKit session on the native side.
  Future<void> startSession() async {
    await _channel.invokeMethod<void>('startSession');
  }

  /// Capture the current camera frame (top or side).
  /// [frameType] is "top" or "side".
  Future<Map<String, dynamic>> captureFrame(String frameType) async {
    final raw = await _channel.invokeMethod<String>(
      'captureFrame',
      {'type': frameType},
    );
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// Run full pipeline: segmentation → depth → volume → calories.
  /// Returns JSON list of detected foods with volumes.
  Future<List<Map<String, dynamic>>> runInference() async {
    final raw = await _channel.invokeMethod<String>('runInference');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Stop the AR session and release native resources.
  Future<void> stopSession() async {
    await _channel.invokeMethod<void>('stopSession');
  }
}
