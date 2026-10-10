import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// What voice logging needs from the user, derived from the real platform
/// authorization statuses every time (never cached).
enum VoiceAccess {
  /// Microphone and speech recognition are both authorized.
  granted,

  /// At least one permission was never asked; the system prompt can be shown.
  notDetermined,

  /// The user turned microphone access off (Settings can fix it).
  micDenied,

  /// Microphone access is blocked by Screen Time / a device profile.
  micRestricted,

  /// The user turned speech recognition off (Settings can fix it).
  speechDenied,

  /// Speech recognition is blocked by Screen Time / a device profile.
  speechRestricted,
}

typedef PermissionStatusCall = Future<PermissionStatus> Function();

/// Reads and requests the microphone + speech-recognition permissions that
/// voice logging needs. On iOS permission_handler maps
/// `AVAuthorizationStatus` / `SFSpeechRecognizerAuthorizationStatus` as:
/// notDetermined → denied, denied → permanentlyDenied, restricted →
/// restricted, authorized → granted.
class VoicePermissionService {
  VoicePermissionService({
    PermissionStatusCall? micStatus,
    PermissionStatusCall? speechStatus,
    PermissionStatusCall? requestMic,
    PermissionStatusCall? requestSpeech,
  })  : _micStatus = micStatus ?? (() => Permission.microphone.status),
        _speechStatus = speechStatus ?? (() => Permission.speech.status),
        _requestMic = requestMic ?? (() => Permission.microphone.request()),
        _requestSpeech =
            requestSpeech ?? (() => Permission.speech.request());

  final PermissionStatusCall _micStatus;
  final PermissionStatusCall _speechStatus;
  final PermissionStatusCall _requestMic;
  final PermissionStatusCall _requestSpeech;

  static VoiceAccess classify(PermissionStatus mic, PermissionStatus speech) {
    if (mic.isRestricted) return VoiceAccess.micRestricted;
    if (mic.isPermanentlyDenied) return VoiceAccess.micDenied;
    if (speech.isRestricted) return VoiceAccess.speechRestricted;
    if (speech.isPermanentlyDenied) return VoiceAccess.speechDenied;
    if (mic.isGranted && speech.isGranted) return VoiceAccess.granted;
    return VoiceAccess.notDetermined;
  }

  /// Current access without prompting the user.
  Future<VoiceAccess> check() async =>
      classify(await _micStatus(), await _speechStatus());

  /// Prompts only for permissions that are still requestable, microphone
  /// first, then speech recognition. Already-granted, denied or restricted
  /// permissions are never re-requested.
  Future<VoiceAccess> ensure() async {
    var mic = await _micStatus();
    var speech = await _speechStatus();
    if (classify(mic, speech) != VoiceAccess.notDetermined) {
      return classify(mic, speech);
    }
    if (mic.isDenied) mic = await _requestMic();
    if (mic.isGranted && speech.isDenied) speech = await _requestSpeech();
    final access = classify(mic, speech);
    // A request that still answers "denied" can no longer show a prompt;
    // treat it as off so the user is pointed to Settings instead of a loop.
    if (access == VoiceAccess.notDetermined) {
      return mic.isGranted ? VoiceAccess.speechDenied : VoiceAccess.micDenied;
    }
    return access;
  }
}

/// True when a recognizer error code is about authorization rather than
/// audio/recognition (Android `error_permission`, iOS kAFAssistant 1700
/// `error_speech_recognizer_request_not_authorized`). Such errors must be
/// confirmed against the real statuses before telling the user anything.
bool isSpeechAuthorizationError(String code) {
  final c = code.toLowerCase();
  return c.contains('permission') ||
      c.contains('denied') ||
      c.contains('not_authorized');
}

/// speech_to_text is an app-wide singleton that initializes once per app
/// session: later `initialize` calls return the cached result and silently
/// drop the new `onError`/`onStatus` callbacks, leaving them bound to the
/// first (possibly disposed) screen. This re-binds them on every screen.
class SpeechRecognizerBinding {
  SpeechRecognizerBinding(this.speech);

  static final _owners = Expando<Object>();

  final SpeechToText speech;
  Object? _generation;
  SpeechErrorListener? _onError;
  SpeechStatusListener? _onStatus;

  bool get isAvailable => speech.isAvailable;

  Future<bool> initialize({
    required SpeechErrorListener onError,
    required SpeechStatusListener onStatus,
  }) async {
    final generation = Object();
    _generation = generation;
    _owners[speech] = generation;
    _onError = onError;
    _onStatus = onStatus;
    speech.errorListener = onError;
    speech.statusListener = onStatus;
    final ok = await speech.initialize(onError: onError, onStatus: onStatus);
    if (identical(_owners[speech], generation)) {
      speech.errorListener = onError;
      speech.statusListener = onStatus;
    }
    return ok;
  }

  /// Unbinds this screen's callbacks unless another screen took them over.
  void detach() {
    if (_generation != null && identical(_owners[speech], _generation)) {
      _owners[speech] = null;
      if (_onError != null && speech.errorListener == _onError) {
        speech.errorListener = null;
      }
      if (_onStatus != null && speech.statusListener == _onStatus) {
        speech.statusListener = null;
      }
    }
    _generation = null;
    _onError = null;
    _onStatus = null;
  }
}
