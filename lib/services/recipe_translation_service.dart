import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import '../providers/locale_provider.dart';
import 'database_service.dart';
import 'recipe_translation_glossary.dart';

/// Availability of an Apple on-device translation language pair.
enum TranslationPackStatus { installed, supported, unsupported, unavailable }

/// Thin wrapper over the native `com.pixelstomacros/translation` channel
/// (Apple Translation framework, iOS 18+).
class AppleTranslationBridge {
  const AppleTranslationBridge();

  static const MethodChannel _channel =
      MethodChannel('com.pixelstomacros/translation');

  bool get isSupportedPlatform => !kIsWeb && Platform.isIOS;

  Future<TranslationPackStatus> status(String from, String to) async {
    if (!isSupportedPlatform) return TranslationPackStatus.unavailable;
    try {
      final raw = await _channel
          .invokeMethod<String>('status', {'from': from, 'to': to});
      return switch (raw) {
        'installed' => TranslationPackStatus.installed,
        'supported' => TranslationPackStatus.supported,
        'unsupported' => TranslationPackStatus.unsupported,
        _ => TranslationPackStatus.unavailable,
      };
    } catch (e) {
      debugPrint('[RecipeTranslation] status failed: $e');
      return TranslationPackStatus.unavailable;
    }
  }

  /// Shows Apple's language-download prompt when the pair is not installed.
  Future<bool> prepare(String from, String to) async {
    if (!isSupportedPlatform) return false;
    try {
      return await _channel
              .invokeMethod<bool>('prepare', {'from': from, 'to': to}) ??
          false;
    } catch (e) {
      debugPrint('[RecipeTranslation] prepare failed: $e');
      return false;
    }
  }

  Future<List<String>?> translateBatch(
    String from,
    String to,
    List<String> strings,
  ) async {
    if (!isSupportedPlatform || strings.isEmpty) return null;
    try {
      final raw = await _channel.invokeListMethod<String>(
        'translateBatch',
        {'from': from, 'to': to, 'strings': strings},
      );
      if (raw == null || raw.length != strings.length) return null;
      return raw;
    } catch (e) {
      debugPrint('[RecipeTranslation] translateBatch failed: $e');
      return null;
    }
  }
}

/// Translated text for one recipe in the current app language. Any field may
/// be null while it is still being translated (the original is shown).
@immutable
class RecipeTranslation {
  const RecipeTranslation({this.name, this.ingredients, this.steps});

  final String? name;
  final List<RecipeIngredient>? ingredients;
  final List<String>? steps;

  RecipeTranslation copyWith({
    String? name,
    List<RecipeIngredient>? ingredients,
    List<String>? steps,
  }) =>
      RecipeTranslation(
        name: name ?? this.name,
        ingredients: ingredients ?? this.ingredients,
        steps: steps ?? this.steps,
      );
}

@immutable
class RecipeTranslationState {
  const RecipeTranslationState({
    required this.lang,
    this.byId = const {},
    this.translatingDetails = const {},
  });

  final String lang;
  final Map<String, RecipeTranslation> byId;
  final Set<String> translatingDetails;

  RecipeTranslationState copyWith({
    Map<String, RecipeTranslation>? byId,
    Set<String>? translatingDetails,
  }) =>
      RecipeTranslationState(
        lang: lang,
        byId: byId ?? this.byId,
        translatingDetails: translatingDetails ?? this.translatingDetails,
      );
}

/// Language pairs for which Apple's download prompt was already requested in
/// this app session (so the user is asked at most once per pair per session).
final Set<String> _preparedPairsThisSession = <String>{};

/// Translates recipe names (lazily, in batches, for visible cards) and recipe
/// details (on open) into the app language with Apple's on-device Translation
/// framework, caching results in SQLite. On any failure the original text is
/// kept silently.
class RecipeTranslationNotifier extends StateNotifier<RecipeTranslationState> {
  RecipeTranslationNotifier(
    String lang, {
    AppleTranslationBridge bridge = const AppleTranslationBridge(),
  })  : _bridge = bridge,
        super(RecipeTranslationState(lang: lang));

  final AppleTranslationBridge _bridge;

  static const int _nameBatchSize = 40;

  final Map<String, Recipe> _pendingNames = <String, Recipe>{};
  final Set<String> _requestedNames = <String>{};
  final Set<String> _requestedDetails = <String>{};
  final Map<String, TranslationPackStatus> _pairStatus = {};
  Timer? _debounce;
  Future<void> _queue = Future<void>.value();

  String get lang => state.lang;

  bool _needsTranslation(Recipe recipe) =>
      _bridge.isSupportedPlatform &&
      recipe.language.isNotEmpty &&
      recipe.language != lang &&
      !recipe.id.startsWith('custom:');

