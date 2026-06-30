/// Turns raw recipe ingredients into a realistic shopping list.
///
/// Two problems this solves:
///  1. Recipe ingredient names are freeform, multilingual phrases
///     ("milde olijfolie", "fein gehackte Zwiebel", "small ripe avocados,
///     sliced"). We strip preparation / descriptor words across EN/NL/DE/PL so
///     only the shoppable item remains.
///  2. You cannot buy a partial unit — you don't buy "1 egg", you buy a box of
///     10; you don't buy "230 g flour", you buy a 1 kg bag. Required amounts
///     therefore round UP to whole purchasable packages.
///
/// Everything here is pure and synchronous so it can be unit-tested in
/// isolation and reused by the meal-planner grocery generator.
library;

/// A canonical, language-independent staple identifier.
enum Staple {
  eggs,
  garlic,
  onion,
  tomato,
  lemon,
  cucumber,
  milk,
  butter,
  flour,
  sugar,
  oil,
  salt,
  pepper,
}

/// How a staple is purchased.
///
/// * [gramsPerPiece] > 0  → sold by the piece (eggs, tomatoes, lemons…). The
///   needed grams convert to whole pieces, then round up to [packPieces].
/// * [gramsPerPiece] == 0 → sold by weight/volume in a fixed [packGrams] pack
///   (flour 1 kg, milk 1 L…). Needed grams round up to whole packs.
/// * [pantryStaple] items (salt, pepper) are assumed already owned and are
///   omitted from the list entirely.
class PackRule {
  const PackRule({
    this.gramsPerPiece = 0,
    this.packPieces = 1,
    this.packGrams = 0,
    this.unit = 'g',
    this.pieceUnit = 'pcs',
    this.singularPieceUnit = 'pc',
    this.pantryStaple = false,
  });

  final double gramsPerPiece;
  final int packPieces;
  final double packGrams;
  final String unit;
  final String pieceUnit;
  final String singularPieceUnit;
  final bool pantryStaple;

  bool get countable => gramsPerPiece > 0;
}

/// A finished shopping-list line.
class GroceryLine {
  const GroceryLine({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.totalGrams,
    this.packages = 1,
    this.packaged = false,
  });

  /// Display name (already title-cased / language-appropriate).
  final String name;

  /// Quantity to buy in [unit] (pieces, grams, or millilitres).
  final int quantity;
  final String unit;

  /// The raw summed grams the recipes actually use (for leftover tracking).
  final double totalGrams;

  /// How many whole packages this represents (eggs boxes, flour bags…).
  final int packages;

  /// True when the quantity was rounded up to a whole package.
  final bool packaged;
}

