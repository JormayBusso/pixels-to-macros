import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/custom_meal.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

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
  List<FoodData> _allFoods = [];

  // ── Save as meal ───────────────────────────────────────────────
  final _mealNameCtrl = TextEditingController();
  bool _saveAsMeal = false;
  MealType _mealType = MealType.lunch;

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
          if (mounted) setState(() => _error = e.errorMsg);
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
      );
    } catch (e) {
      _available = false;
      if (mounted) setState(() => _error = 'Speech recognition unavailable: $e');
    }
    if (mounted) setState(() {});
  }

  void _startListening() {
    if (!_available) {
      setState(() => _error = 'Speech recognition not available on this device.');
      return;
    }
    setState(() {
      _error = null;
      _listening = true;
      _transcript = '';
      _parsed = [];
    });
    try {
      _speech.listen(
        onResult: _onResult,
        localeId: 'en_US', // English only
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
          _parsed = _parseTranscript(_transcript);
        } catch (e) {
          _error = 'Failed to parse speech: $e';
          _parsed = [];
        }
      }
    });
  }

  /// NLP parser: handles word-numbers, plurals, smart segmentation.
  List<_ParsedFood> _parseTranscript(String text) {
    final results = <_ParsedFood>[];
    final lower = text.toLowerCase().replaceAll(RegExp(r'[^\w\s,]'), '');

    // 1. Convert word-numbers to digits
    final converted = _wordNumbersToDigits(lower);

    // 2. Strip filler phrases ("also", "i have", "i had", "i ate", "also i have", etc.)
    // These appear naturally in speech but carry no food/quantity meaning.
    final fillerPhrases = RegExp(
      r'\b(also\s+i\s+(have|had|ate|got|eat)|i\s+(have|had|ate|got|eat)|also\s+have|also\s+had|also\s+ate|\balso\b)\s+',
      caseSensitive: false,
    );
    final defiltered = converted.replaceAll(fillerPhrases, '');

    // 3. Split on "and", commas, "with"
    var segments = defiltered.split(RegExp(r'\s*(?:,\s*|(?:^|\s)and\s+|(?:^|\s)with\s+)'));

    // 3. Further split when a digit immediately precedes a food name
    //    e.g. "2 bananas 1 apple" -> ["2 bananas", "1 apple"]
    final refined = <String>[];
    for (var seg in segments) {
      seg = seg.trim();
      if (seg.isEmpty) continue;
      final parts = seg.splitMapJoin(
        RegExp(r'(?<=\S)\s+(?=\d+\s)'),
        onMatch: (m) => '\x00',
        onNonMatch: (s) => s,
      ).split('\x00');
      for (final p in parts) {
        final t = p.trim();
        if (t.isNotEmpty) refined.add(t);
      }
    }

    for (var seg in refined) {
      seg = seg.trim();
      if (seg.isEmpty) continue;

      // 4. Extract quantity
      double? grams;
      String foodQuery = seg;

      final qMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*(g|grams?|ml|pieces?|servings?|cups?|slices?|handfuls?)?\s*(?:of\s+)?(.+)$')
          .firstMatch(seg);
      if (qMatch != null) {
        final qty = double.tryParse(qMatch.group(1)!) ?? 100;
        final unit = qMatch.group(2) ?? '';
        foodQuery = qMatch.group(3)!.trim();

        if (unit.startsWith('piece') || unit.startsWith('serving')) {
          grams = qty * 100;
        } else if (unit.startsWith('cup')) {
          grams = qty * 240;
        } else if (unit.startsWith('slice')) {
          grams = qty * 30;
        } else if (unit.startsWith('handful')) {
          grams = qty * 30;
        } else if (unit.startsWith('g') || unit.startsWith('ml')) {
          grams = qty;
        } else {
          // No unit: treat number as count of pieces (e.g. "2 bananas")
          grams = qty * 120; // 1 piece ~ 120 g average
        }
      }

      // Handle "a/an" prefix
      if (foodQuery.startsWith('a ') || foodQuery.startsWith('an ')) {
        foodQuery = foodQuery.replaceFirst(RegExp(r'^an?\s+'), '');
        grams ??= 120;
      }

      // Handle bare "handful of ..." without a leading number
      final handfulMatch = RegExp(r'^handfuls?\s+(?:of\s+)?(.+)$').firstMatch(foodQuery);
      if (handfulMatch != null) {
        foodQuery = handfulMatch.group(1)!.trim();
        grams ??= 30;
      }

      grams ??= 100;

      // 5. Strip trailing plural 's' for matching
      foodQuery = _depluralize(foodQuery);

      // 6. Fuzzy match against food DB
      FoodData? match;
      int bestScore = -999;
      final queryWords = foodQuery
          .split(' ')
          .where((w) => w.length > 1)
          .toList();

      for (final f in _allFoods) {
        final fLabel = f.label.toLowerCase();
        final fWords = fLabel.split(' ');

        // Exact full match
        if (fLabel == foodQuery) {
          match = f;
          bestScore = 10000;
          break;
        }

        // Count how many query words appear in the food label
        int matched = 0;
        for (final qw in queryWords) {
          if (fWords.any((fw) =>
              fw.contains(qw) || qw.contains(fw) ||
              _depluralize(fw) == qw || fw == _depluralize(qw))) {
            matched++;
          }
        }

        // For multi-word queries, require ALL words to match (prevents "protein powder"
        // from matching "protein bar" when user said "protein powder")
        if (queryWords.length > 1 && matched < queryWords.length) continue;
        // For single-word queries, still require at least 1 match
        if (queryWords.length == 1 && matched == 0) continue;

        final unmatched = fWords
            .where((fw) => !queryWords.any(
                (qw) => fw.contains(qw) || qw.contains(fw) ||
                    _depluralize(fw) == qw || fw == _depluralize(qw)))
            .length;

        final score = matched * 10 - unmatched * 5;
        if (score > bestScore) {
          bestScore = score;
          match     = f;
        }
      }

      if (match != null && bestScore >= 0) {
        results.add(_ParsedFood(food: match, grams: grams));
      } else {
        results.add(_ParsedFood(food: null, query: foodQuery, grams: grams));
      }
    }

    return results;
  }

  /// Map spoken word-numbers to digits so the quantity regex can pick them up.
  static String _wordNumbersToDigits(String text) {
    const map = {
      'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
      'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
      'ten': '10', 'eleven': '11', 'twelve': '12', 'thirteen': '13',
      'fourteen': '14', 'fifteen': '15', 'twenty': '20', 'thirty': '30',
      'forty': '40', 'fifty': '50', 'hundred': '100',
      'half': '0.5',
    };
    var out = text;
    for (final e in map.entries) {
      out = out.replaceAll(RegExp('\\b${e.key}\\b'), e.value);
    }
    return out;
  }

  /// Remove trailing 's' / 'es' from food names so "bananas" matches "banana".
  static String _depluralize(String word) {
    if (word.length < 4) return word;
    if (word.endsWith('ies')) return '${word.substring(0, word.length - 3)}y';
    if (word.endsWith('ves')) return '${word.substring(0, word.length - 3)}f';
    if (word.endsWith('ses') || word.endsWith('xes') || word.endsWith('zes') ||
        word.endsWith('ches') || word.endsWith('shes')) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && !word.endsWith('ss')) {
      return word.substring(0, word.length - 1);
    }
    return word;
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
          const SnackBar(content: Text('Please enter a name for the meal.')),
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
      final saved = _saveAsMeal ? ' • saved as "${_mealNameCtrl.text.trim()}"' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Logged ${validFoods.length} food(s) via voice$saved'),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Speech'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // ── Instructions ──────────────────────────────────────
              Card(
                color: context.primary50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.mic, color: context.primary600, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Speak in English',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Example: "200 grams of chicken and a banana"',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.gray600,
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _listening ? 100 : 80,
                  height: _listening ? 100 : 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening
                        ? Colors.red.shade400
                        : context.primary600,
                    boxShadow: _listening
                        ? [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.4),
                              blurRadius: 24,
                              spreadRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _listening ? 'Listening…' : (_available ? 'Tap to speak' : 'Initialising…'),
                style: const TextStyle(fontSize: 13, color: AppTheme.gray400),
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
                    color: AppTheme.gray100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '"$_transcript"',
                    style: const TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.gray700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Parsed foods ────────────────────────────────────────
              if (_parsed.isNotEmpty) ...[
                Expanded(
                  child: ListView.builder(
                    itemCount: _parsed.length,
                    itemBuilder: (_, i) {
                      final p = _parsed[i];
                      final matched = p.food != null;
                      return Card(
                        color: matched ? Colors.white : AppTheme.red100,
                        child: ListTile(
                          leading: Icon(
                            matched ? Icons.check_circle : Icons.help_outline,
                            color: matched
                                ? context.primary600
                                : Colors.red.shade400,
                          ),
                          title: Text(
                            matched ? p.food!.label : 'Unknown: "${p.query}"',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: matched ? AppTheme.gray900 : AppTheme.red700,
                            ),
                          ),
                          subtitle: Text(
                            matched
                                ? '${p.grams.round()} g  •  ${(p.food!.kcalPer100g * p.grams / 100).round()} kcal'
                                : 'Not found in database',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: matched
                              ? SizedBox(
                                  width: 60,
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    controller: TextEditingController(
                                        text: p.grams.round().toString()),
                                    onChanged: (v) {
                                      final g = double.tryParse(v);
                                      if (g != null) {
                                        setState(() => _parsed[i] = _ParsedFood(
                                            food: p.food, grams: g));
                                      }
                                    },
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      suffixText: 'g',
                                      border: OutlineInputBorder(),
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                // ── Save as meal toggle ───────────────────────────────
                Card(
                  color: _saveAsMeal ? context.primary50 : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _saveAsMeal ? context.primary400 : AppTheme.gray200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        // Toggle row
                        Row(
                          children: [
                            Icon(Icons.bookmark_add_outlined,
                                color: _saveAsMeal
                                    ? context.primary600
                                    : AppTheme.gray400,
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
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Meal name',
                              hintText: 'e.g. My post-workout lunch',
                              prefixIcon: Icon(Icons.restaurant_menu),
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
                                        : AppTheme.gray600,
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
                    onPressed: _parsed.any((p) => p.food != null) ? _logAll : null,
                    icon: Icon(_saveAsMeal ? Icons.bookmark_added : Icons.add_task),
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
    );
  }
}

class _ParsedFood {
  final FoodData? food;
  final String? query;
  final double grams;
  const _ParsedFood({this.food, this.query, required this.grams});
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
                Icon(Icons.error_outline,
                    size: 16, color: Colors.red.shade700),
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
                  tooltip: 'Copy error',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: error));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error copied to clipboard'),
                        duration: Duration(seconds: 2),
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
