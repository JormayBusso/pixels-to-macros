import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/models/mascot_type.dart';
import 'package:pixels_to_macros/providers/challenge_provider.dart';
import 'package:pixels_to_macros/providers/daily_intake_provider.dart';
import 'package:pixels_to_macros/providers/history_provider.dart';
import 'package:pixels_to_macros/providers/recommendations_provider.dart';
import 'package:pixels_to_macros/providers/streak_provider.dart';
import 'package:pixels_to_macros/providers/user_prefs_provider.dart';
import 'package:pixels_to_macros/screens/home_screen_v2.dart';
import 'package:pixels_to_macros/theme/app_theme.dart';
import 'package:pixels_to_macros/widgets/card_title_box.dart';
import 'package:pixels_to_macros/widgets/premium_theme_effects.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
}

ThemeData themeFor(AppVisualTheme visual) => ThemeData(
      cardTheme: CardThemeData(
        color: visual.cardColor,
        margin: EdgeInsets.zero,
      ),
      extensions: [
        AppColorTheme(seedColor: visual.primaryAccent, visual: visual),
      ],
    );

class _Prefs extends UserPrefsNotifier {
  @override
  Future<void> load() async {}
}

class _Intake extends DailyIntakeNotifier {
  @override
  Future<void> load() async {}
}

class _History extends HistoryNotifier {
  _History(super.ref);

  @override
  Future<void> load() async {}
}

class _Streak extends StreakNotifier {
  @override
  Future<void> load() async {}
}

class _Recommendations extends RecommendationsNotifier {
  _Recommendations() {
    state = const RecommendationsState(recs: [
      Recommendation(
        message: 'Test recommendation',
        icon: Icons.info,
        color: Colors.green,
      ),
    ]);
  }
}

class _Challenges extends WeeklyChallengeNotifier {
  _Challenges() {
    state = WeeklyChallengeState(activeChallenges: [Challenge.all.first]);
  }
}

