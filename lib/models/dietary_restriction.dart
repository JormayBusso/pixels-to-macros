enum DietaryRestriction {
  glutenFree,
  dairyFree,
  nutFree,
}

extension DietaryRestrictionX on DietaryRestriction {
  String get dbValue => name;

  String get label {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Gluten-Free';
      case DietaryRestriction.dairyFree:
        return 'Lactose-Free / Dairy-Free';
      case DietaryRestriction.nutFree:
        return 'Nut-Free';
    }
  }

  String get shortLabel {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Gluten-Free';
      case DietaryRestriction.dairyFree:
        return 'Dairy-Free';
      case DietaryRestriction.nutFree:
        return 'Nut-Free';
    }
  }

  String get description {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Filters wheat, rye, barley, malt, seitan, flour, pasta, bread, and similar gluten sources.';
      case DietaryRestriction.dairyFree:
        return 'Filters milk, lactose, cheese, yogurt, cream, butter, whey, casein, and similar dairy sources.';
      case DietaryRestriction.nutFree:
        return 'Filters tree nuts and peanut ingredients, including nut butters, nut flours, and common nut oils.';
    }
  }

  /// Backwards-compatible flat list of trigger keywords (whole-word, prefix and
  /// phrase forms combined). The authoritative matching logic lives in
  /// [matchesText], which is multilingual and false-positive aware.
  List<String> get triggerTerms {
    final rules = _allergenRules[this]!;
    return <String>[
      ...rules.wholeWord,
      ...rules.prefixes,
      ...rules.phraseTriggers,
    ];
  }

  /// Returns true when [text] (a recipe name + tags + ingredient list) indicates
  /// the food violates this restriction.
  ///
  /// Safety-first design for a health feature:
  ///  * Explicit "free-from" / vegan labelling marks the recipe as safe.
  ///  * Known plant-based alternatives (e.g. "almond milk", "peanut butter")
  ///    are scrubbed so their dairy/gluten-sounding tokens do not trigger.
  ///  * Remaining tokens are matched against whole-word and prefix trigger
  ///    lists covering EN/NL/PL/DE/ES so inflected forms are caught too.
  bool matchesText(String text) {
    final rules = _allergenRules[this]!;
    final lower = text.toLowerCase();

    // 1. Trust explicit "free-from" / vegan labelling.
    for (final label in rules.safeLabels) {
      if (lower.contains(label)) return false;
    }

    // 2. Remove safe plant-based alternatives so their tokens don't trigger.
    var scrubbed = lower;
    for (final phrase in rules.safePhrases) {
      if (scrubbed.contains(phrase)) {
        scrubbed = scrubbed.replaceAll(phrase, ' ');
      }
    }

    // 3. Multi-word substring triggers.
    for (final phrase in rules.phraseTriggers) {
      if (scrubbed.contains(phrase)) return true;
    }

    // 4. Token-level whole-word and prefix matching.
    for (final match in _allergenWordPattern.allMatches(scrubbed)) {
      final word = match.group(0)!;
      if (rules.wholeWord.contains(word)) return true;
      for (final prefix in rules.prefixes) {
        if (word.startsWith(prefix)) return true;
      }
    }
    return false;
  }

  /// True when [text] explicitly advertises this restriction as satisfied
  /// (e.g. a "gluten-free" / "dairy-free" label). Used to *rank* clearly-safe
  /// recipes higher for users with the restriction — never a substitute for the
  /// exclusion done by [matchesText].
  bool isExplicitlyFree(String text) {
    final lower = text.toLowerCase();
    final rules = _allergenRules[this]!;
    for (final label in rules.safeLabels) {
      if (lower.contains(label)) return true;
    }
    return false;
  }

  String alertFor(String itemName) =>
      '$itemName may not fit your $shortLabel setting. Check ingredients and labels before logging it.';

  static DietaryRestriction? fromDbValue(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final restriction in DietaryRestriction.values) {
      if (restriction.dbValue == normalized) return restriction;
    }
    return null;
  }
}

abstract final class DietaryRestrictionCodec {
  static String encode(Set<DietaryRestriction> restrictions) {
    final values = restrictions
        .map((restriction) => restriction.dbValue)
        .toList(growable: false);
    final sorted = values.toList()..sort();
    return sorted.join(',');
  }

  static Set<DietaryRestriction> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <DietaryRestriction>{};
    return raw
        .split(',')
        .map(DietaryRestrictionX.fromDbValue)
        .whereType<DietaryRestriction>()
        .toSet();
  }
}

/// Tokeniser for allergen matching. Includes ASCII plus Latin-1 and
/// Latin-Extended-A accented letters (German ß/ä/ö/ü, Spanish á/í/ñ, Polish
/// ą/ć/ę/ł/ń/ś/ź/ż) so non-English ingredient words stay intact.
final RegExp _allergenWordPattern = RegExp(r'[a-zßà-ÿā-ž]+');

