/// Protected-term handling for on-device recipe translation.
///
/// Traditional dish names (stamppot, pierogi, spätzle, paella, sushi …) must
/// reach the user exactly as written, whatever the app language. Before a text
/// is sent to the machine translator every protected term is replaced by a
/// numbered placeholder token (`⟦0⟧`, `⟦1⟧` …) and restored afterwards. If the
/// translator drops, duplicates or rewrites a token, the text is instead split
/// around the protected terms and only the unprotected pieces are translated.
library;

/// Signature of a batch translator: same length/order in and out, or `null`
/// when the whole batch failed.
typedef BatchTranslateFn = Future<List<String>?> Function(List<String> texts);

class RecipeTranslationGlossary {
  RecipeTranslationGlossary._();

  /// Untranslatable dish names / culinary terms. Matched case-insensitively on
  /// whole words; longer phrases win over shorter ones ("boerenkool stamppot"
  /// before "stamppot").
  static const List<String> protectedTerms = [
    // Dutch / Flemish
    'stamppot', 'boerenkool stamppot', 'boerenkoolstamppot',
    'zuurkoolstamppot', 'andijviestamppot', 'hutspot', 'erwtensoep', 'snert',
    'bitterballen', 'bitterbal', 'kapsalon', 'poffertjes', 'oliebollen',
    'stroopwafel', 'stroopwafels', 'hagelslag', 'frikandel', 'kibbeling',
    'kruidnoten', 'speculaas', 'tompouce',
    'ontbijtkoek', 'bami goreng', 'nasi goreng', 'bami', 'saté', 'babi pangang',
    'waterzooi', 'stoofvlees', 'hachee', 'bossche bol',
    // Polish
    'pierogi', 'pierogi ruskie', 'bigos', 'żurek', 'zurek', 'gołąbki',
    'golabki', 'kotlet schabowy', 'schabowy', 'pierniki', 'piernik', 'barszcz',
    'rosół', 'kopytka', 'kluski śląskie', 'oscypek', 'kiełbasa', 'kielbasa',
    'mizeria', 'pączki', 'paczki', 'zapiekanka', 'flaki', 'chłodnik',
    'krupnik', 'łazanki', 'racuchy',
    // German / Austrian
    'sauerbraten', 'spätzle', 'spaetzle', 'käsespätzle', 'kasespatzle',
    'currywurst', 'schnitzel', 'wiener schnitzel', 'jägerschnitzel',
    'bratwurst', 'weißwurst', 'weisswurst',
    'strudel', 'apfelstrudel', 'knödel', 'semmelknödel',
    'rouladen', 'maultaschen', 'flammkuchen', 'eisbein', 'leberkäse',
    'stollen', 'lebkuchen', 'kaiserschmarrn', 'schwarzwälder kirschtorte',
    'bienenstich', 'labskaus', 'frikadellen',
    // Spanish / Portuguese / Latin American
    'paella', 'gazpacho', 'tortilla española', 'tortilla espanola',
    'tortilla de patatas', 'churros', 'chorizo', 'tapas', 'patatas bravas',
    'croquetas', 'salmorejo', 'empanada', 'empanadas', 'fabada', 'pisto',
    'sangria', 'pastel de nata', 'pasteis de nata', 'ceviche', 'arepas',
    'feijoada',
    // Mexican / Tex-Mex
    'taco', 'tacos', 'burrito', 'burritos', 'quesadilla', 'quesadillas',
    'enchilada', 'enchiladas', 'fajita', 'fajitas', 'nachos', 'guacamole',
    'chili con carne', 'chili sin carne', 'tamales', 'pozole', 'mole',
    'pico de gallo', 'huevos rancheros', 'elote',
    // Italian
    'risotto', 'lasagne', 'lasagna', 'gnocchi', 'carbonara', 'bolognese',
    'pesto', 'bruschetta', 'focaccia', 'ciabatta', 'tiramisu', 'tiramisù',
    'minestrone', 'panna cotta', 'ravioli', 'tortellini', 'cannelloni',
    'caprese', 'arancini', 'polenta', 'calzone', 'frittata', 'panzanella',
    'saltimbocca', 'ossobuco', 'carpaccio', 'antipasti', 'antipasto',
    'cacio e pepe', 'aglio e olio', 'puttanesca', 'arrabbiata', 'parmigiana',
    'piccata', 'gremolata', 'orzotto', 'pizza', 'margherita', 'stracciatella',
    'affogato', 'burrata',
    // French
    'ratatouille', 'quiche', 'quiche lorraine', 'croissant', 'croissants',
    'crêpe', 'crêpes', 'crepes', 'bouillabaisse', 'coq au vin',
    'croque monsieur', 'croque madame', 'gratin dauphinois', 'soufflé',
    'souffle', 'pot-au-feu', 'cassoulet', 'tarte tatin', 'niçoise', 'nicoise',
    'boeuf bourguignon', 'bœuf bourguignon', 'clafoutis', 'madeleines',
    'éclair', 'eclairs', 'profiteroles', 'brioche', 'galette', 'vichyssoise',
    'béarnaise', 'hollandaise', 'velouté',
    // Greek / Turkish / Middle Eastern / North African
    'hummus', 'houmous', 'falafel', 'shakshuka', 'shakshouka', 'tzatziki',
    'tabbouleh', 'tabouleh', 'baba ganoush', 'baba ghanoush', 'shawarma',
    'kebab', 'kebabs', 'döner', 'doner', 'köfte', 'kofta', 'couscous',
    'moussaka', 'souvlaki', 'gyros', 'spanakopita', 'dolma', 'dolmades',
    'halloumi', 'labneh', 'za\'atar', 'zaatar', 'harissa', 'tahini',
    'tagine', 'tajine', 'fattoush', 'baklava', 'manakish', 'mezze', 'meze',
    'lahmacun', 'pide', 'börek', 'borek', 'muhammara', 'mujadara', 'kibbeh',
    'chermoula', 'dukkah',
    // East / South-East / South Asian
    'sushi', 'sashimi', 'onigiri', 'ramen', 'pho', 'phở', 'kimchi',
    'curry', 'pad thai', 'tom yum', 'tom kha', 'bibimbap', 'bulgogi',
    'teriyaki', 'tempura', 'miso', 'udon', 'soba', 'gyoza', 'dim sum', 'bao',
    'katsu', 'tonkatsu', 'yakitori', 'okonomiyaki', 'donburi', 'tikka masala',
    'tikka', 'korma', 'vindaloo', 'jalfrezi', 'madras', 'rogan josh', 'dal',
    'dahl', 'daal', 'biryani', 'samosa', 'samosas', 'naan', 'pakora',
    'pakoras', 'bhaji', 'bhajis', 'raita', 'chana masala', 'saag', 'paneer',
    'tandoori', 'satay', 'laksa', 'rendang', 'gado gado', 'gado-gado',
    'banh mi', 'bánh mì', 'poké', 'poke bowl', 'edamame', 'tteokbokki',
    'japchae',
    'char siu', 'chow mein', 'lo mein', 'kung pao', 'mapo tofu', 'wonton',
    'wontons', 'congee', 'nasi lemak', 'massaman', 'panang', 'larb',
    // Other well-known dishes
    'goulash', 'borscht', 'smørrebrød', 'gravlax', 'gravad lax', 'pierogies',
    'shashlik', 'pelmeni', 'blini', 'khachapuri',
    'açaí', 'acai',
    'pavlova',
    'shakshuka', 'chimichurri', 'aioli', 'sriracha', 'gochujang',
  ];