void main() {
  test('Only the default seed gets stronger background and input tints', () {
    for (final seed in AppColorSeed.values.where((seed) => !seed.isPremium)) {
      final visual = AppVisualTheme.fromSeed(seed);
      final oldBackground =
          Color.alphaBlend(seed.color.withValues(alpha: 0.09), Colors.white);
      final oldInput =
          Color.alphaBlend(seed.color.withValues(alpha: 0.035), Colors.white);
      if (seed == AppColorSeed.green) {
        expect(visual.background.computeLuminance(),
            lessThan(oldBackground.computeLuminance()));
        expect(visual.inputFillColor.computeLuminance(),
            lessThan(oldInput.computeLuminance()));
        expect(contrast(Colors.white, visual.background), greaterThan(1.1));
      } else {
        expect(visual.background, oldBackground);
        expect(visual.inputFillColor, oldInput);
      }
      expect(visual.cardColor, Colors.white);
    }
  });

  for (final seed in AppColorSeed.values) {
    for (final brightness in Brightness.values) {
      final visual = AppVisualTheme.fromSeed(seed, brightness: brightness);
      testWidgets('${seed.name} $brightness has readable headers and surfaces',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: themeFor(visual),
          home: Builder(builder: (context) {
            for (final background in [
              visual.background,
              visual.cardColor,
              visual.inputFillColor,
            ]) {
              expect(contrast(context.appTextColor, background),
                  greaterThanOrEqualTo(4.5));
              expect(contrast(context.appMutedTextColor, background),
                  greaterThanOrEqualTo(4.5));
            }
            expect(
              contrast(CardTitleBox.foregroundOf(context),
                  CardTitleBox.fillOf(context)),
              greaterThanOrEqualTo(4.5),
            );
            final expectedTint = Color.alphaBlend(
              visual.primaryAccent.withValues(
                  alpha: visual.premium ? 0.32 : 0.35),
              visual.premium ? visual.surface : Colors.white,
            );
            expect(CardTitleBox.fillOf(context), expectedTint);
            return const SizedBox();
          }),
        ));
      });
    }
  }

  for (final seed in [
    AppColorSeed.green,
    ...AppColorSeed.values.where((seed) => seed.isPremium),
  ]) {
    for (final width in [240.0, 320.0, 600.0]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('${seed.name} full-width header at $width / $scale',
            (tester) async {
          const cardKey = ValueKey('card');
          const headerKey = ValueKey('header');
          const bodyKey = ValueKey('body');
          const actionKey = ValueKey('action');
          const title = 'Hydration and daily water goal';
          const radius = BorderRadius.all(Radius.circular(18));
          var taps = 0;
          await tester.pumpWidget(MaterialApp(
            theme: themeFor(AppVisualTheme.fromSeed(seed)),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: PremiumSurface(
                        key: cardKey,
                        borderRadius: radius,
                        header: CardTitleBox(
                          key: headerKey,
                          borderRadius: BorderRadius.zero,
                          icon: Icons.water_drop,
                          title: title,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < 3; i++)
                                IconButton(
                                  key: i == 0 ? actionKey : null,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => taps++,
                                  icon: const Icon(Icons.add, size: 20),
                                ),
                            ],
                          ),
                        ),
                        child: const SizedBox(key: bodyKey, height: 160),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
          expect(tester.takeException(), isNull);
          final card = tester.getRect(find.byKey(cardKey));
          final header = tester.getRect(find.byKey(headerKey));
          final body = tester.getRect(find.byKey(bodyKey));
          expect(header.left, card.left);
          expect(header.right, card.right);
          expect(header.top, card.top);
          expect(header.height, lessThan(card.height));
          expect(body.top, header.bottom + 16);
          expect(body.left, card.left + 16);
          expect(body.right, card.right - 16);
          final textRect = tester.getRect(find.text(title));
          expect(textRect.left, greaterThanOrEqualTo(header.left + 12));
          expect(textRect.right, lessThanOrEqualTo(header.right - 12));
          expect(textRect.bottom, lessThanOrEqualTo(header.bottom - 9));
          if (seed.isPremium) {
            final clip = tester.widget<ClipRRect>(find.descendant(
                of: find.byKey(cardKey), matching: find.byType(ClipRRect)));
            expect(clip.borderRadius, radius);
            expect(clip.clipBehavior, Clip.antiAlias);
          } else {
            final cardWidget = tester.widget<Card>(find.descendant(
                of: find.byKey(cardKey), matching: find.byType(Card)));
            expect(cardWidget.clipBehavior, Clip.antiAlias);
            expect((cardWidget.shape! as RoundedRectangleBorder).borderRadius,
                radius);
          }
          await tester.tap(find.byKey(actionKey));
          expect(taps, 1);
        });
      }
    }
  }

  testWidgets('A surface without a header keeps its existing padding and clip',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeFor(AppVisualTheme.fromSeed(AppColorSeed.green)),
      home: const PremiumSurface(
        padding: EdgeInsets.all(14),
        child: SizedBox(height: 40),
      ),
    ));
    expect(tester.widget<Card>(find.byType(Card)).clipBehavior, Clip.none);
    final padding = tester.widget<Padding>(find.descendant(
      of: find.byType(Card),
      matching: find.byWidgetPredicate((widget) =>
          widget is Padding && widget.padding == const EdgeInsets.all(14)),
    ));
    expect(padding.padding, const EdgeInsets.all(14));
  });

  for (final language in ['en', 'nl', 'es', 'de', 'pl']) {
    testWidgets('$language long titles wrap within a narrow enlarged band',
        (tester) async {
      final l10n = AppLocalizations(Locale(language));
      for (final title in [
        l10n.hydrationTitle,
        l10n.weeklyChallengesTitle,
        l10n.smartRecommendations,
        l10n.todaysFoods,
        l10n.scanHistory,
      ]) {
        await tester.pumpWidget(MaterialApp(
          theme: themeFor(AppVisualTheme.fromSeed(AppColorSeed.green)),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 240,
                  child: PremiumSurface(
                    header: CardTitleBox(
                      title: title,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: const SizedBox(height: 80),
                  ),
                ),
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(CardTitleBox));
        final text = tester.getRect(find.text(title));
        expect(header.height, text.height + 18);
        expect(text.right, lessThanOrEqualTo(header.right - 12));
      }
    });
  }

  testWidgets('All seven Home card titles are edge-to-edge clipped bands',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        userPrefsProvider.overrideWith((ref) => _Prefs()),
        dailyIntakeProvider.overrideWith((ref) => _Intake()),
        historyProvider.overrideWith((ref) => _History(ref)),
        streakProvider.overrideWith((ref) => _Streak()),
        recommendationsProvider.overrideWith((ref) => _Recommendations()),
        weeklyChallengeProvider.overrideWith((ref) => _Challenges()),
      ],
      child: MaterialApp(
        theme: themeFor(AppVisualTheme.fromSeed(AppColorSeed.green)),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: const HomeScreen(),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.byType(CardTitleBox), findsNWidgets(7));
    for (final element in find.byType(CardTitleBox).evaluate()) {
      final finder = find.byWidget(element.widget);
      final header = tester.getRect(finder);
      final card = tester.getRect(
          find.ancestor(of: finder, matching: find.byType(Card)).first);
      expect(header.left, card.left);
      expect(header.right, card.right);
      expect(header.top, card.top);
      expect((element.widget as CardTitleBox).borderRadius, BorderRadius.zero);
    }
    final selectionIcons = find.byIcon(Icons.check_circle_outline);
    await tester.tap(selectionIcons.first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    final selected = find.text('0 selected');
    expect(selected, findsOneWidget);
    final selectionCard = tester.getRect(
        find.ancestor(of: selected, matching: find.byType(Card)).first);
    final selectionBand = tester.getRect(find.ancestor(
      of: selected,
      matching: find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.padding ==
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9)),
    ));
    expect(selectionBand.left, selectionCard.left);
    expect(selectionBand.right, selectionCard.right);
    expect(selectionBand.top, selectionCard.top);
  });
}