class GroceryPackaging {
  // ── Multilingual descriptor / preparation noise words ──────────────────
  // Stripped from ingredient names so "fein gehackte Zwiebel" → "zwiebel".
  static const Set<String> _noiseEn = {
    'warm', 'cold', 'hot', 'fresh', 'freshly', 'ripe', 'large', 'small',
    'medium', 'big', 'extra', 'organic', 'raw', 'cooked', 'boiled', 'baked',
    'roasted', 'grilled', 'fried', 'toasted', 'chopped', 'sliced', 'diced',
    'minced', 'grated', 'shredded', 'crushed', 'ground', 'peeled', 'halved',
    'quartered', 'cubed', 'crumbled', 'melted', 'softened', 'drained',
    'rinsed', 'dried', 'frozen', 'canned', 'jarred', 'smoked', 'lean',
    'boneless', 'skinless', 'virgin', 'unsalted', 'salted', 'plain', 'whole',
    'light', 'optional', 'taste', 'finely', 'roughly', 'thinly', 'thickly',
    'good', 'quality', 'your', 'favourite', 'favorite', 'some', 'few',
    'little', 'pinch', 'of', 'a', 'an', 'the', 'for', 'and', 'with', 'into',
    'about', 'approximately', 'to', 'or', 'plus', 'pieces', 'piece', 'slices',
    'slice', 'beaten', 'warmed', 'room', 'temperature', 'packed', 'level',
    'heaped',
  };
  static const Set<String> _noiseNl = {
    'milde', 'traditionele', 'verse', 'gemalen', 'gehakte', 'gesnipperde',
    'fijngesneden', 'fijngehakte', 'grof', 'grove', 'geraspte', 'geraspt',
    'gepelde', 'ongezouten', 'gezouten', 'halfvolle', 'volle', 'magere',
    'extra', 'vierge', 'biologische', 'gedroogde', 'gerookte',
    'middelgrote', 'grote', 'kleine', 'rijpe', 'een', 'van', 'met', 'en',
    'of', 'naar', 'smaak', 'snufje', 'optioneel', 'plus', 'in', 'stukjes',
    'reepjes', 'plakjes', 'blokjes', 'partjes',
  };
  static const Set<String> _noiseDe = {
    'fein', 'gehackte', 'gehackt', 'gewürfelte', 'gewürfelt', 'geriebene',
    'gerieben', 'frische', 'frisch', 'getrocknete', 'getrocknet', 'geräucherte',
    'geräuchert', 'gemahlene', 'gemahlen', 'kleine', 'große', 'mittelgroße',
    'reife', 'ungesalzene', 'gesalzene', 'fettarme', 'extra', 'natives',
    'bio', 'eine', 'ein', 'von', 'mit', 'und', 'oder', 'nach', 'geschmack',
    'prise', 'optional', 'in', 'stücke', 'streifen', 'scheiben', 'würfel',
  };
  static const Set<String> _noisePl = {
    'drobno', 'posiekany', 'posiekana', 'posiekane', 'starty', 'starta',
    'starte', 'świeży', 'świeża', 'świeże', 'suszony', 'suszona', 'wędzony',
    'mielony', 'mielona', 'mały', 'mała', 'duży', 'duża', 'średni', 'średnia',
    'dojrzały', 'niesolone', 'solone', 'extra', 'bio', 'z', 'ze', 'i', 'lub',
    'do', 'smaku', 'szczypta', 'opcjonalnie', 'w', 'kostkę', 'plasterki',
    'paski',
  };

  static final Set<String> _noise = {
    ..._noiseEn,
    ..._noiseNl,
    ..._noiseDe,
    ..._noisePl,
  };

  // ── Staple recognition: canonical → substrings (any language) ──────────
  // Matched against the cleaned, lower-cased ingredient core.
  static const Map<Staple, List<String>> _stapleMatchers = {
    Staple.eggs: ['egg', 'ei', 'eier', 'scharrelei', 'jajk', 'jajo', 'jaj'],
    Staple.garlic: ['garlic', 'knoflook', 'knoblauch', 'czosnk'],
    Staple.onion: ['onion', 'ui', 'zwiebel', 'cebul'],
    Staple.tomato: ['tomato', 'tomaat', 'tomate', 'pomidor'],
    Staple.lemon: ['lemon', 'citroen', 'zitrone', 'cytryn'],
    Staple.cucumber: ['cucumber', 'komkommer', 'gurke', 'ogórek', 'ogórk'],
    Staple.milk: ['milk', 'melk', 'milch', 'mleko', 'mleka'],
    Staple.butter: ['butter', 'roomboter', 'boter', 'masło', 'masła'],
    Staple.flour: ['flour', 'bloem', 'mehl', 'mąka', 'mąki', 'tarwebloem'],
    Staple.sugar: ['sugar', 'suiker', 'zucker', 'cukier', 'cukru'],
    Staple.oil: ['oil', 'olie', 'olijfolie', 'öl', 'oliwa', 'oliwy'],
    Staple.salt: ['salt', 'zout', 'salz', 'sól', 'soli'],
    Staple.pepper: ['pepper', 'peper', 'pfeffer', 'pieprz'],
  };

  // ── Purchase rules per staple ──────────────────────────────────────────
  static const Map<Staple, PackRule> _rules = {
    Staple.eggs: PackRule(gramsPerPiece: 55, packPieces: 10, unit: 'pcs'),
    Staple.garlic:
        PackRule(gramsPerPiece: 5, packPieces: 1, unit: 'cloves'),
    Staple.onion: PackRule(gramsPerPiece: 110, packPieces: 1, unit: 'pcs'),
    Staple.tomato: PackRule(gramsPerPiece: 100, packPieces: 1, unit: 'pcs'),
    Staple.lemon: PackRule(gramsPerPiece: 100, packPieces: 1, unit: 'pcs'),
    Staple.cucumber: PackRule(gramsPerPiece: 300, packPieces: 1, unit: 'pcs'),
    Staple.milk: PackRule(packGrams: 1000, unit: 'ml'),
    Staple.butter: PackRule(packGrams: 250, unit: 'g'),
    Staple.flour: PackRule(packGrams: 1000, unit: 'g'),
    Staple.sugar: PackRule(packGrams: 1000, unit: 'g'),
    Staple.oil: PackRule(packGrams: 500, unit: 'ml'),
    Staple.salt: PackRule(pantryStaple: true),
    Staple.pepper: PackRule(pantryStaple: true),
  };

