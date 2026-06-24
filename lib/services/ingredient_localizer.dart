/// Recipe **ingredient name** localization.
///
/// Recipes are stored in their original source language (English, Polish,
/// Dutch, Spanish, German). This service translates the common base ingredient
/// words to the app's selected language at display time so the ingredient list
/// reads naturally regardless of where the recipe came from.
///
/// Scope and safety:
///   • Only **ingredient** words are translated — never dish/recipe names.
///     Proper names (Paella, Carbonara, Sushi, Tiramisu) are recipe titles and
///     are never passed through here.
///   • Unknown words (quantities, descriptors like "finely chopped", brand
///     names) are passed through unchanged.
///   • If the recipe is already in the target language, the text is returned
///     untouched.
///   • Matching is conservative and word-boundary based, so partial words are
///     never mangled.
class IngredientLocalizer {
  IngredientLocalizer._();

  static const _langIndex = <String, int>{
    'en': 0,
    'pl': 1,
    'nl': 2,
    'es': 3,
    'de': 4,
  };

  /// Canonical English key -> [en, pl, nl, es, de].
  ///
  /// Curated set of the highest-frequency cooking ingredients that appear in
  /// the bundled recipe corpus (bbcgoodfood EN, ah.nl NL, chefkoch DE,
  /// kwestiasmaku PL, hogarmania ES). Multi-word phrases are matched before
  /// single words.
  static const Map<String, List<String>> _table = {
    // Pantry staples
    'water': ['water', 'woda', 'water', 'agua', 'Wasser'],
    'salt': ['salt', 'sól', 'zout', 'sal', 'Salz'],
    'sugar': ['sugar', 'cukier', 'suiker', 'azúcar', 'Zucker'],
    'flour': ['flour', 'mąka', 'bloem', 'harina', 'Mehl'],
    'butter': ['butter', 'masło', 'boter', 'mantequilla', 'Butter'],
    'oil': ['oil', 'olej', 'olie', 'aceite', 'Öl'],
    'olive oil': [
      'olive oil',
      'oliwa z oliwek',
      'olijfolie',
      'aceite de oliva',
      'Olivenöl'
    ],
    'vinegar': ['vinegar', 'ocet', 'azijn', 'vinagre', 'Essig'],
    'honey': ['honey', 'miód', 'honing', 'miel', 'Honig'],
    'yeast': ['yeast', 'drożdże', 'gist', 'levadura', 'Hefe'],
    'baking powder': [
      'baking powder',
      'proszek do pieczenia',
      'bakpoeder',
      'levadura en polvo',
      'Backpulver'
    ],
    'cornflour': [
      'cornflour',
      'mąka kukurydziana',
      'maïzena',
      'maicena',
      'Speisestärke'
    ],
    'breadcrumbs': [
      'breadcrumbs',
      'bułka tarta',
      'paneermeel',
      'pan rallado',
      'Semmelbrösel'
    ],
    'stock': ['stock', 'bulion', 'bouillon', 'caldo', 'Brühe'],
    'soy sauce': [
      'soy sauce',
      'sos sojowy',
      'sojasaus',
      'salsa de soja',
      'Sojasauce'
    ],
    'mustard': ['mustard', 'musztarda', 'mosterd', 'mostaza', 'Senf'],
    'mayonnaise': [
      'mayonnaise',
      'majonez',
      'mayonaise',
      'mayonesa',
      'Mayonnaise'
    ],

    // Dairy & eggs
    'egg': ['egg', 'jajko', 'ei', 'huevo', 'Ei'],
    'eggs': ['eggs', 'jajka', 'eieren', 'huevos', 'Eier'],
    'milk': ['milk', 'mleko', 'melk', 'leche', 'Milch'],
    'cream': ['cream', 'śmietana', 'room', 'nata', 'Sahne'],
    'sour cream': [
      'sour cream',
      'śmietana kwaśna',
      'zure room',
      'crema agria',
      'saure Sahne'
    ],
    'cheese': ['cheese', 'ser', 'kaas', 'queso', 'Käse'],
    'cream cheese': [
      'cream cheese',
      'serek śmietankowy',
      'roomkaas',
      'queso crema',
      'Frischkäse'
    ],
    'mozzarella': [
      'mozzarella',
      'mozzarella',
      'mozzarella',
      'mozzarella',
      'Mozzarella'
    ],
    'parmesan': ['parmesan', 'parmezan', 'parmezaan', 'parmesano', 'Parmesan'],
    'feta': ['feta', 'feta', 'feta', 'feta', 'Feta'],
    'yogurt': ['yogurt', 'jogurt', 'yoghurt', 'yogur', 'Joghurt'],

    // Vegetables
    'onion': ['onion', 'cebula', 'ui', 'cebolla', 'Zwiebel'],
    'garlic': ['garlic', 'czosnek', 'knoflook', 'ajo', 'Knoblauch'],
    'tomato': ['tomato', 'pomidor', 'tomaat', 'tomate', 'Tomate'],
    'potato': ['potato', 'ziemniak', 'aardappel', 'patata', 'Kartoffel'],
    'carrot': ['carrot', 'marchewka', 'wortel', 'zanahoria', 'Karotte'],
    'pepper': ['pepper', 'papryka', 'paprika', 'pimiento', 'Paprika'],
    'bell pepper': [
      'bell pepper',
      'papryka',
      'paprika',
      'pimiento',
      'Paprika'
    ],
    'mushroom': ['mushroom', 'pieczarka', 'champignon', 'champiñón', 'Pilz'],
    'spinach': ['spinach', 'szpinak', 'spinazie', 'espinaca', 'Spinat'],
    'lettuce': ['lettuce', 'sałata', 'sla', 'lechuga', 'Salat'],
    'cucumber': ['cucumber', 'ogórek', 'komkommer', 'pepino', 'Gurke'],
    'broccoli': ['broccoli', 'brokuły', 'broccoli', 'brócoli', 'Brokkoli'],
    'cauliflower': [
      'cauliflower',
      'kalafior',
      'bloemkool',
      'coliflor',
      'Blumenkohl'
    ],
    'zucchini': ['zucchini', 'cukinia', 'courgette', 'calabacín', 'Zucchini'],
    'courgette': ['courgette', 'cukinia', 'courgette', 'calabacín', 'Zucchini'],
    'eggplant': ['eggplant', 'bakłażan', 'aubergine', 'berenjena', 'Aubergine'],
    'celery': ['celery', 'seler', 'selderij', 'apio', 'Sellerie'],
    'leek': ['leek', 'por', 'prei', 'puerro', 'Lauch'],
    'corn': ['corn', 'kukurydza', 'maïs', 'maíz', 'Mais'],
    'peas': ['peas', 'groszek', 'erwten', 'guisantes', 'Erbsen'],
    'beans': ['beans', 'fasola', 'bonen', 'frijoles', 'Bohnen'],
    'lentils': ['lentils', 'soczewica', 'linzen', 'lentejas', 'Linsen'],
    'chickpeas': [
      'chickpeas',
      'ciecierzyca',
      'kikkererwten',
      'garbanzos',
      'Kichererbsen'
    ],
    'ginger': ['ginger', 'imbir', 'gember', 'jengibre', 'Ingwer'],
    'chili': ['chili', 'chili', 'chili', 'chile', 'Chili'],

    // Fruit
    'lemon': ['lemon', 'cytryna', 'citroen', 'limón', 'Zitrone'],
    'lime': ['lime', 'limonka', 'limoen', 'lima', 'Limette'],
    'orange': ['orange', 'pomarańcza', 'sinaasappel', 'naranja', 'Orange'],
    'apple': ['apple', 'jabłko', 'appel', 'manzana', 'Apfel'],
    'banana': ['banana', 'banan', 'banaan', 'plátano', 'Banane'],
    'strawberry': [
      'strawberry',
      'truskawka',
      'aardbei',
      'fresa',
      'Erdbeere'
    ],
    'blueberry': [
      'blueberry',
      'borówka',
      'bosbes',
      'arándano',
      'Heidelbeere'
    ],
    'raspberry': ['raspberry', 'malina', 'framboos', 'frambuesa', 'Himbeere'],
    'avocado': ['avocado', 'awokado', 'avocado', 'aguacate', 'Avocado'],
    'coconut': ['coconut', 'kokos', 'kokos', 'coco', 'Kokosnuss'],
    'raisins': ['raisins', 'rodzynki', 'rozijnen', 'pasas', 'Rosinen'],

    // Meat & fish
    'chicken': ['chicken', 'kurczak', 'kip', 'pollo', 'Hähnchen'],
    'beef': ['beef', 'wołowina', 'rundvlees', 'ternera', 'Rindfleisch'],
    'pork': ['pork', 'wieprzowina', 'varkensvlees', 'cerdo', 'Schweinefleisch'],
    'turkey': ['turkey', 'indyk', 'kalkoen', 'pavo', 'Pute'],
    'bacon': ['bacon', 'boczek', 'spek', 'bacon', 'Speck'],
    'ham': ['ham', 'szynka', 'ham', 'jamón', 'Schinken'],
    'sausage': ['sausage', 'kiełbasa', 'worst', 'salchicha', 'Wurst'],
    'fish': ['fish', 'ryba', 'vis', 'pescado', 'Fisch'],
    'salmon': ['salmon', 'łosoś', 'zalm', 'salmón', 'Lachs'],
    'tuna': ['tuna', 'tuńczyk', 'tonijn', 'atún', 'Thunfisch'],
    'shrimp': ['shrimp', 'krewetki', 'garnalen', 'gambas', 'Garnelen'],

    // Grains
    'rice': ['rice', 'ryż', 'rijst', 'arroz', 'Reis'],
    'pasta': ['pasta', 'makaron', 'pasta', 'pasta', 'Nudeln'],
    'bread': ['bread', 'chleb', 'brood', 'pan', 'Brot'],
    'oats': ['oats', 'płatki owsiane', 'havermout', 'avena', 'Haferflocken'],

    // Herbs & spices
    'basil': ['basil', 'bazylia', 'basilicum', 'albahaca', 'Basilikum'],
    'parsley': ['parsley', 'pietruszka', 'peterselie', 'perejil', 'Petersilie'],
    'coriander': [
      'coriander',
      'kolendra',
      'koriander',
      'cilantro',
      'Koriander'
    ],
    'mint': ['mint', 'mięta', 'munt', 'menta', 'Minze'],
    'thyme': ['thyme', 'tymianek', 'tijm', 'tomillo', 'Thymian'],
    'oregano': ['oregano', 'oregano', 'oregano', 'orégano', 'Oregano'],
    'cinnamon': ['cinnamon', 'cynamon', 'kaneel', 'canela', 'Zimt'],
    'vanilla': ['vanilla', 'wanilia', 'vanille', 'vainilla', 'Vanille'],
    'paprika': ['paprika', 'papryka', 'paprika', 'pimentón', 'Paprika'],
    'cumin': ['cumin', 'kmin', 'komijn', 'comino', 'Kreuzkümmel'],
    'curry': ['curry', 'curry', 'kerrie', 'curry', 'Curry'],

    // Sweet
    'chocolate': [
      'chocolate',
      'czekolada',
      'chocolade',
      'chocolate',
      'Schokolade'
    ],
    'cocoa': ['cocoa', 'kakao', 'cacao', 'cacao', 'Kakao'],
    'almonds': ['almonds', 'migdały', 'amandelen', 'almendras', 'Mandeln'],
    'walnuts': ['walnuts', 'orzechy włoskie', 'walnoten', 'nueces', 'Walnüsse'],
    'peanut butter': [
      'peanut butter',
      'masło orzechowe',
      'pindakaas',
      'mantequilla de cacahuete',
      'Erdnussbutter'
    ],
    'jam': ['jam', 'dżem', 'jam', 'mermelada', 'Marmelade'],
  };

