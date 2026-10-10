import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pixels_to_macros/services/voice_permission_service.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Fake platform statuses; on iOS permission_handler reports notDetermined as
/// `denied`, user-denied as `permanentlyDenied`, Screen Time as `restricted`.
class _FakePlatform {
  _FakePlatform(this.mic, this.speech, {this.micGrant, this.speechGrant});

  PermissionStatus mic;
  PermissionStatus speech;
  final PermissionStatus? micGrant;
  final PermissionStatus? speechGrant;
  int micRequests = 0;
  int speechRequests = 0;

  VoicePermissionService service() => VoicePermissionService(
        micStatus: () async => mic,
        speechStatus: () async => speech,
        requestMic: () async {
          micRequests++;
          return mic = micGrant ?? mic;
        },
        requestSpeech: () async {
          speechRequests++;
          return speech = speechGrant ?? speech;
        },
      );
}

const _granted = PermissionStatus.granted;
const _notDetermined = PermissionStatus.denied;
const _denied = PermissionStatus.permanentlyDenied;
const _restricted = PermissionStatus.restricted;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoicePermissionService.classify', () {
    test('both granted', () {
      expect(VoicePermissionService.classify(_granted, _granted),
          VoiceAccess.granted);
    });
    test('never asked stays requestable', () {
      expect(VoicePermissionService.classify(_notDetermined, _notDetermined),
          VoiceAccess.notDetermined);
      expect(VoicePermissionService.classify(_granted, _notDetermined),
          VoiceAccess.notDetermined);
    });
    test('microphone denial and restriction are distinct', () {
      expect(VoicePermissionService.classify(_denied, _granted),
          VoiceAccess.micDenied);
      expect(VoicePermissionService.classify(_restricted, _granted),
          VoiceAccess.micRestricted);
    });
    test('speech denial and restriction are distinct', () {
      expect(VoicePermissionService.classify(_granted, _denied),
          VoiceAccess.speechDenied);
      expect(VoicePermissionService.classify(_granted, _restricted),
          VoiceAccess.speechRestricted);
    });
  });

  group('VoicePermissionService.ensure', () {
    test('already granted never prompts, across repeated taps/re-entries',
        () async {
      final p = _FakePlatform(_granted, _granted);
      for (var i = 0; i < 5; i++) {
        expect(await p.service().ensure(), VoiceAccess.granted);
        expect(await p.service().check(), VoiceAccess.granted);
      }
      expect(p.micRequests, 0);
      expect(p.speechRequests, 0);
    });

    test('first use requests microphone then speech', () async {
      final p = _FakePlatform(_notDetermined, _notDetermined,
          micGrant: _granted, speechGrant: _granted);
      final service = p.service();
      expect(await service.ensure(), VoiceAccess.granted);
      expect(p.micRequests, 1);
      expect(p.speechRequests, 1);
      expect(await service.ensure(), VoiceAccess.granted);
      expect(p.micRequests, 1);
      expect(p.speechRequests, 1);
    });

    test('only the missing permission is requested', () async {
      final p =
          _FakePlatform(_granted, _notDetermined, speechGrant: _granted);
      expect(await p.service().ensure(), VoiceAccess.granted);
      expect(p.micRequests, 0);
      expect(p.speechRequests, 1);
    });

    test('declining the microphone prompt reports micDenied, skips speech',
        () async {
      final p = _FakePlatform(_notDetermined, _notDetermined, micGrant: _denied);
      expect(await p.service().ensure(), VoiceAccess.micDenied);
      expect(p.speechRequests, 0);
    });

    test('declining the speech prompt reports speechDenied', () async {
      final p = _FakePlatform(_notDetermined, _notDetermined,
          micGrant: _granted, speechGrant: _denied);
      expect(await p.service().ensure(), VoiceAccess.speechDenied);
    });

    test('denied and restricted are never re-requested', () async {
      for (final c in [
        (_denied, _granted, VoiceAccess.micDenied),
        (_restricted, _notDetermined, VoiceAccess.micRestricted),
        (_granted, _denied, VoiceAccess.speechDenied),
        (_granted, _restricted, VoiceAccess.speechRestricted),
      ]) {
        final p = _FakePlatform(c.$1, c.$2);
        expect(await p.service().ensure(), c.$3);
        expect(p.micRequests + p.speechRequests, 0);
      }
    });

    test('a request that cannot prompt does not loop as notDetermined',
        () async {
      final p = _FakePlatform(_notDetermined, _notDetermined);
      expect(await p.service().ensure(), VoiceAccess.micDenied);
    });

    test('check reflects a grant made in Settings (resume)', () async {
      final p = _FakePlatform(_denied, _granted);
      final service = p.service();
      expect(await service.check(), VoiceAccess.micDenied);
      p.mic = _granted;
      expect(await service.check(), VoiceAccess.granted);
      expect(p.micRequests, 0);
    });
  });

  test('isSpeechAuthorizationError', () {
    expect(isSpeechAuthorizationError('error_permission'), isTrue);
    expect(
        isSpeechAuthorizationError(
            'error_speech_recognizer_request_not_authorized'),
        isTrue);
    expect(isSpeechAuthorizationError('error_no_match'), isFalse);
    expect(isSpeechAuthorizationError('error_speech_recognizer_disabled'),
        isFalse);
  });

  group('SpeechRecognizerBinding (once-per-session initialize)', () {
    const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late int nativeInits;
    late bool nativeResult;

    setUp(() {
      nativeInits = 0;
      nativeResult = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') {
          nativeInits++;
          return nativeResult;
        }
        return null;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromNative(String method, Object args) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
    }

    test('re-entered screen receives callbacks; old screen does not',
        () async {
      final speech = SpeechToText.withMethodChannel();
      final firstErrors = <String>[];
      final secondErrors = <String>[];
      final secondStatuses = <String>[];

      final first = SpeechRecognizerBinding(speech);
      expect(
          await first.initialize(
              onError: (e) => firstErrors.add(e.errorMsg), onStatus: (_) {}),
          isTrue);
      first.detach();

      final second = SpeechRecognizerBinding(speech);
      expect(second.isAvailable, isTrue);
      expect(
          await second.initialize(
              onError: (SpeechRecognitionError e) =>
                  secondErrors.add(e.errorMsg),
              onStatus: secondStatuses.add),
          isTrue);
      expect(nativeInits, 1, reason: 'native initialize runs once');

      await fromNative('notifyError',
          jsonEncode({'errorMsg': 'error_no_match', 'permanent': false}));
      await fromNative('notifyStatus', 'notListening');
      expect(firstErrors, isEmpty);
      expect(secondErrors, ['error_no_match']);
      expect(secondStatuses, contains('notListening'));
    });

    test('detach does not clear listeners another screen bound later',
        () async {
      final speech = SpeechToText.withMethodChannel();
      final a = SpeechRecognizerBinding(speech);
      final b = SpeechRecognizerBinding(speech);
      await a.initialize(onError: (_) {}, onStatus: (_) {});
      await b.initialize(onError: (_) {}, onStatus: (_) {});
      a.detach();
      expect(speech.errorListener, isNotNull);
      expect(speech.statusListener, isNotNull);
      b.detach();
      expect(speech.errorListener, isNull);
      expect(speech.statusListener, isNull);
    });

    test('detach during pending initialization does not rebind callbacks',
        () async {
      final completion = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'initialize') return completion.future;
        return null;
      });
      final speech = SpeechToText.withMethodChannel();
      final binding = SpeechRecognizerBinding(speech);
      final errors = <String>[];
      final statuses = <String>[];
      final pending = binding.initialize(
          onError: (e) => errors.add(e.errorMsg), onStatus: statuses.add);
      await Future<void>.delayed(Duration.zero);
      binding.detach();
      completion.complete(true);
      expect(await pending, isTrue);
      expect(speech.errorListener, isNull);
      expect(speech.statusListener, isNull);
      await fromNative('notifyError',
          jsonEncode({'errorMsg': 'error_no_match', 'permanent': false}));
      await fromNative('notifyStatus', 'notListening');
      expect(errors, isEmpty);
      expect(statuses, isEmpty);
    });

    for (final oldCompletesFirst in [true, false]) {
      test('re-entry owns overlapping initialization callbacks '
          '(old completes first: $oldCompletesFirst)', () async {
        final completions = <Completer<bool>>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') {
            final completion = Completer<bool>();
            completions.add(completion);
            return completion.future;
          }
          return null;
        });
        final speech = SpeechToText.withMethodChannel();
        final first = SpeechRecognizerBinding(speech);
        final second = SpeechRecognizerBinding(speech);
        final firstErrors = <String>[];
        final firstStatuses = <String>[];
        final secondErrors = <String>[];
        final secondStatuses = <String>[];
        final firstPending = first.initialize(
            onError: (e) => firstErrors.add(e.errorMsg),
            onStatus: firstStatuses.add);
        await Future<void>.delayed(Duration.zero);
        first.detach();
        final secondPending = second.initialize(
            onError: (e) => secondErrors.add(e.errorMsg),
            onStatus: secondStatuses.add);
        await Future<void>.delayed(Duration.zero);
        expect(completions, hasLength(2));
        first.detach();

        Future<void> checkCurrentCallbacks() async {
          final errorCount = secondErrors.length;
          final statusCount = secondStatuses.length;
          await fromNative('notifyError',
              jsonEncode({'errorMsg': 'error_no_match', 'permanent': false}));
          await fromNative('notifyStatus', 'notListening');
          expect(firstErrors, isEmpty);
          expect(firstStatuses, isEmpty);
          expect(secondErrors.length, errorCount + 1);
          expect(secondStatuses.length, statusCount + 1);
        }

        await checkCurrentCallbacks();
        final firstIndex = oldCompletesFirst ? 0 : 1;
        completions[firstIndex].complete(true);
        expect(await (oldCompletesFirst ? firstPending : secondPending), isTrue);
        await checkCurrentCallbacks();
        completions[1 - firstIndex].complete(true);
        expect(await (oldCompletesFirst ? secondPending : firstPending), isTrue);
        await checkCurrentCallbacks();
        first.detach();
        await checkCurrentCallbacks();
        second.detach();
        expect(speech.errorListener, isNull);
        expect(speech.statusListener, isNull);
      });
    }

    test('detach respects ownership even when screens share callbacks',
        () async {
      final speech = SpeechToText.withMethodChannel();
      final first = SpeechRecognizerBinding(speech);
      final second = SpeechRecognizerBinding(speech);
      void onError(SpeechRecognitionError error) {}
      void onStatus(String status) {}
      await first.initialize(onError: onError, onStatus: onStatus);
      await second.initialize(onError: onError, onStatus: onStatus);
      first.detach();
      expect(speech.errorListener, same(onError));
      expect(speech.statusListener, same(onStatus));
      second.detach();
      expect(speech.errorListener, isNull);
      expect(speech.statusListener, isNull);
    });

    test('unavailable recognizer retries and is not cached as ready',
        () async {
      final speech = SpeechToText.withMethodChannel();
      nativeResult = false;
      final binding = SpeechRecognizerBinding(speech);
      expect(await binding.initialize(onError: (_) {}, onStatus: (_) {}),
          isFalse);
      expect(binding.isAvailable, isFalse);
      nativeResult = true;
      expect(await binding.initialize(onError: (_) {}, onStatus: (_) {}),
          isTrue);
      expect(nativeInits, 2);
    });
  });
}
