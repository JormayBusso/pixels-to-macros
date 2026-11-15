import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_localizations.dart';
import '../services/grocery_voice_parser.dart';
import '../services/voice_permission_service.dart';
import '../theme/app_theme.dart';

class GroceryVoiceEntryScreen extends StatefulWidget {
  const GroceryVoiceEntryScreen({super.key, this.permissions, this.speech});

  final VoicePermissionService? permissions;
  final SpeechToText? speech;

  @override
  State<GroceryVoiceEntryScreen> createState() =>
      _GroceryVoiceEntryScreenState();
}

class _GroceryVoiceEntryScreenState extends State<GroceryVoiceEntryScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  late final _speech = widget.speech ?? SpeechToText();
  late final _binding = SpeechRecognizerBinding(_speech);
  late final _permissions = widget.permissions ?? VoicePermissionService();
  bool _starting = false;
  bool _listening = false;
  bool _acceptResults = false;
  bool _foreground = true;
  String _prefix = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      _acceptResults = false;
      unawaited(_speech.cancel());
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _acceptResults = false;
    _binding.detach();
    unawaited(_speech.cancel());
    _text.dispose();
    super.dispose();
  }

  Future<void> _showAccess(VoiceAccess access) async {
    final l10n = AppLocalizations.of(context);
    final restricted = access == VoiceAccess.micRestricted ||
        access == VoiceAccess.speechRestricted;
    final speechDenied = access == VoiceAccess.speechDenied;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(restricted
            ? l10n.voiceRestrictedTitle
            : speechDenied
                ? l10n.voiceSpeechPermissionTitle
                : l10n.voiceMicPermissionTitle),
        content: Text(restricted
            ? l10n.voiceRestrictedBody
            : speechDenied
                ? l10n.voiceSpeechDeniedBody
                : l10n.voiceMicDeniedBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          if (!restricted)
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await openAppSettings();
              },
              child: Text(l10n.openSettings),
            ),
        ],
      ),
    );
  }

  void _onError(SpeechRecognitionError error) {
    if (!mounted || !_acceptResults) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _listening = false;
      _error = error.errorMsg.toLowerCase().contains('network')
          ? l10n.voiceErrNetwork
          : l10n.voiceErrGeneric;
    });
    if (isSpeechAuthorizationError(error.errorMsg)) {
      unawaited(_checkAccess());
    }
  }

  Future<void> _checkAccess() async {
    final access = await _permissions.check();
    if (!mounted) return;
    if (access != VoiceAccess.granted) await _showAccess(access);
  }

  Future<void> _start() async {
    if (_starting || _listening) return;
    setState(() => _starting = true);
    try {
      final access = await _permissions.ensure();
      if (!mounted || !_foreground) return;
      if (access != VoiceAccess.granted) {
        await _showAccess(access);
        return;
      }
      final available = await _binding.initialize(
        onError: _onError,
        onStatus: (status) {
          if (mounted && (status == 'done' || status == 'notListening')) {
            setState(() => _listening = false);
          }
        },
      );
      if (!mounted || !_foreground) return;
      final l10n = AppLocalizations.of(context);
      if (!available) {
        setState(() => _error = l10n.voiceEnableDictation);
        return;
      }
      const locales = {
        'en': 'en_US',
        'nl': 'nl_NL',
        'es': 'es_ES',
        'de': 'de_DE',
        'pl': 'pl_PL',
      };
      _prefix = _text.text.trim();
      _acceptResults = true;
      setState(() {
        _error = null;
        _listening = true;
      });
      await _speech.listen(
        localeId: locales[l10n.locale.languageCode] ?? 'en_US',
        listenFor: const Duration(seconds: 60),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          onDevice: true,
        ),
        onResult: (result) {
          if (!mounted || !_acceptResults) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          _text.value = TextEditingValue(
            text: _prefix.isEmpty ? words : '$_prefix, $words',
            selection: TextSelection.collapsed(
                offset: (_prefix.isEmpty ? words : '$_prefix, $words').length),
          );
          setState(() {});
        },
      );
    } catch (error) {
      debugPrint('[GROCERY_VOICE] recognizer failed: $error');
      if (mounted) {
        setState(() {
          _listening = false;
          _error = AppLocalizations.of(context).voiceErrGeneric;
        });
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    try {
      await _speech.stop();
    } catch (error) {
      debugPrint('[GROCERY_VOICE] stop failed: $error');
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).voiceErrGeneric);
      }
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  void _review() {
    _acceptResults = false;
    final l10n = AppLocalizations.of(context);
    final candidates =
        GroceryVoiceParser.parse(_text.text, l10n.locale.languageCode);
    if (candidates.isEmpty) {
      setState(() => _error = l10n.groceryVoiceNoProducts);
      return;
    }
    Navigator.pop(context, candidates);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.grocerySpeakPurchases)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l10n.groceryVoiceHint,
                style: TextStyle(color: context.appMutedTextColor)),
            const SizedBox(height: 20),
            TextField(
              controller: _text,
              enabled: !_starting && !_listening,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: l10n.groceryPurchaseText,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                _acceptResults = false;
                setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            if (_listening) Text(l10n.listening),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            OutlinedButton.icon(
              onPressed: _starting ? null : (_listening ? _stop : _start),
              icon: Icon(_listening ? Icons.stop : Icons.mic_none_outlined),
              label: Text(
                  _listening ? l10n.groceryVoiceStop : l10n.groceryVoiceStart),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _starting || _listening || _text.text.trim().isEmpty
                  ? null
                  : _review,
              child: Text(l10n.groceryVoiceReview),
            ),
          ],
        ),
      ),
    );
  }
}