  /// Lazily-built reverse index: localized-lowercased-term -> canonical key.
  static Map<String, String>? _reverse;

  static Map<String, String> get _reverseIndex {
    final existing = _reverse;
    if (existing != null) return existing;
    final map = <String, String>{};
    _table.forEach((key, forms) {
      for (final form in forms) {
        map.putIfAbsent(form.toLowerCase(), () => key);
      }
    });
    _reverse = map;
    return map;
  }

  /// Returns true if [code] is a language this service can translate to.
  static bool supportsLanguage(String code) =>
      _langIndex.containsKey(code.toLowerCase());

  /// Localize a single ingredient [name] to [targetLang].
  ///
  /// [sourceLang] is the recipe's stored language. When source and target
  /// match (or the target is unsupported) the original text is returned.
  static String localize(
    String name, {
    required String targetLang,
    required String sourceLang,
  }) {
    final target = _langIndex[targetLang.toLowerCase()];
    if (target == null) return name;
    if (targetLang.toLowerCase() == sourceLang.toLowerCase()) return name;
    if (name.trim().isEmpty) return name;

    // Dart's String.split discards the matched separators (capturing groups
    // are NOT preserved as in JS), so we split on whitespace, translate, and
    // rejoin with single spaces. Ingredient names use ordinary spacing, so
    // normalising internal whitespace is acceptable.
    final tokens = name.trim().split(RegExp(r'\s+'));
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      // Try a two-word phrase first (e.g. "olive oil", "peanut butter").
      if (i + 1 < tokens.length) {
        final bigram = '${_core(tokens[i])} ${_core(tokens[i + 1])}';
        final key = _reverseIndex[bigram.toLowerCase()];
        if (key != null) {
          final translated = _applyCasing(tokens[i], _table[key]![target]);
          // Carry any trailing punctuation from the second word.
          final trail = RegExp(r'[^\p{L}]+$', unicode: true)
                  .firstMatch(tokens[i + 1])
                  ?.group(0) ??
              '';
          out.add('$translated$trail');
          i += 2;
          continue;
        }
      }

      final core = _core(tokens[i]);
      final key = _reverseIndex[core.toLowerCase()];
      if (key != null) {
        out.add(_reattach(tokens[i], _applyCasing(core, _table[key]![target])));
      } else {
        out.add(tokens[i]);
      }
      i++;
    }
    return out.join(' ');
  }

  /// Strip leading/trailing punctuation for lookup (keeps inner letters).
  static String _core(String word) =>
      word.replaceAll(RegExp(r'^[^\p{L}]+|[^\p{L}]+$', unicode: true), '');

  /// Re-attach the original leading/trailing punctuation around [replacement].
  static String _reattach(String original, String replacement) {
    final lead =
        RegExp(r'^[^\p{L}]+', unicode: true).firstMatch(original)?.group(0) ??
            '';
    final trail =
        RegExp(r'[^\p{L}]+$', unicode: true).firstMatch(original)?.group(0) ??
            '';
    return '$lead$replacement$trail';
  }

  /// Match the capitalization style of [sample] (Title / lower) on [value].
  static String _applyCasing(String sample, String value) {
    final core = _core(sample);
    if (core.isEmpty) return value;
    final isUpperFirst =
        core[0].toUpperCase() == core[0] && core[0].toLowerCase() != core[0];
    if (isUpperFirst && value.isNotEmpty) {
      return value[0].toUpperCase() + value.substring(1);
    }
    return value;
  }
}