  /// Strip descriptor / preparation words and preparation notes, returning a
  /// clean lower-cased ingredient core (e.g. "milde olijfolie" → "olijfolie").
  static String cleanName(String name) {
    // Drop preparation notes after comma / parenthesis / slash / dash.
    final core = name.toLowerCase().split(RegExp(r'[,(/\u2013\u2014]')).first;
    final tokens = core
        // Keep letters (incl. accented) / spaces / hyphens only.
        .replaceAll(RegExp(r'[^a-zà-ÿ\u0100-\u017f\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !_noise.contains(t))
        .toList();
    final cleaned = tokens.join(' ').trim();
    return cleaned.isEmpty ? name.toLowerCase().trim() : cleaned;
  }

  /// Identify the canonical staple for a (raw) ingredient name, or null.
  static Staple? stapleOf(String name) {
    final c = cleanName(name);
    for (final entry in _stapleMatchers.entries) {
      for (final m in entry.value) {
        if (c == m || c.contains(m)) return entry.key;
      }
    }
    return null;
  }

  /// True when the ingredient should never appear on a shopping list because
  /// it's water or a pantry staple everyone already owns (salt, pepper).
  static bool isPantryAssumed(String name) {
    final c = cleanName(name);
    if (c == 'water' || c == 'wasser' || c == 'woda') return true;
    final s = stapleOf(name);
    return s != null && _rules[s]!.pantryStaple;
  }

  /// Convert summed grams for an ingredient into a realistic purchase line,
  /// rounding UP to whole packages. Returns null for trace amounts, water and
  /// assumed pantry staples.
  static GroceryLine? purchaseLine(String displayName, double grams) {
    if (grams < 1 || isPantryAssumed(displayName)) return null;
    final staple = stapleOf(displayName);
    if (staple != null) {
      final rule = _rules[staple]!;
      if (rule.countable) {
        final piecesNeeded = (grams / rule.gramsPerPiece).ceil().clamp(1, 200);
        if (rule.packPieces > 1) {
          final packs = (piecesNeeded / rule.packPieces).ceil();
          final qty = packs * rule.packPieces;
          return GroceryLine(
            name: _title(cleanName(displayName)),
            quantity: qty,
            unit: rule.unit,
            totalGrams: grams,
            packages: packs,
            packaged: true,
          );
        }
        return GroceryLine(
          name: _title(cleanName(displayName)),
          quantity: piecesNeeded,
          unit: piecesNeeded == 1 ? _singular(rule.unit) : rule.unit,
          totalGrams: grams,
        );
      }
      // Weight/volume staple sold in fixed packs → round up to whole packs.
      final packs = (grams / rule.packGrams).ceil().clamp(1, 50);
      return GroceryLine(
        name: _title(cleanName(displayName)),
        quantity: (packs * rule.packGrams).round(),
        unit: rule.unit,
        totalGrams: grams,
        packages: packs,
        packaged: true,
      );
    }
    // Generic item: round grams to a sensible shopping amount.
    int g;
    if (grams < 50) {
      g = (grams / 5).ceil() * 5;
    } else if (grams < 500) {
      g = (grams / 10).ceil() * 10;
    } else {
      g = (grams / 25).ceil() * 25;
    }
    if (g < 1) g = 1;
    return GroceryLine(
      name: _title(cleanName(displayName)),
      quantity: g,
      unit: 'g',
      totalGrams: grams,
    );
  }

  static String _singular(String unit) {
    switch (unit) {
      case 'pcs':
        return 'pc';
      case 'cloves':
        return 'clove';
      default:
        return unit;
    }
  }

  static String _title(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