  /// Queue a recipe-name translation (called when a card becomes visible).
  void requestName(Recipe recipe) {
    if (!_needsTranslation(recipe)) return;
    if (!_requestedNames.add(recipe.id)) return;
    _pendingNames[recipe.id] = recipe;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _flushNames);
  }

  /// Translate the full recipe (name, ingredients, steps) on detail open.
  void requestDetails(Recipe recipe) {
    if (!_needsTranslation(recipe)) return;
    if (!_requestedDetails.add(recipe.id)) return;
    _requestedNames.add(recipe.id);
    _setTranslatingDetails(recipe.id, true);
    _enqueue(() async {
      try {
        await _translateDetails(recipe);
      } finally {
        _setTranslatingDetails(recipe.id, false);
      }
    });
  }

  void _setTranslatingDetails(String id, bool on) {
    if (!mounted) return;
    final next = {...state.translatingDetails};
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(translatingDetails: next);
  }

  void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) async {
      if (!mounted) return;
      try {
        await job();
      } catch (e) {
        debugPrint('[RecipeTranslation] job failed: $e');
      }
    });
  }

  void _flushNames() {
    if (_pendingNames.isEmpty) return;
    final batch = _pendingNames.values.toList();
    _pendingNames.clear();
    _enqueue(() => _translateNames(batch));
  }

  Future<bool> _ensurePairReady(String from) async {
    final key = '$from>$lang';
    final known = _pairStatus[key];
    if (known == TranslationPackStatus.installed) return true;
    if (known == TranslationPackStatus.unsupported ||
        known == TranslationPackStatus.unavailable) {
      return false;
    }
    var status = await _bridge.status(from, lang);
    if (status == TranslationPackStatus.supported &&
        _preparedPairsThisSession.add(key)) {
      debugPrint('[RecipeTranslation] requesting language download $key');
      await _bridge.prepare(from, lang);
      status = await _bridge.status(from, lang);
    }
    debugPrint('[RecipeTranslation] pair $key status=${status.name}');
    // "supported" (not downloaded) is not cached so a later screen can retry
    // once the user has installed the language.
    if (status != TranslationPackStatus.supported) _pairStatus[key] = status;
    return status == TranslationPackStatus.installed;
  }

  Future<List<String>> _translate(
    String from,
    List<String> texts, {
    void Function()? onFailure,
  }) =>
      RecipeTranslationGlossary.translateAll(
        texts,
        (batch) async {
          final res = await _bridge.translateBatch(from, lang, batch);
          if (res == null) onFailure?.call();
          return res;
        },
      );

  Future<void> _translateNames(List<Recipe> recipes) async {
    final cached = await _loadCache(recipes.map((r) => r.id));
    final todo = <Recipe>[];
    final updates = <String, RecipeTranslation>{};
    for (final r in recipes) {
      final row = cached[r.id];
      if (row != null &&
          row['name'] != null &&
          row['name_sig'] == _sig(r.name)) {
        updates[r.id] = (state.byId[r.id] ?? const RecipeTranslation())
            .copyWith(name: row['name'] as String);
      } else if (RecipeTranslationGlossary.needsTranslation(r.name)) {
        todo.add(r);
      }
    }
    _apply(updates);

    final byLang = <String, List<Recipe>>{};
    for (final r in todo) {
      byLang.putIfAbsent(r.language, () => []).add(r);
    }
    for (final entry in byLang.entries) {
      if (!mounted) return;
      if (!await _ensurePairReady(entry.key)) continue;
      final list = entry.value;
      for (var i = 0; i < list.length; i += _nameBatchSize) {
        if (!mounted) return;
        final chunk =
            list.sublist(i, (i + _nameBatchSize).clamp(0, list.length));
        final translated =
            await _translate(entry.key, [for (final r in chunk) r.name]);
        final chunkUpdates = <String, RecipeTranslation>{};
        for (var k = 0; k < chunk.length; k++) {
          final r = chunk[k];
          final name = translated[k];
          if (name == r.name) continue;
          chunkUpdates[r.id] = (state.byId[r.id] ?? const RecipeTranslation())
              .copyWith(name: name);
          await _saveCache(r.id, name: name, nameSig: _sig(r.name));
        }
        _apply(chunkUpdates);
      }
    }
  }

  Future<void> _translateDetails(Recipe r) async {
    final detailsSig = _detailsSig(r);
    final cached = (await _loadCache([r.id]))[r.id];
    if (cached != null) {
      var t = state.byId[r.id] ?? const RecipeTranslation();
      if (cached['name'] != null && cached['name_sig'] == _sig(r.name)) {
        t = t.copyWith(name: cached['name'] as String);
      }
      if (cached['details_sig'] == detailsSig) {
        final ingredients = _decodeIngredients(r, cached['ingredients']);
        final steps = _decodeSteps(r, cached['steps']);
        if (ingredients != null && steps != null) {
          _apply({r.id: t.copyWith(ingredients: ingredients, steps: steps)});
          return;
        }
      }
      _apply({r.id: t});
    }

    if (!await _ensurePairReady(r.language)) return;
    if (!mounted) return;

    final translateAmount = <int>[
      for (var i = 0; i < r.ingredients.length; i++)
        if (_amountHasWords(r.ingredients[i].amount)) i,
    ];
    final texts = <String>[
      r.name,
      ...r.ingredients.map((i) => i.name),
      for (final i in translateAmount) r.ingredients[i].amount,
      ...r.steps,
    ];
    var failed = false;
    final out = await _translate(r.language, texts, onFailure: () => failed = true);
    if (!mounted) return;
    if (failed) {
      debugPrint('[RecipeTranslation] details for ${r.id} failed; not cached');
      return;
    }

    var cursor = 0;
    final name = out[cursor++];
    final names = <String>[
      for (var i = 0; i < r.ingredients.length; i++) out[cursor++],
    ];
    final amounts = [for (final i in r.ingredients) i.amount];
    for (final i in translateAmount) {
      amounts[i] = out[cursor++];
    }
    final steps = <String>[
      for (var i = 0; i < r.steps.length; i++) out[cursor++],
    ];
    final ingredients = <RecipeIngredient>[
      for (var i = 0; i < r.ingredients.length; i++)
        RecipeIngredient(
          name: names[i],
          amount: amounts[i],
          grams: r.ingredients[i].grams,
        ),
    ];
    _apply({
      r.id: (state.byId[r.id] ?? const RecipeTranslation()).copyWith(
        name: name,
        ingredients: ingredients,
        steps: steps,
      ),
    });
    await _saveCache(
      r.id,
      name: name,
      nameSig: _sig(r.name),
      ingredientsJson: jsonEncode([
        for (final i in ingredients) {'name': i.name, 'amount': i.amount},
      ]),
      stepsJson: jsonEncode(steps),
      detailsSig: detailsSig,
    );
  }

  void _apply(Map<String, RecipeTranslation> updates) {
    if (updates.isEmpty || !mounted) return;
    state = state.copyWith(byId: {...state.byId, ...updates});
  }

  Future<Map<String, Map<String, dynamic>>> _loadCache(
      Iterable<String> ids) async {
    try {
      return await DatabaseService.instance.getRecipeTranslations(lang, ids);
    } catch (e) {
      debugPrint('[RecipeTranslation] cache read failed: $e');
      return const {};
    }
  }

  Future<void> _saveCache(
    String id, {
    String? name,
    String? nameSig,
    String? ingredientsJson,
    String? stepsJson,
    String? detailsSig,
  }) async {
    try {
      await DatabaseService.instance.upsertRecipeTranslation(
        recipeId: id,
        lang: lang,
        name: name,
        nameSig: nameSig,
        ingredientsJson: ingredientsJson,
        stepsJson: stepsJson,
        detailsSig: detailsSig,
      );
    } catch (e) {
      debugPrint('[RecipeTranslation] cache write failed: $e');
    }
  }

  static List<RecipeIngredient>? _decodeIngredients(Recipe r, Object? raw) {
    if (raw is! String) return null;
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.length != r.ingredients.length) return null;
      return [
        for (var i = 0; i < list.length; i++)
          RecipeIngredient(
            name: list[i]['name'] as String? ?? r.ingredients[i].name,
            amount: list[i]['amount'] as String? ?? r.ingredients[i].amount,
            grams: r.ingredients[i].grams,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  static List<String>? _decodeSteps(Recipe r, Object? raw) {
    if (raw is! String) return null;
    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.length == r.steps.length ? list : null;
    } catch (_) {
      return null;
    }
  }

  static bool _amountHasWords(String amount) =>
      RegExp(r'\p{L}{3,}', unicode: true).hasMatch(amount);

  static String _detailsSig(Recipe r) => _sig(jsonEncode([
        for (final i in r.ingredients) [i.name, i.amount],
        r.steps,
      ]));

  /// Stable FNV-1a (32-bit) hash of the source text.
  static String _sig(String text) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(text)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final recipeTranslationProvider =
    StateNotifierProvider<RecipeTranslationNotifier, RecipeTranslationState>(
  (ref) => RecipeTranslationNotifier(ref.watch(localeProvider).code),
);
