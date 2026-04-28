#!/usr/bin/env python3
"""Replace _parseTranscript method with improved version."""

FILE = 'lib/screens/voice_entry_screen.dart'

with open(FILE, 'r') as f:
    content = f.read()

start_marker = '  /// Simple NLP parser: split by'
end_marker = '  Future<void> _logAll() async {'

start_idx = content.index(start_marker)
end_idx = content.index(end_marker)

new_method = r"""  /// NLP parser: handles word-numbers, plurals, smart segmentation.
  List<_ParsedFood> _parseTranscript(String text) {
    final results = <_ParsedFood>[];
    final lower = text.toLowerCase().replaceAll(RegExp(r'[^\w\s,]'), '');

    // 1. Convert word-numbers to digits
    final converted = _wordNumbersToDigits(lower);

    // 2. Split on "and", commas, "with"
    var segments = converted.split(RegExp(r'\s*(?:,\s*|(?:^|\s)and\s+|(?:^|\s)with\s+)'));

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

      final qMatch = RegExp(r'^(\d+(?:\.\d+)?)\s*(g|grams?|ml|pieces?|servings?|cups?|slices?)?\s*(?:of\s+)?(.+)$')
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

        if (matched < queryWords.length) continue;

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

"""

content = content[:start_idx] + new_method + content[end_idx:]

with open(FILE, 'w') as f:
    f.write(content)

print('Done - replaced _parseTranscript with improved version')
