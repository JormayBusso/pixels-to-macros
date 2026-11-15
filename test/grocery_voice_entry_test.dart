import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:pixels_to_macros/core/app_localizations.dart';
import 'package:pixels_to_macros/screens/grocery_voice_entry_screen.dart';
import 'package:pixels_to_macros/services/pantry_photo_service.dart';
import 'package:pixels_to_macros/services/voice_permission_service.dart';

class _DeniedPermissions extends VoicePermissionService {
  int requests = 0;

  @override
  Future<VoiceAccess> ensure() async {
    requests++;
    return VoiceAccess.micDenied;
  }
}

class _GrantedPermissions extends VoicePermissionService {
  @override
  Future<VoiceAccess> ensure() async => VoiceAccess.granted;
}

class _Speech extends Fake implements SpeechToText {
  @override
  SpeechErrorListener? errorListener;
  @override
  SpeechStatusListener? statusListener;
  SpeechResultListener? onResult;
  SpeechListenOptions? options;
  String? locale;
  int cancellations = 0;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    dynamic debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async =>
      true;

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    dynamic cancelOnError = false,
    dynamic partialResults = true,
    dynamic onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    dynamic sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    this.onResult = onResult;
    options = listenOptions;
    locale = localeId;
  }

  @override
  Future<void> stop() async => statusListener?.call('notListening');

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  void emit(String words, {bool finalResult = false}) {
    onResult?.call(SpeechRecognitionResult(
        [SpeechRecognitionWords(words, null, 0.9)], finalResult));
  }
}

Future<void> _open(
  WidgetTester tester, {
  VoicePermissionService? permissions,
  SpeechToText? speech,
  required void Function(List<PantryPhotoCandidate>?) onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            onResult(await Navigator.push<List<PantryPhotoCandidate>>(
              context,
              MaterialPageRoute(
                builder: (_) => GroceryVoiceEntryScreen(
                    permissions: permissions, speech: speech),
              ),
            ));
          },
          child: const Text('Open'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'speech batches append once and text correction rejects late results',
      (tester) async {
    final speech = _Speech();
    List<PantryPhotoCandidate>? result;
    await _open(tester,
        permissions: _GrantedPermissions(),
        speech: speech,
        onResult: (items) => result = items);
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    expect(speech.options!.onDevice, isTrue);
    expect(speech.locale, 'en_US');
    speech.emit('two apples');
    speech.emit('two apples', finalResult: true);
    await tester.pump();
    await tester.tap(find.text('Stop listening'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    speech.emit('one litre of milk', finalResult: true);
    await tester.pump();
    await tester.tap(find.text('Stop listening'));
    await tester.pumpAndSettle();
    expect(find.text('two apples, one litre of milk'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField), 'three apples, one litre of milk');
    speech.emit('wrong late result', finalResult: true);
    await tester.pump();
    expect(find.text('three apples, one litre of milk'), findsOneWidget);
    await tester.tap(find.text('Review purchases'));
    await tester.pumpAndSettle();
    expect(result!.first.quantity, 3);
    expect(result, hasLength(2));
    expect(speech.cancellations, greaterThan(0));
  });

  testWidgets('backgrounding cancels microphone and ignores late speech',
      (tester) async {
    final speech = _Speech();
    await _open(tester,
        permissions: _GrantedPermissions(), speech: speech, onResult: (_) {});
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    speech.emit('two apples');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    speech.emit('five apples', finalResult: true);
    await tester.pump();
    expect(find.text('two apples'), findsOneWidget);
    expect(speech.cancellations, greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets(
      'editable purchase text returns counts and volume for review only',
      (tester) async {
    List<PantryPhotoCandidate>? result;
    await _open(tester, onResult: (items) => result = items);
    await tester.enterText(
        find.byType(TextField), 'two apples and one litre of milk');
    await tester.pump();
    await tester.tap(find.text('Review purchases'));
    await tester.pumpAndSettle();
    expect(result, hasLength(2));
    expect(result!.first.quantity, 2);
    final milk =
        result!.firstWhere((item) => item.name.toLowerCase() == 'milk');
    expect(milk.quantity * (milk.unit == 'l' ? 1000 : 1), 1000);
    expect(milk.unit, anyOf('l', 'ml'));
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('voice permissions are requested only on tap; denial keeps text',
      (tester) async {
    final permissions = _DeniedPermissions();
    List<PantryPhotoCandidate>? result;
    await _open(tester,
        permissions: permissions, onResult: (items) => result = items);
    expect(permissions.requests, 0);
    await tester.enterText(find.byType(TextField), 'three bananas');
    await tester.tap(find.text('Start speaking'));
    await tester.pumpAndSettle();
    expect(permissions.requests, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('three bananas'), findsOneWidget);
    await tester.tap(find.text('Review purchases'));
    await tester.pumpAndSettle();
    expect(result!.single.quantity, 3);
  });

  testWidgets('unrecognized text and cancellation never return purchases',
      (tester) async {
    List<PantryPhotoCandidate>? result;
    var returned = false;
    await _open(tester, onResult: (items) {
      result = items;
      returned = true;
    });
    await tester.enterText(find.byType(TextField), 'detergent and toothpaste');
    await tester.pump();
    await tester.tap(find.text('Review purchases'));
    await tester.pumpAndSettle();
    expect(returned, isFalse);
    expect(find.textContaining('No food or drink recognized'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
  });
}