  static final List<String> _sortedTerms = () {
    final seen = <String>{};
    final unique = <String>[
      for (final t in protectedTerms)
        if (seen.add(t.toLowerCase())) t.toLowerCase(),
    ];
    unique.sort((a, b) => b.length.compareTo(a.length));
    return unique;
  }();

  static final RegExp _termPattern = RegExp(
    '(?<![\\p{L}\\p{N}])(?:${_sortedTerms.map(RegExp.escape).join('|')})(?![\\p{L}\\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _tokenPattern = RegExp(r'⟦\s*(\d+)\s*⟧');
  static final RegExp _letters = RegExp(r'\p{L}', unicode: true);
  static final RegExp _trailingPunct =
      RegExp(r'^[\s\p{P}\p{S}]+|[\s\p{P}\p{S}]+$', unicode: true);

  static String token(int index) => '⟦$index⟧';

  /// True when [text] consists only of protected terms (plus whitespace and
  /// punctuation), e.g. "Pierogi" or "Hummus" — it is shown unchanged.
  static bool isEntirelyProtected(String text) {
    final trimmed = text.replaceAll(_trailingPunct, '');
    if (trimmed.isEmpty) return false;
    final rest = trimmed.replaceAll(_termPattern, '');
    return rest != trimmed && !_letters.hasMatch(rest);
  }

  /// Whether [text] contains anything a translator could change.
  static bool needsTranslation(String text) =>
      _letters.hasMatch(text) && !isEntirelyProtected(text);

  /// Replace protected terms with placeholder tokens.
  static ProtectedText protect(String text) {
    final terms = <String>[];
    final masked = text.replaceAllMapped(_termPattern, (m) {
      terms.add(m.group(0)!);
      return token(terms.length - 1);
    });
    return ProtectedText(original: text, masked: masked, terms: terms);
  }

  /// Restore placeholder tokens in [translated]. Returns `null` when a token
  /// is missing, duplicated or unknown so the caller can fall back to
  /// translating around the protected terms.
  static String? restore(String translated, List<String> terms) {
    if (terms.isEmpty) {
      return translated.contains('⟦') || translated.contains('⟧')
          ? null
          : translated;
    }
    final counts = List<int>.filled(terms.length, 0);
    var ok = true;
    final restored = translated.replaceAllMapped(_tokenPattern, (m) {
      final i = int.tryParse(m.group(1)!) ?? -1;
      if (i < 0 || i >= terms.length) {
        ok = false;
        return m.group(0)!;
      }
      counts[i]++;
      return terms[i];
    });
    if (!ok || counts.any((c) => c != 1)) return null;
    if (restored.contains('⟦') || restored.contains('⟧')) return null;
    return restored;
  }

  /// Split [text] into alternating translatable / protected segments.
  static List<GlossarySegment> split(String text) {
    final out = <GlossarySegment>[];
    var last = 0;
    for (final m in _termPattern.allMatches(text)) {
      if (m.start > last) {
        out.add(GlossarySegment(text.substring(last, m.start), false));
      }
      out.add(GlossarySegment(m.group(0)!, true));
      last = m.end;
    }
    if (last < text.length) {
      out.add(GlossarySegment(text.substring(last), false));
    }
    return out;
  }

  /// Translate [texts] with [translate] while keeping protected terms intact.
  /// Always returns a list of the same length; any entry that could not be
  /// translated keeps its original text.
  static Future<List<String>> translateAll(
    List<String> texts,
    BatchTranslateFn translate,
  ) async {
    final out = List<String>.from(texts);
    final protectedTexts = <int, ProtectedText>{};
    for (var i = 0; i < texts.length; i++) {
      if (needsTranslation(texts[i])) {
        protectedTexts[i] = protect(texts[i]);
      }
    }
    if (protectedTexts.isEmpty) return out;

    final indices = protectedTexts.keys.toList();
    final firstPass = await _safeTranslate(translate, [
      for (final i in indices) protectedTexts[i]!.masked,
    ]);

    final fallback = <int>[];
    for (var k = 0; k < indices.length; k++) {
      final i = indices[k];
      final p = protectedTexts[i]!;
      final translated = firstPass?[k];
      if (translated == null) continue;
      final restored = restore(translated, p.terms);
      if (restored != null && restored.trim().isNotEmpty) {
        out[i] = restored;
      } else if (p.terms.isNotEmpty) {
        fallback.add(i);
      }
    }
    if (fallback.isEmpty) return out;

    // Fallback: translate only the unprotected pieces, keep terms verbatim.
    final pieces = <String>[];
    final plans = <int, List<GlossarySegment>>{};
    for (final i in fallback) {
      final segments = split(texts[i]);
      plans[i] = segments;
      for (final s in segments) {
        if (!s.isProtected && _letters.hasMatch(s.text)) {
          pieces.add(s.text.trim());
        }
      }
    }
    if (pieces.isEmpty) return out;
    final translatedPieces = await _safeTranslate(translate, pieces);
    if (translatedPieces == null) return out;
    var cursor = 0;
    for (final i in fallback) {
      final buffer = StringBuffer();
      for (final s in plans[i]!) {
        if (!s.isProtected && _letters.hasMatch(s.text)) {
          final piece = translatedPieces[cursor++];
          final lead = RegExp(r'^\s*').firstMatch(s.text)!.group(0)!;
          final trail = RegExp(r'\s*$').firstMatch(s.text)!.group(0)!;
          final clean = piece.contains('⟦') ? s.text.trim() : piece.trim();
          buffer.write('$lead$clean$trail');
        } else {
          buffer.write(s.text);
        }
      }
      out[i] = buffer.toString();
    }
    return out;
  }

  static Future<List<String>?> _safeTranslate(
    BatchTranslateFn translate,
    List<String> texts,
  ) async {
    try {
      final result = await translate(texts);
      if (result == null || result.length != texts.length) return null;
      return result;
    } catch (_) {
      return null;
    }
  }
}

class ProtectedText {
  const ProtectedText({
    required this.original,
    required this.masked,
    required this.terms,
  });

  final String original;
  final String masked;
  final List<String> terms;
}

class GlossarySegment {
  const GlossarySegment(this.text, this.isProtected);

  final String text;
  final bool isProtected;
}
