import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hidden container portion requires review without nutrition lookup',
      () async {
    var lookups = 0;
    final notifier = ScanResultNotifier(
      runInference: () async => throw PlatformException(
        code: 'CONTAINER_PORTION_REVIEW_REQUIRED',
        details: 'hidden_interior=unobserved volume_measured=false',
      ),
      lookupFood: (_) async {
        lookups++;
        return null;
      },
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan();
    expect(notifier.state.failureKind,
        ScanFailureKind.containerPortionReviewRequired);
    expect(notifier.state.foods, isEmpty);
    expect(notifier.state.error, isNotNull);
    expect(notifier.state.loading, isFalse);
    expect(lookups, 0);
  });

  test('SIDE_VIEW_REQUIRED maps to sideViewRequired', () {
    expect(
      ScanResultNotifier.classifyFailure(
          PlatformException(code: 'SIDE_VIEW_REQUIRED', message: 'no food')),
      ScanFailureKind.sideViewRequired,
    );
  });

  test('NO_FOOD_DETECTED still maps to noFood', () {
    expect(
      ScanResultNotifier.classifyFailure(
          PlatformException(code: 'NO_FOOD_DETECTED')),
      ScanFailureKind.noFood,
    );
  });

  test('strict side failure clears prior nutrition and never looks up food',
      () async {
    var attempts = 0;
    var lookups = 0;
    final notifier = ScanResultNotifier(
      runInference: () async {
        if (attempts++ == 0) {
          return [
            {
              'label': 'apple',
              'volume_cm3': 100.0,
              'volume_measured': true,
              'pixel_count': 5000,
              'confidence': 0.9,
            },
          ];
        }
        throw PlatformException(
          code: 'SIDE_VIEW_REQUIRED',
          details: 'food#1_missing_independent_side_silhouette',
        );
      },
      lookupFood: (_) async {
        lookups++;
        return null;
      },
    );
    addTearDown(notifier.dispose);
    await notifier.runVideoScan();
    expect(notifier.state.foods, hasLength(1));
    expect(lookups, 1);
    await notifier.runVideoScan();
    expect(notifier.state.failureKind, ScanFailureKind.sideViewRequired);
    expect(notifier.state.error, isNotNull);
    expect(notifier.state.loading, isFalse);
    expect(notifier.state.foods, isEmpty);
    expect(notifier.state.hasUnmeasuredFoods, isFalse);
    expect(notifier.state.totalCaloriesMin, 0);
    expect(notifier.state.totalCaloriesMax, 0);
    expect(lookups, 1);
  });
}
