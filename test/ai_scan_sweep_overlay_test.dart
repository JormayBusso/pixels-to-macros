import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/widgets/ai_scan_sweep_overlay.dart';
import 'package:pixels_to_macros/widgets/dual_photo_capture_overlay.dart';

void main() {
  const palette = ScanChromePalette(
    premium: true,
    accent: Colors.green,
    secondary: Colors.blue,
    gradient: [Colors.green, Colors.blue],
  );
  final guide = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, 40, 40),
    const Radius.circular(4),
  );
  final mask = ui.Path()
    ..fillType = ui.PathFillType.evenOdd
    ..addRect(const Rect.fromLTWH(5, 5, 20, 20))
    ..addRect(const Rect.fromLTWH(10, 10, 5, 5))
    ..addRect(const Rect.fromLTWH(30, 30, 3, 3));
  final paint = find.descendant(
    of: find.byType(AiScanSweepOverlay),
    matching: find.byType(CustomPaint),
  );

  Widget overlay(
          {ui.Path? support, bool active = true, bool reduced = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: SizedBox(
            width: 40,
            height: 40,
            child: AiScanSweepOverlay(
              guide: guide,
              palette: palette,
              foodMask: support,
              active: active,
            ),
          ),
        ),
      );

  testWidgets('no guide-wide paint or ticker without current food support',
      (tester) async {
    await tester.pumpWidget(overlay());
    expect(paint, findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(overlay(support: mask));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(overlay());
    expect(paint, findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(overlay(support: mask, active: false));
    expect(paint, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final reduced in [false, true]) {
    testWidgets('fill keeps holes and components, reduced motion=$reduced',
        (tester) async {
      await tester.pumpWidget(overlay(support: mask, reduced: reduced));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.hasRunningAnimations, !reduced);
      final painter = tester.widget<CustomPaint>(paint).painter!;
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(40, 40));
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(40, 40)))!;
      final bytes = (await tester.runAsync(() => image.toByteData()))!;
      int alpha(int x, int y) => bytes.getUint8((y * 40 + x) * 4 + 3);
      expect(alpha(1, 1), 0);
      expect(alpha(12, 12), 0);
      expect(alpha(7, 7), inInclusiveRange(1, 100));
      expect(alpha(31, 31), inInclusiveRange(1, 100));
      expect(alpha(29, 31), 0);
      image.dispose();
      picture.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
