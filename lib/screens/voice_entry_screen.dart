import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/app_localizations.dart';
import '../models/custom_meal.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../providers/locale_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_theme_effects.dart';
import 'voice/voice_translation.dart';

/// Voice-powered food logging.
///
/// Listens to spoken English, parses food names + optional quantities,
/// and logs them in one tap.  Works offline using iOS's built-in speech
/// recognition engine.
class VoiceEntryScreen extends ConsumerStatefulWidget {
  const VoiceEntryScreen({super.key});

  @override
  ConsumerState<VoiceEntryScreen> createState() => _VoiceEntryScreenState();
}

class _VoiceEntryScreenState extends ConsumerState<VoiceEntryScreen> {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;
  String _transcript = '';
  List<_ParsedFood> _parsed = [];
  String? _error;
  bool _lowConfidence = false;
  List<FoodData> _allFoods = [];

  // ── Save as meal ───────────────────────────────────────────────
  final _mealNameCtrl = TextEditingController();
  bool _saveAsMeal = false;
  MealType _mealType = MealType.lunch;

  // Persistent per-row controllers for the editable grams field. Recreating a
  // controller every build reset the caret to the start mid-typing; caching
  // them by row index keeps the cursor where the user left it.
  final Map<int, TextEditingController> _gramControllers = {};

  TextEditingController _gramController(int index, double grams) {
    return _gramControllers[index] ??=
        TextEditingController(text: grams.round().toString());
  }

  void _disposeGramControllers() {
    for (final c in _gramControllers.values) {
      c.dispose();
    }
    _gramControllers.clear();
  }

  /// Remove a parsed item before logging (e.g. a mishear). Controllers are
  /// keyed by row index, so dispose them all and let them rebuild.
  void _removeParsed(int index) {
    if (index < 0 || index >= _parsed.length) return;
    setState(() {
      _disposeGramControllers();
      final next = [..._parsed]..removeAt(index);
      _parsed = next;
    });
  }

