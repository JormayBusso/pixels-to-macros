import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/providers/scan_result_provider.dart';

void main() {
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
}