/// Matching rules for a single dietary restriction.
///
/// * [safeLabels]   – substrings that, if present, mark the recipe SAFE
///                    (explicit "free-from" labels, plus "vegan" for dairy).
/// * [safePhrases]  – non-offending phrases scrubbed before matching so their
///                    tokens (e.g. "milk" in "almond milk") don't false-trigger.
/// * [phraseTriggers] – multi-word/substring offenders.
/// * [wholeWord]    – tokens that must match exactly (ambiguous short stems).
/// * [prefixes]     – stems matched against the START of a token (handles
///                    plurals and Polish/German inflection/compounding).
class _AllergenRules {
  const _AllergenRules({
    required this.safeLabels,
    required this.safePhrases,
    required this.phraseTriggers,
    required this.wholeWord,
    required this.prefixes,
  });

  final List<String> safeLabels;
  final List<String> safePhrases;
  final List<String> phraseTriggers;
  final Set<String> wholeWord;
  final List<String> prefixes;
}

const Map<DietaryRestriction, _AllergenRules> _allergenRules = {
  DietaryRestriction.glutenFree: _AllergenRules(
    safeLabels: [
      'gluten-free', 'gluten free', 'glutenfree', 'glutenvrij', 'glutenfrei',
      'sin gluten', 'sans gluten', 'bez glutenu', 'bezglutenow',
    ],
    safePhrases: [
      // Naturally gluten-free flours / starches.
      'almond flour', 'coconut flour', 'rice flour', 'corn flour',
      'chickpea flour', 'gram flour', 'oat flour', 'cassava flour',
      'tapioca flour', 'potato flour', 'buckwheat flour', 'quinoa flour',
      'millet flour', 'sorghum flour', 'teff flour', 'amaranth flour',
      'plantain flour', 'banana flour', 'nut flour', 'soy flour',
      'soya flour', 'almond meal', 'flourless',
      // Naturally gluten-free pasta / noodles / wraps.
      'rice noodle', 'rice noodles', 'glass noodle', 'glass noodles',
      'shirataki', 'kelp noodle', 'rice pasta', 'corn pasta',
      'chickpea pasta', 'lentil pasta', 'red lentil pasta', 'edamame pasta',
      'rice paper', 'corn tortilla', 'corn tortillas',
      // Dutch cookie-spice blend (no grain).
      'koekkruiden',
      // Naturally gluten-free Asian noodles.
      'reisnudel', 'glasnudel', 'reisbandnudel',
    ],
    phraseTriggers: ['brood', 'deeg', 'nudel', 'pan rallado'],
    wholeWord: {'rye', 'brot', 'mehl', 'malt', 'farina', 'bloem'},
    prefixes: [
      // English / international.
      'wheat', 'barley', 'spelt', 'farro', 'bulgur', 'couscous', 'seitan',
      'gluten', 'flour', 'pasta', 'noodle', 'bread', 'breadcrumb', 'cracker',
      'tortilla', 'semolina', 'durum', 'panko', 'orzo', 'ramen', 'udon',
      'brioche', 'croissant', 'bagel', 'naan', 'biscuit', 'pastry', 'pancake',
      'waffle', 'muffin', 'cereal', 'einkorn', 'kamut', 'matzo', 'gnocchi',
      'pretzel', 'crouton', 'dumpling', 'pierogi', 'fusilli', 'penne',
      'spaghetti', 'macaroni', 'lasagn', 'tagliatell', 'fettuccin', 'linguin',
      'vermicell', 'baguette', 'ciabatta', 'focaccia', 'sourdough',
      'triticale', 'freekeh', 'rusk', 'pizza',
      // Dutch.
      'tarwe', 'beschuit', 'paneermeel', 'griesmeel', 'koek', 'pannenkoek',
      'gerst', 'rogge', 'krentenbol', 'stokbrood', 'volkoren', 'boterham',
      'patentbloem', 'bakmeel', 'bloemtortilla',
      // Polish.
      'pszen', 'mąk', 'żyt', 'jęczmie', 'bułk', 'chleb', 'makaron', 'kasz',
      'grzank', 'naleśnik', 'pieróg', 'pierog', 'owsian', 'otręb',
      // German.
      'weizen', 'brötchen', 'semmel', 'teigwaren', 'roggen',
      'dinkel', 'grieß', 'paniermehl', 'vollkorn', 'knödel', 'spätzle',
      'keks', 'gebäck', 'kuchen', 'plätzchen', 'zwieback', 'pumpernickel',
      'brezel',
      // Spanish.
      'trigo', 'harina', 'cebada', 'centeno', 'espelta', 'fideo', 'galleta',
      'sémola', 'bizcocho', 'magdalena', 'empanada',
    ],
  ),
  DietaryRestriction.dairyFree: _AllergenRules(
    safeLabels: [
      'dairy-free', 'dairy free', 'dairyfree', 'lactose-free', 'lactose free',
      'lactosefree', 'non-dairy', 'nondairy', 'lactosevrij', 'laktosefrei',
      'sin lactosa', 'bez laktozy', 'zuivelvrij',
    ],
    safePhrases: [
      // English plant-based milks / creams / butters.
      'coconut milk', 'coconut cream', 'almond milk', 'almond cream',
      'oat milk', 'oat cream', 'soy milk', 'soya milk', 'soy cream',
      'rice milk', 'cashew milk', 'cashew cream', 'hemp milk', 'pea milk',
      'hazelnut milk', 'macadamia milk', 'flax milk', 'peanut butter',
      'sunflower butter', 'seed butter', 'nut butter', 'cocoa butter',
      'shea butter', 'apple butter', 'cream of tartar', 'creme of tartar',
      'vegan butter', 'vegan cheese', 'vegan cream', 'plant butter',
      // Polish.
      'mleko kokosowe', 'mleko migdałowe', 'mleko sojowe', 'mleko owsiane',
      'mleko ryżowe', 'masło orzechowe', 'masło kakaowe', 'masło arachidowe',
      'masło shea', 'masło kokosowe', 'śmietana kokosowa', 'śmietana sojowa',
      // Spanish.
      'leche de coco', 'leche de almendra', 'leche de almendras',
      'leche de soja', 'leche de avena', 'leche de arroz',
      'mantequilla de cacahuete', 'mantequilla de maní', 'manteca de cacao',
      'crema de coco',
      // German / Dutch (space-separated cases).
      'pflanzliche milch', 'plantaardige melk', 'plantaardige boter',
      // Plant-based cheeses / yogurts (so the käse/kaas/joghurt substring
      // triggers below do not false-flag them).
      'pindakaas', 'sojakaas', 'vegan kaas', 'plantaardige kaas',
      'veganer käse', 'vegane käse', 'pflanzlicher käse', 'pflanzenkäse',
      'sojajoghurt', 'kokosjoghurt', 'joghurtalternative',
    ],
    phraseTriggers: ['zure room', 'crème fraîche', 'creme fraiche', 'käse',
        'kaas', 'joghurt', 'jogurt'],
    wholeWord: {'ser', 'curd', 'brie', 'edam', 'butter', 'boter', 'nata',
        'crema', 'vla'},
    prefixes: [
      // English / international.
      'milk', 'lactose', 'cheese', 'yogurt', 'yoghurt', 'cream', 'whey',
      'casein', 'paneer', 'ghee', 'mozzarella', 'parmesan', 'parmigiano',
      'feta', 'ricotta', 'buttermilk', 'cheddar', 'gouda', 'camembert',
      'gruyère', 'gruyere', 'emmental', 'halloumi', 'manchego', 'pecorino',
      'asiago', 'mascarpone', 'burrata', 'provolone', 'gorgonzola',
      'roquefort', 'stilton', 'havarti', 'queso', 'quark', 'kefir', 'custard',
      'gelato', 'milkshake', 'bechamel', 'béchamel', 'labneh', 'skyr', 'dairy',
      // Dutch.
      'melk', 'kaas', 'kwark', 'geitenkaas', 'roomkaas', 'karnemelk',
      'slagroom', 'roomboter', 'kookroom', 'roomijs',
      // Polish.
      'mlek', 'sera', 'serek', 'masł', 'śmietan', 'jogurt', 'twaróg',
      'twarog', 'twarożek', 'maślank',
      // German.
      'milch', 'käse', 'sahne', 'joghurt', 'rahm', 'frischkäse',
      'schlagsahne', 'buttermilch', 'vollmilch', 'magermilch', 'schmand',
      'molke', 'kondensmilch',
      // Spanish.
      'leche', 'mantequilla', 'requesón', 'cuajada',
    ],
  ),
  DietaryRestriction.nutFree: _AllergenRules(
    safeLabels: [
      'nut-free', 'nut free', 'nutfree', 'peanut-free', 'peanut free',
      'notenvrij', 'noten vrij', 'nussfrei', 'sin frutos secos',
      'bez orzechów',
    ],
    safePhrases: [
      'water chestnut', 'water chestnuts', 'tiger nut', 'tiger nuts',
      'nuez moscada', 'muskatnuss', 'kokosnuss', 'nootmuskaat',
    ],
    phraseTriggers: ['mandel', 'nuss', 'nüss'],
    wholeWord: {'nut', 'noot'},
    prefixes: [
      // English / international.
      'almond', 'walnut', 'cashew', 'peanut', 'hazelnut', 'pecan',
      'pistachio', 'macadamia', 'tahini', 'marzipan', 'praline', 'praliné',
      'pralin', 'nougat', 'nutella', 'frangipane', 'gianduja', 'gianduia',
      'pesto', 'satay', 'groundnut', 'pignoli', 'filbert', 'amaretto',
      'amaretti', 'chestnut', 'pinenut',
      // Dutch.
      'amandel', 'pinda', 'walnoot', 'hazelnoot', 'cashewnoot', 'arachide',
      'pistache', 'noten',
      // Polish.
      'orzech', 'orzesz', 'migdał', 'nerkowc', 'pistacj', 'arachidow',
      // German.
      'nuss', 'nüss', 'mandel', 'erdnuss', 'haselnuss', 'walnuss',
      'cashewkern', 'pistazie',
      // Spanish.
      'nuez', 'nuece', 'almendra', 'cacahuete', 'cacahuate', 'maní',
      'avellana', 'pistacho', 'anacardo',
    ],
  ),
};
