import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/models/scan_diagnostics.dart';

/// Representative native payload for a healthy monocular reconstruction that
/// used BOTH the top and side silhouettes (the target outcome of the P1 fix).
Map<String, dynamic> _monocularBothViews() => {
      'id': 'tomato_0',
      'label': 'tomato',
      'detected_category': 'tomato',
      'volume_cm3': 96.4,
      'raw_volume_cm3': 102.1,
      'voxel_count': 4120,
      'pixel_count': 38200,
      'confidence': 0.91,
      'silhouette_height_px': 78.5,
      'pixels_per_cm': 15.2,
      'density_source': 'label_prior',
      'frames_used': 2,
      'scan_mode': 'monocular_visual_hull',
      'scale_source': 'plate_diameter',
      'estimated': true,
      'footprint_area_cm2': 33.6,
      'height_cm': 5.2,
      'density_g_cm3': 0.95,
      'weight_g': 92.0,
      'volume_guardrail_applied': false,
      'side_view_applied': true,
      'fallback_used': false,
      'mesh_roundness_applied': true,
      'debug': 'visual_hull: side=hard scale=plate_diameter 15.2px/cm h=5.2cm '
          'fill=0.71 vol=96.4cm³',
    };

/// A reconstruction where the side silhouette was rejected and the estimator
/// fell back to a prior, with the soft volume guardrail engaged.
Map<String, dynamic> _monocularFallbackGuardrail() => {
      'id': 'rice_0',
      'label': 'rice',
      'volume_cm3': 410.0,
      'raw_volume_cm3': 980.0,
      'confidence': 0.62,
      'pixels_per_cm': 11.1,
      'scan_mode': 'monocular_scale',
      'scale_source': 'fallback_22cm',
      'estimated': true,
      'footprint_area_cm2': 120.4,
      'height_cm': 6.0,
      'weight_g': 320.0,
      'density_g_cm3': 0.78,
      'volume_guardrail_applied': true,
      'guardrail_upper_cm3': 420.0,
      'side_view_applied': false,
      'fallback_used': true,
    };

Map<String, dynamic> _lidar() => {
      'id': 'banana_0',
      'label': 'banana',
      'volume_cm3': 118.0,
      'voxel_count': 5200,
      'confidence': 0.88,
      'scan_mode': 'lidar_mesh',
      'estimated': false,
    };

void main() {
  group('FoodDiagnostic.fromMap', () {
    test('parses a full monocular both-views payload', () {
      final f = FoodDiagnostic.fromMap(_monocularBothViews());
      expect(f.label, 'tomato');
      expect(f.scanMode, 'monocular_visual_hull');
      expect(f.scaleSource, 'plate_diameter');
      expect(f.volumeCm3, 96.4);
      expect(f.rawVolumeCm3, 102.1);
      expect(f.footprintAreaCm2, 33.6);
      expect(f.heightCm, 5.2);
      expect(f.weightG, 92.0);
      expect(f.densityGCm3, 0.95);
      expect(f.pixelsPerCm, 15.2);
      expect(f.confidence, 0.91);
      expect(f.sideViewApplied, true);
      expect(f.fallbackUsed, false);
      expect(f.guardrailApplied, false);
      expect(f.debug, isNotNull);
    });

    test('usedBothViews is true only when side applied and no fallback', () {
      expect(FoodDiagnostic.fromMap(_monocularBothViews()).usedBothViews, true);
      expect(
          FoodDiagnostic.fromMap(_monocularFallbackGuardrail()).usedBothViews,
          false);
      // LiDAR omits side/fallback keys -> not "both views" in the monocular sense.
      expect(FoodDiagnostic.fromMap(_lidar()).usedBothViews, false);
    });

    test('captures guardrail engagement and upper bound', () {
      final f = FoodDiagnostic.fromMap(_monocularFallbackGuardrail());
      expect(f.guardrailApplied, true);
      expect(f.guardrailUpperCm3, 420.0);
      expect(f.fallbackUsed, true);
      expect(f.scaleSource, 'fallback_22cm');
    });

    test('tolerates missing optional keys without throwing', () {
      final f = FoodDiagnostic.fromMap({'label': 'x', 'scan_mode': 'm'});
      expect(f.volumeCm3, 0);
      expect(f.weightG, isNull);
      expect(f.sideViewApplied, isNull);
      expect(f.usedBothViews, false);
    });

    test('coerces int-typed volume to double', () {
      final f = FoodDiagnostic.fromMap({
        'label': 'x',
        'scan_mode': 'm',
        'volume_cm3': 100, // int from the platform channel
      });
      expect(f.volumeCm3, 100.0);
    });
  });

  group('ScanDiagnostics', () {
    test('fromCapture maps timings and foods', () {
      final d = ScanDiagnostics.fromCapture(
        depthMode: 'monocular_scale',
        nativeObjects: [_monocularBothViews(), _monocularFallbackGuardrail()],
        timings: {
          'record': const Duration(milliseconds: 1200),
          'inference': const Duration(milliseconds: 850),
        },
        peakMemoryBytes: 256 * 1048576,
        ambientLux: 480,
        stability: 0.92,
      );
      expect(d.depthMode, 'monocular_scale');
      expect(d.recordMs, 1200);
      expect(d.inferenceMs, 850);
      expect(d.foods, hasLength(2));
      expect(d.ambientLux, 480);
      expect(d.stability, 0.92);
    });

    test('toReport surfaces key validation signals', () {
      final d = ScanDiagnostics.fromCapture(
        depthMode: 'monocular_scale',
        nativeObjects: [_monocularBothViews(), _monocularFallbackGuardrail()],
        timings: {
          'record': const Duration(milliseconds: 1000),
          'inference': const Duration(milliseconds: 700),
        },
      );
      final report = d.toReport();
      expect(report, contains('depth mode:  monocular_scale'));
      expect(report, contains('tomato'));
      expect(report, contains('monocular_visual_hull'));
      expect(report, contains('plate_diameter'));
      expect(report, contains('bothViews=true'));
      expect(report, contains('guardrail: softened'));
      expect(report, contains('fallback_22cm'));
    });
  });
}
