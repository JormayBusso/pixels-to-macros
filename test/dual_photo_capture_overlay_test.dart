import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/core/scan_state.dart';
import 'package:pixels_to_macros/widgets/dual_photo_capture_overlay.dart';

void main() {
  testWidgets(
      'approximate mode has an accessible switch and only a top step in all languages',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final lang in ['en', 'nl', 'es', 'de', 'pl']) {
      bool? changed;
      await tester.pumpWidget(MaterialApp(
        locale: Locale(lang),
        supportedLocales: const [
          Locale('en'),
          Locale('nl'),
          Locale('es'),
          Locale('de'),
          Locale('pl'),
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: DualPhotoCaptureOverlay(
          scanState: ScanState.waitingForTopView,
          aligned: false,
          alignmentScore: 0,
          stability: 0,
          holdProgress: 0,
          capturing: false,
          scanMode: 'monocular_scale',
          extraAccuracy: false,
          onExtraAccuracyChanged: (value) => changed = value,
        ),
      ));
      await tester.pump();
      final context = tester.element(find.byType(DualPhotoCaptureOverlay));
      final l10n = AppLocalizations.of(context);
      expect(find.text(l10n.scanSideView), findsNothing);
      expect(find.text(l10n.approximateScanMode), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget is Semantics &&
              widget.properties.label == l10n.extraAccuracy),
          findsOneWidget);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('top and side alignment accepts six degrees, not beyond the boundary',
      () {
    for (final target in [-math.pi / 2, 0.0]) {
      for (final sign in [-1, 1]) {
        final insidePitch = target + sign * (math.pi / 30 - 1e-9);
        final outsidePitch = target + sign * (math.pi / 30 + 1e-9);
        expect(ScanCaptureAlignment.isAligned(insidePitch - target), isTrue);
        expect(ScanCaptureAlignment.isAligned(outsidePitch - target), isFalse);
      }
    }
    expect(ScanCaptureAlignment.isAligned(math.pi / 30), isTrue);
    expect(ScanCaptureAlignment.score(math.pi / 30), 1);
    expect(ScanCaptureAlignment.score(ScanCaptureAlignment.falloffRad), 0);
    expect(ScanCaptureAlignment.score(-1), 0);
    expect(ScanCaptureAlignment.isAligned(double.nan), isFalse);
    expect(ScanCaptureAlignment.score(double.infinity), 0);
  });

  test('aspect-fit ROI mapping remains centred and rails avoid both masks', () {
    for (final size in [const Size(568, 320), const Size(1194, 834)]) {
      for (final aspect in [4 / 3, 16 / 9, 1.0]) {
        const padding = EdgeInsets.fromLTRB(44, 0, 24, 21);
        final video = ScanGuideGeometry.videoRect(size, aspect);
        final radius = ScanGuideGeometry.radius(size, aspect);
        expect(radius, closeTo(video.shortestSide * 0.485, 1e-9));
        expect(video.center, size.center(Offset.zero));
        final rails = ScanGuideGeometry.rails(size, padding, aspect);
        for (final morph in [0.0, 0.5, 1.0]) {
          final roi = ScanGuideGeometry.guide(size, morph, aspect).outerRect;
          expect(rails.left.overlaps(roi), isFalse);
          expect(rails.right.overlaps(roi), isFalse);
        }
        expect(rails.left.left, greaterThanOrEqualTo(padding.left));
        expect(
            rails.right.right, lessThanOrEqualTo(size.width - padding.right));
        expect(
            rails.left.bottom, lessThanOrEqualTo(size.height - padding.bottom));
        expect(rails.right.width, greaterThan(44));
        expect(ScanGuideGeometry.rightRailCenterX(size, padding, aspect),
            rails.right.center.dx);
      }
    }
  });

  final cases = [
    (size: const Size(568, 320), scale: 1.0, lang: 'en', aspect: 4 / 3),
    (size: const Size(568, 320), scale: 2.0, lang: 'de', aspect: 16 / 9),
    (size: const Size(844, 390), scale: 1.0, lang: 'nl', aspect: 4 / 3),
    (size: const Size(844, 390), scale: 2.0, lang: 'es', aspect: 16 / 9),
    (size: const Size(1194, 834), scale: 2.0, lang: 'pl', aspect: 4 / 3),
  ];
  for (final sample in cases) {
    testWidgets('readable rails ${sample.size} ${sample.scale} ${sample.lang}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = sample.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const padding = EdgeInsets.fromLTRB(44, 0, 24, 21);
      for (final state in [
        ScanState.waitingForTopView,
        ScanState.moveSide,
        ScanState.captureSide,
      ]) {
        await tester.pumpWidget(MaterialApp(
          locale: Locale(sample.lang),
          supportedLocales: const [
            Locale('en'),
            Locale('nl'),
            Locale('es'),
            Locale('de'),
            Locale('pl'),
          ],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: MediaQuery(
            data: MediaQueryData(
              // Deliberately different: the rails must use layout constraints.
              size: sample.size * 2,
              padding: padding,
              textScaler: TextScaler.linear(sample.scale),
              disableAnimations: true,
            ),
            child: DualPhotoCaptureOverlay(
              scanState: state,
              aligned: false,
              alignmentScore: 0.9,
              stability: 0.1,
              holdProgress: 0,
              capturing: false,
              scanMode: 'monocular_scale',
              videoAspect: sample.aspect,
              tiltError: 0.2,
              lowLight: true,
              liveDetectionAvailable: true,
            ),
          ),
        ));
        await tester.pump();
        final rails =
            ScanGuideGeometry.rails(sample.size, padding, sample.aspect);
        for (final side in ['left', 'right']) {
          final finder = find.byKey(ValueKey('scan-$side-rail'));
          expect(tester.getRect(finder),
              side == 'left' ? rails.left : rails.right);
          await tester.drag(finder, const Offset(0, -600));
          await tester.pump();
        }
        expect(find.byType(FittedBox), findsNothing);
        expect(find.byType(Switch), findsOneWidget);
        expect(find.byIcon(Icons.camera_alt), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