  /// Let the user search and assign the correct food for a row — used both to
  /// fix an "Unknown" item and to correct a wrong match before logging.
  Future<void> _resolveParsed(int index) async {
    if (index < 0 || index >= _parsed.length) return;
    final picked = await showModalBottomSheet<FoodData>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoiceFoodSearchSheet(foods: _allFoods),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final old = _parsed[index];
      final grams = old.grams <= 0 ? 100.0 : old.grams;
      _disposeGramControllers();
      final next = [..._parsed];
      next[index] = _ParsedFood(food: picked, grams: grams);
      _parsed = next;
    });
  }

  static const _foodAliases = {
    'nut': 'mixed nuts',
    'nuts': 'mixed nuts',
    'mixed nut': 'mixed nuts',
    'blueberries': 'blueberry',
    'strawberries': 'strawberry',
    'raspberries': 'raspberry',
    'blackberries': 'blackberry',
    'cranberries': 'cranberry',
    'cherries': 'cherry',
    'thee': 'tea',
    'tater': 'potato',
    'taters': 'potato',
    'spud': 'potato',
    'spuds': 'potato',
    'fries': 'french fries',
    'chips': 'potato chips',
    'crisps': 'potato chips',
    'chix': 'chicken',
    'breast': 'chicken breast',
    'thigh': 'chicken thigh',
    'drumstick': 'chicken',
    'steak': 'beef steak',
    'ribeye': 'beef steak',
    'sirloin': 'beef steak',
    'filet': 'beef steak',
    'mince': 'ground beef',
    'ground meat': 'ground beef',
    'pork chop': 'pork',
    'ham': 'pork',
    'bacon strip': 'bacon',
    'oatmeal': 'oats',
    'porridge': 'oats',
    'cereal': 'oats',
    'granola bar': 'granola',
    'pb': 'peanut butter',
    'almond butter': 'almond butter',
    'oj': 'orange juice',
    'juice': 'orange juice',
    'soda': 'soft drink',
    'pop': 'soft drink',
    'coke': 'soft drink',
    'pepsi': 'soft drink',
    'sprite': 'soft drink',
    'latte': 'coffee',
    'espresso': 'coffee',
    'cappuccino': 'coffee',
    'toast': 'bread',
    'naan': 'bread',
    'pita': 'bread',
    'tortilla': 'bread',
    'wrap': 'bread',
    'bagel': 'bread',
    'croissant': 'bread',
    'roll': 'bread',
    'bun': 'bread',
    'jam': 'fruit jam',
    'jelly': 'fruit jam',
    'marmalade': 'fruit jam',
    'veggies': 'mixed vegetables',
    'vegetables': 'mixed vegetables',
    'greens': 'spinach',
    'lettuce': 'salad',
    'romaine': 'salad',
    'arugula': 'salad',
    'rocket': 'salad',
    'sweetcorn': 'corn',
    'maize': 'corn',
    'tuna can': 'tuna',
    'canned tuna': 'tuna',
    'tinned tuna': 'tuna',
    'sardine': 'sardines',
    'prawn': 'shrimp',
    'prawns': 'shrimp',
    'shrimps': 'shrimp',
    'curd': 'yogurt',
    'greek yoghurt': 'greek yogurt',
    'yoghurt': 'yogurt',
    'cottage cheese': 'cottage cheese',
    'cream cheese': 'cream cheese',
    'cheddar': 'cheddar cheese',
    'mozzarella': 'mozzarella cheese',
    'parmesan': 'parmesan cheese',
    'feta': 'feta cheese',
    'gouda': 'cheese',
    'brie': 'cheese',
    'swiss': 'cheese',
  };

  static const _speechStopWords = {
    'i',
    'we',
    'did',
    'do',
    'just',
    'also',
    'then',
    'please',
    'log',
    'logged',
    'add',
    'ate',
    'eat',
    'eaten',
    'had',
    'have',
    'having',
    'consumed',
    'and',
    'with',
    'of',
    'a',
    'an',
    'the',
    'some',
    'bit',
    'little',
    'full',
    'hand',
    'today',
    'tonight',
    'yesterday',
    'morning',
    'afternoon',
    'evening',
    'for',
    'lunch',
    'dinner',
    'breakfast',
    'snack',
    'my',
    'that',
    'this',
    'like',
    'about',
    'around',
    'roughly',
    'approximately',
  };

  /// Single words that speech recognition captures but are not food items.
  static const _nonFoodWords = {
    'it',
    'is',
    'was',
    'were',
    'be',
    'been',
    'am',
    'are',
    'so',
    'no',
    'yes',
    'not',
    'but',
    'or',
    'if',
    'at',
    'in',
    'on',
    'to',
    'up',
    'me',
    'he',
    'she',
    'they',
    'what',
    'when',
    'how',
    'much',
    'many',
    'very',
    'really',
    'thing',
    'stuff',
    'lot',
    'good',
    'bad',
    'nice',
    'big',
    'small',
    'more',
    'less',
    'enough',
    'too',
    'well',
    'pretty',
    'kind',
    'type',
    'sort',
    'way',
    'something',
    'anything',
    'nothing',
    'everything',
    'maybe',
    'actually',
    'basically',
    'literally',
    'ok',
    'okay',
    'yeah',
    'yep',
    'nope',
    'um',
    'uh',
    'hmm',
    'ah',
    'oh',
  };

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadFoods();
  }

  Future<void> _loadFoods() async {
    try {
      _allFoods = await DatabaseService.instance.getAllFoods();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load food database: $e');
    }
  }

  Future<void> _initSpeech() async {
    try {
      _available = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          // Ignore late/transient plugin errors once we already have a usable
          // result — otherwise a code like "error_no_match" overwrites a
          // perfectly good transcript with a cryptic, scary message.
          if (_parsed.isNotEmpty || _transcript.trim().isNotEmpty) return;
          setState(() => _error = _friendlySpeechError(e.errorMsg));
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
    } catch (e) {
      _available = false;
      if (mounted) {
        debugPrint('Speech recognition unavailable: $e');
        setState(() =>
            _error = AppLocalizations.of(context).voiceRecognitionUnavailable);
      }
    }
    if (mounted) setState(() {});
  }

  /// Turns raw speech-plugin error codes (e.g. "error_no_match") into clear,
  /// reassuring guidance instead of an alarming "unknown error".
  String _friendlySpeechError(String code) {
    final l10n = AppLocalizations.of(context);
    final c = code.toLowerCase();
    if (c.contains('no_match') ||
        c.contains('nomatch') ||
        c.contains('speech_timeout') ||
        c.contains('timeout')) {
      return l10n.voiceErrNoMatch;
    }
    if (c.contains('permission') || c.contains('denied')) {
      return l10n.voiceErrPermission;
    }
    if (c.contains('network')) {
      return l10n.voiceErrNetwork;
    }
    if (c.contains('busy')) {
      return l10n.voiceErrBusy;
    }
    return l10n.voiceErrGeneric;
  }

  void _startListening() {
    if (!_available) {
      setState(() =>
          _error = AppLocalizations.of(context).voiceNotAvailableOnDevice);
      return;
    }
    setState(() {
      _error = null;
      _listening = true;
      _transcript = '';
      _parsed = [];
      _lowConfidence = false;
    });
    try {
      // Use the app language for speech recognition
      final langCode = ref.read(localeProvider).code;
      final localeMap = {
        'en': 'en_US',
        'pl': 'pl_PL',
        'nl': 'nl_NL',
        'es': 'es_ES',
        'de': 'de_DE',
      };
      _speech.listen(
        onResult: _onResult,
        localeId: localeMap[langCode] ?? 'en_US',
        listenMode: ListenMode.dictation,
        partialResults: true,
      );
    } catch (e) {
      setState(() {
        _listening = false;
        _error = 'Could not start listening: $e';
      });
    }
  }

  void _stopListening() {
    try {
      _speech.stop();
    } catch (_) {}
    if (mounted) setState(() => _listening = false);
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _transcript = result.recognizedWords;
      if (result.finalResult) {
        try {
          // New parse → row indices change; drop stale grams controllers.
          _disposeGramControllers();
          final langCode = ref.read(localeProvider).code;
          _parsed = _parseTranscript(_transcript, langCode);
          _lowConfidence = result.hasConfidenceRating &&
              result.confidence > 0 &&
              result.confidence < 0.55 &&
              _parsed.isNotEmpty;
          if (_parsed.isEmpty) {
            _error = _transcript.trim().isEmpty
                ? 'I didn\'t catch anything. Tap the mic and say e.g. '
                    '"200 grams of chicken and a banana".'
                : 'No foods recognised in "$_transcript". Try naming the food '
                    'and amount, e.g. "two eggs and a slice of bread".';
          } else {
            _error = null;
          }
        } catch (e) {
          _error = 'Something went wrong reading that. Please try again.';
          _parsed = [];
          _lowConfidence = false;
        }
      }
    });
  }

  /// NLP parser: handles word-numbers, plurals, smart segmentation.
  List<_ParsedFood> _parseTranscript(String text, String langCode) {
    final results = <_ParsedFood>[];
    // Parse the transcript natively in the user's language: localized numbers,
    // fractions, units, connectors and food names are understood directly and
    // each food is resolved against a multilingual index — no English pivot.
    final spoken = parseSpokenFoods(text, langCode);

    for (final item in spoken) {
      // [grams] is set when the speaker gave an explicit weight/volume;
      // [pieceCount] is set when they gave a count and is refined to a realistic
      // weight using the matched food's category after matching.
      final double? grams = item.grams;
      final double? pieceCount = item.pieceCount;

      // Apply English aliases / depluralization for the DB match. When the food
      // already resolved to a canonical English label this is a no-op; for an
      // unresolved native phrase it harmlessly normalizes any English residue.
      var foodQuery = _normaliseFoodQuery(item.foodQuery);
      if (foodQuery.isEmpty || _isNoiseFoodQuery(foodQuery)) continue;


      // 6. Fuzzy match against food DB
      FoodData? match;
      int bestScore = -999;
      final queryWords = foodQuery
          .split(' ')
          .where((w) => w.length > 1 && !_speechStopWords.contains(w))
          .toList();

      if (queryWords.isEmpty) continue;

      // Skip queries made up entirely of common non-food / chatter words
      // (e.g. "really good", "some stuff", "the thing").
      if (queryWords.every(_nonFoodWords.contains)) continue;

      for (final f in _allFoods) {
        final fLabel = f.label.toLowerCase();
        final fWords = fLabel.split(' ');

        // Exact full match — highest priority
        if (fLabel == foodQuery) {
          match = f;
          bestScore = 10000;
          break;
        }

        // Check for alias-based exact match
        final aliased = _foodAliases[foodQuery];
        if (aliased != null && fLabel == aliased) {
          match = f;
          bestScore = 9000;
          break;
        }

        // Count how many query words appear in the food label
        int matched = 0;
        for (final qw in queryWords) {
          if (fWords.any((fw) =>
              fw.contains(qw) ||
              qw.contains(fw) ||
              _depluralize(fw) == qw ||
              fw == _depluralize(qw) ||
              _levenshteinClose(fw, qw))) {
            matched++;
          }
        }

        // For multi-word queries, require ALL words to match (prevents "protein powder"
        // from matching "protein bar" when user said "protein powder")
        if (queryWords.length > 1 && matched < queryWords.length) continue;
        // For single-word queries, still require at least 1 match
        if (queryWords.length == 1 && matched == 0) continue;

        final unmatched = fWords
            .where((fw) => !queryWords.any((qw) =>
                fw.contains(qw) ||
                qw.contains(fw) ||
                _depluralize(fw) == qw ||
                fw == _depluralize(qw) ||
                _levenshteinClose(fw, qw)))
            .length;

        final score = matched * 10 - unmatched * 5;
        if (score > bestScore) {
          bestScore = score;
          match = f;
        }
      }

      if (match != null && bestScore >= 5) {
        // Refine a spoken count into a realistic weight using the matched
        // food's category (a "piece" of nuts is not a "piece" of steak).
        final resolvedGrams = pieceCount != null
            ? pieceCount * _typicalPieceGrams(match.category)
            : (grams ?? 100);
        results.add(_ParsedFood(food: match, grams: resolvedGrams));
      } else {
        // Only surface an unrecognised item when the residue genuinely looks
        // like a food name — not leftover filler, verbs, numbers or chatter.
        final cleaned = _foodLikeResidue(queryWords);
        if (cleaned != null) {
          results.add(_ParsedFood(food: null, query: cleaned, grams: grams ?? 100));
        }
      }
    }

    // Combine duplicate foods ("rice and rice", "a banana and another banana")
    // into a single entry by summing their weights so each food is logged once.
    if (results.length > 1) {
      final mergedByKey = <String, _ParsedFood>{};
      final order = <String>[];
      for (final pf in results) {
        final key =
            pf.food != null ? 'food:${pf.food!.label}' : 'query:${pf.query}';
        final existing = mergedByKey[key];
        if (existing == null) {
          mergedByKey[key] = pf;
          order.add(key);
        } else {
          mergedByKey[key] = _ParsedFood(
            food: existing.food,
            query: existing.query,
            grams: existing.grams + pf.grams,
          );
        }
      }
      return [for (final k in order) mergedByKey[k]!];
    }
    return results;
  }

  /// Typical edible weight (grams) of one piece/serving of a food, by category.
  /// Turns a spoken count ("two apples", "a banana") into a realistic weight
  /// instead of a flat per-piece guess.
  static double _typicalPieceGrams(String category) {
    switch (category.toLowerCase()) {
      case 'fruit':
        return 120; // a medium apple / banana / orange
      case 'vegetable':
        return 90;
      case 'protein':
        return 120; // a fillet or portion of meat/fish
      case 'grain':
      case 'bread':
        return 50; // a slice / roll / bun
      case 'legume':
        return 100;
      case 'dairy':
        return 120; // a yoghurt pot / cheese serving
      case 'drink':
        return 250; // a glass
      case 'nut':
        return 30; // a small handful
      case 'snack':
        return 35;
      case 'dessert':
        return 90;
      default:
        return 110; // sensible middle ground for "mixed"/unknown
    }
  }

  static String _normaliseFoodQuery(String query) {
    var out = query
        .replaceAll(RegExp(r'\s+'), ' ')
        // Drop quantity / fraction residue that survives quantity extraction
        // ("third of an apple", "piece of toast") so it can't block matching.
        .replaceAll(
            RegExp(r'\b(?:some|the|of|piece|pieces|bit|bits|third|thirds|'
                r'quarter|quarters|fourth|fourths|fifth|fifths|half|halves|'
                r'another|more|couple|few)\b'),
            ' ')
        .trim();
    out = out
        .split(' ')
        .map(_depluralize)
        .where((word) => word.isNotEmpty)
        .join(' ')
        .trim();
    return _foodAliases[out] ?? out;
  }

  static bool _isNoiseFoodQuery(String query) {
    final words = query.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return true;
    return words.every(
        (w) => _speechStopWords.contains(w) || _nonFoodWords.contains(w));
  }

  /// Returns a cleaned food-name string when [queryWords] plausibly describe a
  /// real food, or `null` when the residue is just filler, verbs, stray numbers
  /// or conversational chatter. Prevents random words from showing up as foods.
  static String? _foodLikeResidue(List<String> queryWords) {
    final words = queryWords
        .map((w) => w.replaceAll(RegExp(r'[0-9]'), '').trim())
        .where((w) => w.length >= 3)
        .where((w) => !_speechStopWords.contains(w))
        .where((w) => !_nonFoodWords.contains(w))
        .toList();
    if (words.isEmpty) return null;
    return words.join(' ');
  }

  /// Remove trailing 's' / 'es' from food names so "bananas" matches "banana".
  static String _depluralize(String word) {
    if (word.length < 4) return word;
    if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
    if (word.endsWith('ves')) return '${word.substring(0, word.length - 3)}f';
    if (word.endsWith('ses') ||
        word.endsWith('xes') ||
        word.endsWith('zes') ||
        word.endsWith('ches') ||
        word.endsWith('shes')) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && !word.endsWith('ss')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  /// Fuzzy match: allows 1 character edit distance for words > 4 chars.
  /// Catches speech recognition typos like "chiken" → "chicken".
  static bool _levenshteinClose(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    if (a.length < 4 || b.length < 4) return false;
    int diffs = 0;
    int ia = 0, ib = 0;
    while (ia < a.length && ib < b.length) {
      if (a[ia] != b[ib]) {
        diffs++;
        if (diffs > 1) return false;
        if (a.length > b.length) {
          ia++;
        } else if (b.length > a.length) {
          ib++;
        } else {
          ia++;
          ib++;
        }
      } else {
        ia++;
        ib++;
      }
    }
    diffs += (a.length - ia) + (b.length - ib);
    return diffs <= 1;
  }

  Future<void> _logAll() async {
    try {
      await _doLogAll();
    } catch (e, st) {
      if (mounted) {
        setState(() => _error = 'Log failed: $e\n\n$st');
      }
    }
  }

  Future<void> _doLogAll() async {
    final validFoods = _parsed.where((p) => p.food != null).toList();
    if (validFoods.isEmpty) return;

    // ── Optionally save as a custom meal ────────────────────────────
    if (_saveAsMeal) {
      final mealName = _mealNameCtrl.text.trim();
      if (mealName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).enterMealName)),
        );
        return;
      }

      final meal = CustomMeal(
        name: mealName,
        mealType: _mealType,
        createdAt: DateTime.now(),
      );
      final ingredients = validFoods
          .map((pf) => MealIngredient(
                mealId: 0, // will be set by insertCustomMeal
                foodLabel: pf.food!.label,
                grams: pf.grams,
              ))
          .toList();
      await DatabaseService.instance.insertCustomMeal(meal, ingredients);
    }

    // ── Log as a scan result for today's intake ──────────────────────
    final foods = <DetectedFood>[];
    for (final pf in validFoods) {
      final food = pf.food!;
      final grams = pf.grams;
      final kcalMin = food.kcalPer100g * grams / 100 * 0.9;
      final kcalMax = food.kcalPer100g * grams / 100 * 1.1;

      foods.add(DetectedFood(
        label: food.label,
        volumeCm3: grams / ((food.densityMin + food.densityMax) / 2),
        caloriesMin: kcalMin,
        caloriesMax: kcalMax,
      ));
    }

    final scan = ScanResult(
      timestamp: DateTime.now(),
      depthMode: 'voice',
      foods: foods,
    );

    await DatabaseService.instance.insertScanResult(scan);
    await ref.read(dailyIntakeProvider.notifier).load();
    await ref.read(historyProvider.notifier).load();

    if (mounted) {
      final saved =
          _saveAsMeal ? ' • saved as "${_mealNameCtrl.text.trim()}"' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('✅ Logged ${validFoods.length} food(s) via voice$saved'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    try {
      _speech.stop();
    } catch (_) {}
    _mealNameCtrl.dispose();
    _disposeGramControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visualTheme = context.visualTheme;
    final premium = visualTheme.premium;
    // "Actively editing" == keyboard visible; drives the contextual Done
    // button + dismiss FAB so neither is permanently shown.
    final editing = MediaQuery.of(context).viewInsets.bottom > 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiSpeech),
        actions: [
          if (editing)
            TextButton(
              onPressed: () => FocusScope.of(context).unfocus(),
              child: Text(l10n.done),
            ),
        ],
      ),
      floatingActionButton: editing
          ? FloatingActionButton.extended(
              onPressed: () => FocusScope.of(context).unfocus(),
              icon: const Icon(Icons.keyboard_arrow_down),
              label: Text(l10n.done),
            )
          : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Instructions ──────────────────────────────────────
                  Card(
                    color: premium ? visualTheme.cardColor : context.primary50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.mic,
                              color: premium
                                  ? visualTheme.primaryAccent
                                  : context.primary600,
                              size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Tell me what you ate',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Say naturally, e.g.:\n'
                                  '• "200 grams of chicken and a banana"\n'
                                  '• "2 eggs, toast with peanut butter"\n'
                                  '• "a bowl of oatmeal and a coffee"\n'
                                  '• "150g salmon with rice and broccoli"',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appMutedTextColor,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Mic button ─────────────────────────────────────────
                  GestureDetector(
                    onTap: _listening ? _stopListening : _startListening,
                    child: PremiumMotionSurface(
                      enabled: premium,
                      borderRadius: BorderRadius.circular(_listening ? 58 : 48),
                      padding: const EdgeInsets.all(5),
                      borderWidth: _listening ? 4.2 : 3.4,
                      glow: true,
                      animate: premium,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: _listening ? 100 : 80,
                        height: _listening ? 100 : 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: premium
                              ? visualTheme.surface
                              : (_listening
                                  ? Colors.red.shade400
                                  : context.primary600),
                          boxShadow: _listening
                              ? [
                                  BoxShadow(
                                    color: (premium
                                            ? visualTheme.secondaryAccent
                                            : Colors.red)
                                        .withValues(alpha: 0.44),
                                    blurRadius: premium ? 34 : 24,
                                    spreadRadius: premium ? 10 : 8,
                                  ),
                                ]
                              : [],
                        ),
                        child: Icon(
                          _listening ? Icons.stop : Icons.mic,
                          color: premium
                              ? (_listening
                                  ? visualTheme.secondaryAccent
                                  : visualTheme.primaryAccent)
                              : Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _listening
                        ? 'Listening… speak naturally'
                        : (_available
                            ? 'Tap to speak'
                            : 'Initialising speech…'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          _listening ? FontWeight.w600 : FontWeight.w400,
                      color: premium
                          ? (_listening
                              ? visualTheme.secondaryAccent
                              : visualTheme.onMuted)
                          : (_listening
                              ? Colors.red.shade400
                              : AppTheme.gray400),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    _ErrorBox(error: _error!),
                  ],
                  const SizedBox(height: 20),

                  // ── Transcript ──────────────────────────────────────────
                  if (_transcript.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            premium ? visualTheme.cardColor : AppTheme.gray100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: premium
                              ? visualTheme.borderColor
                              : AppTheme.gray100,
                          width: premium ? 1.8 : 1,
                        ),
                      ),
                      child: Text(
                        '"$_transcript"',
                        style: TextStyle(
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: context.appTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Parsed foods ────────────────────────────────────────
                  if (_parsed.isNotEmpty) ...[
                    if (_lowConfidence)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Heard with low confidence — please double-check '
                                'the items below.',
                                style: TextStyle(
                                    fontSize: 12, color: context.appTextColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _parsed.length,
                      itemBuilder: (_, i) {
                        final p = _parsed[i];
                        final matched = p.food != null;
                        return PremiumMotionSurface(
                          enabled: premium && matched,
                          borderRadius: BorderRadius.circular(14),
                          padding: const EdgeInsets.all(2),
                          borderWidth: 2.8,
                          glow: false,
                          child: Card(
                            color: matched
                                ? (premium
                                    ? visualTheme.cardColor
                                    : Colors.white)
                                : AppTheme.red100,
                            child: ListTile(
                              onTap: () => _resolveParsed(i),
                              leading: Icon(
                                matched
                                    ? Icons.check_circle
                                    : Icons.help_outline,
                                color: matched
                                    ? (premium
                                        ? visualTheme.primaryAccent
                                        : context.primary600)
                                    : Colors.red.shade400,
                              ),
                              title: Text(
                                matched
                                    ? p.food!.label
                                    : 'Unknown: "${p.query}"',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: matched
                                      ? context.appTextColor
                                      : AppTheme.red700,
                                ),
                              ),
                              subtitle: Text(
                                matched
                                    ? '${p.grams.round()} g  •  ${(p.food!.kcalPer100g * p.grams / 100).round()} kcal  •  tap to change'
                                    : 'Not found — tap to search the food',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: matched
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 56,
                                          child: TextField(
                                            keyboardType: TextInputType.number,
                                            controller:
                                                _gramController(i, p.grams),
                                            onChanged: (v) {
                                              final g = double.tryParse(v);
                                              if (g != null) {
                                                setState(() => _parsed[i] =
                                                    _ParsedFood(
                                                        food: p.food,
                                                        grams: g));
                                              }
                                            },
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              suffixText: 'g',
                                              border: OutlineInputBorder(),
                                            ),
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              size: 18),
                                          tooltip: AppLocalizations.of(context).remove,
                                          color: context.appMutedTextColor,
                                          onPressed: () => _removeParsed(i),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.search,
                                              size: 18),
                                          tooltip: AppLocalizations.of(context).searchFoodTooltip,
                                          color: Colors.red.shade400,
                                          onPressed: () => _resolveParsed(i),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              size: 18),
                                          tooltip: AppLocalizations.of(context).remove,
                                          color: Colors.red.shade400,
                                          onPressed: () => _removeParsed(i),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── Save as meal toggle ───────────────────────────────
                    Card(
                      color: premium
                          ? visualTheme.cardColor
                          : (_saveAsMeal ? context.primary50 : null),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: premium
                              ? visualTheme.borderColor
                              : (_saveAsMeal
                                  ? context.primary400
                                  : AppTheme.gray200),
                          width: premium ? 1.8 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Column(
                          children: [
                            // Toggle row
                            Row(
                              children: [
                                Icon(Icons.bookmark_add_outlined,
                                    color: _saveAsMeal
                                        ? context.primary600
                                        : context.appMutedTextColor,
                                    size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Save as a meal',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: _saveAsMeal
                                          ? context.primary700
                                          : AppTheme.gray700,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _saveAsMeal,
                                  onChanged: (v) =>
                                      setState(() => _saveAsMeal = v),
                                ),
                              ],
                            ),
                            // Name + meal type fields (only when toggled on)
                            if (_saveAsMeal) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _mealNameCtrl,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(context).mealNameLabel,
                                  hintText: AppLocalizations.of(context).mealNameExampleHint,
                                  prefixIcon: const Icon(Icons.restaurant_menu),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Meal type chip row
                              Row(
                                children: MealType.values.map((t) {
                                  final selected = t == _mealType;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(t.displayName),
                                      selected: selected,
                                      onSelected: (_) =>
                                          setState(() => _mealType = t),
                                      selectedColor: context.primary200,
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: selected
                                            ? context.primary700
                                            : context.appMutedTextColor,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Log button ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _parsed.any((p) => p.food != null) ? _logAll : null,
                        icon: Icon(_saveAsMeal
                            ? Icons.bookmark_added
                            : Icons.add_task),
                        label: Text(
                          _saveAsMeal
                              ? 'Log & Save as Meal'
                              : 'Log ${_parsed.where((p) => p.food != null).length} food(s)',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParsedFood {
  final FoodData? food;
  final String? query;
  final double grams;
  const _ParsedFood({this.food, this.query, required this.grams});
}

/// Search-and-pick sheet used to fix an unrecognised voice item or correct a
/// wrong match before logging.
class _VoiceFoodSearchSheet extends StatefulWidget {
  const _VoiceFoodSearchSheet({required this.foods});
  final List<FoodData> foods;

  @override
  State<_VoiceFoodSearchSheet> createState() => _VoiceFoodSearchSheetState();
}

class _VoiceFoodSearchSheetState extends State<_VoiceFoodSearchSheet> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase().trim();
    final matches = q.isEmpty
        ? widget.foods.take(40).toList()
        : (widget.foods
            .where((f) => f.label.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => a.label
              .toLowerCase()
              .indexOf(q)
              .compareTo(b.label.toLowerCase().indexOf(q))))
            .take(60)
            .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: context.appSurfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).searchFoodHint,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text(AppLocalizations.of(context).noMatchingFood))
                  : ListView.builder(
                      controller: ctrl,
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final f = matches[i];
                        return ListTile(
                          title: Text(f.label),
                          subtitle:
                              Text('${f.kcalPer100g.round()} kcal / 100 g'),
                          onTap: () => Navigator.pop(context, f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prominent, scrollable, selectable error box with a copy button.
/// Shown whenever [error] is non-null so the developer can read and
/// copy the exact failure message.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Error — tap & hold to copy',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  color: Colors.red.shade700,
                  tooltip: AppLocalizations.of(context).copyError,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context).errorCopied),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          const Divider(height: 8),
          // Scrollable, selectable error text
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                error,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade900,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
