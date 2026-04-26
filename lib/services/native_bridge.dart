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
  /// Returns the session generation number (for generation-aware stop).
  Future<int> startSession() async {
    // startSession now returns the generation number directly,
    // avoiding a second round-trip for getSessionGeneration.
    final gen = await _channel.invokeMethod<int>('startSession');
    return gen ?? 0;
  }

  /// Stop the AR session and release native resources.
  /// If [generation] is provided, only stops if it matches the current
  /// generation — prevents a stale stop from killing a newer session.
  Future<void> stopSession({int? generation}) async {
    await _channel.invokeMethod<void>('stopSession', 
        generation != null ? {'generation': generation} : null);
  }

  /// Get the last session error message, or null if no error.
  Future<String?> getSessionError() async {
    try {
      return await _channel.invokeMethod<String>('getSessionError');
    } catch (_) {
      return null;
    }
  }

  /// Upgrade the running ARKit session to include depth/mesh features.
  /// Safe to call repeatedly; no-op if no session is active.
  Future<void> upgradeDepthConfig() async {
    try {
      await _channel.invokeMethod<void>('upgradeDepthConfig');
    } catch (_) {}
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

  // ── Video recording ──────────────────────────────────────────────────────

  /// Start sampling ARKit frames (~10 fps) for a video-sweep scan.
  Future<void> startRecording() async {
    await _channel.invokeMethod<void>('startRecording');
  }

  /// Stop frame sampling. Must be followed by [runVideoInference].
  Future<void> stopRecording() async {
    await _channel.invokeMethod<void>('stopRecording');
  }

  /// Run multi-frame 3-D reconstruction + segmentation on the recorded sweep.
  /// Returns the same JSON list format as [runInference].
  Future<List<Map<String, dynamic>>> runVideoInference() async {
    final raw = await _channel.invokeMethod<String>('runVideoInference');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.cast<Map<String, dynamic>>();
  }

  // ── Point cloud (Part 15) ────────────────────────────────────────────────

  /// Get current phone pitch angle in radians from ARKit.
  /// Returns -π/2 for straight-down (top-view), 0 for horizontal (side-view).
  Future<double> getPhonePitch() async {
    try {
      final result = await _channel.invokeMethod<double>('getPhonePitch');
      return result ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  /// Export the current scan's depth data as a PLY point cloud string.
  /// Must be called while the AR session is still active (before stopSession).
  /// Returns the PLY file content, or null if depth data is unavailable.
  Future<String?> exportPointCloud() async {
    try {
      return await _channel.invokeMethod<String>('exportPointCloud');
    } catch (_) {
      return null;
    }
  }

  // ── Memory usage (Part 17) ───────────────────────────────────────────────

  /// Get current resident memory usage in bytes from the native side.
  Future<int> getMemoryUsage() async {
    try {
      final result = await _channel.invokeMethod<int>('getMemoryUsage');
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ── Flashlight + ambient light (Phase 1: scan UX) ─────────────────────────

  /// Toggle the device flashlight (torch). Returns true on success.
  Future<bool> setTorch(bool on) async {
    try {
      final ok = await _channel.invokeMethod<bool>('setTorch', {'on': on});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the current ambient light intensity in lux from ARKit.
  /// Roughly: > 600 = bright, 200-600 = normal, < 200 = dark.
  /// Returns -1 if no estimate is available yet.
  Future<double> getAmbientIntensity() async {
    try {
      final v = await _channel.invokeMethod<double>('getAmbientIntensity');
      return v ?? -1.0;
    } catch (_) {
      return -1.0;
    }
  }
}
