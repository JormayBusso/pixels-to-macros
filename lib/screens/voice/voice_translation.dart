/// Multilingual voice food parsing.
///
/// The primary entry point is [parseSpokenFoods], which reads the transcript
/// **directly in the user's language** — recognising localized numbers,
/// fractions, units, connectors and food names natively and resolving each food
/// against a multilingual index. No step round-trips the whole sentence through
/// English (see the parser section at the bottom of this file).
///
/// The older [voiceNormalizeToEnglish] helper (English-pivot token translation)
/// is retained only for reference/tests and is no longer used by the live
/// parsing pipeline.
///
/// IMPORTANT: token tables keep their diacritics (ł, ä, ñ, …) to match the raw
/// transcript; matching is accent-folded internally.
library;

/// Translate a localized spoken phrase to the English tokens the parser
/// understands. Returns the input unchanged for English (or unknown locales).
String voiceNormalizeToEnglish(String text, String langCode) {
  if (langCode == 'en') return text.toLowerCase();
  final dict = _voiceDicts[langCode];
  if (dict == null) return text.toLowerCase();

  final cleaned = text
      .toLowerCase()
      .replaceAll(RegExp(r'[.!?¿¡;:()"]'), ' ')
      .replaceAll(',', ' , ');
  final tokens =
      cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  final out = <String>[];
  var i = 0;
  while (i < tokens.length) {
    var matched = false;
    // Greedily try the longest phrase first (up to 3 words) so multi-word
    // foods like "pommes frites" or fillers like "he comido" are caught.
    for (var n = 3; n >= 1 && !matched; n--) {
      if (i + n > tokens.length) continue;
      final phrase = tokens.sublist(i, i + n).join(' ');
      if (dict.containsKey(phrase)) {
        final rep = dict[phrase]!;
        if (rep.isNotEmpty) out.add(rep);
        i += n;
        matched = true;
      }
    }
    if (!matched) {
      out.add(tokens[i]);
      i++;
    }
  }
  return out.join(' ');
}

// ── Per-language token tables ──────────────────────────────────────────────
// Values are English tokens the existing English pipeline understands:
//  - number words ("two"), fractions ("half", "quarter")
//  - units ("grams", "kg", "ml", "l", "slice", "piece", "cup", "handful",
//    "bowl", "tablespoon", "teaspoon", "serving", "oz", "pound")
//  - connectors ("and", "with", "plus"), articles ("a", "some", "the", "of")
//  - food names matching the English food database labels (lowercased)
// Filler words map to '' so they are dropped from the transcript.

final Map<String, Map<String, String>> _voiceDicts = _buildVoiceDicts();

Map<String, Map<String, String>> _buildVoiceDicts() {
  final result = <String, Map<String, String>>{};
  for (final lang in const ['pl', 'nl', 'es', 'de']) {
    final m = <String, String>{}
      ..addAll(_numbers[lang]!)
      ..addAll(_units[lang]!)
      ..addAll(_connectors[lang]!)
      ..addAll(_articles[lang]!)
      ..addAll(_fillers[lang]!);
    _foodTable.forEach((english, byLang) {
      for (final term in (byLang[lang] ?? const <String>[])) {
        m[term] = english;
      }
    });
    result[lang] = m;
  }
  return result;
}

const Map<String, Map<String, String>> _numbers = {
  'de': {
    'eins': 'one',
    'zwei': 'two',
    'drei': 'three',
    'vier': 'four',
    'fünf': 'five',
    'sechs': 'six',
    'sieben': 'seven',
    'acht': 'eight',
    'neun': 'nine',
    'zehn': 'ten',
    'elf': 'eleven',
    'zwölf': 'twelve',
    'zwanzig': 'twenty',
    'dreißig': 'thirty',
    'hundert': 'hundred',
    'halb': 'half',
    'halbe': 'half',
    'halben': 'half',
    'halbes': 'half',
    'viertel': 'quarter',
  },
  'es': {
    'uno': 'one',
    'dos': 'two',
    'tres': 'three',
    'cuatro': 'four',
    'cinco': 'five',
    'seis': 'six',
    'siete': 'seven',
    'ocho': 'eight',
    'nueve': 'nine',
    'diez': 'ten',
    'once': 'eleven',
    'doce': 'twelve',
    'veinte': 'twenty',
    'treinta': 'thirty',
    'cien': 'hundred',
    'medio': 'half',
    'media': 'half',
    'cuarto': 'quarter',
  },
  'nl': {
    'één': 'one',
    'twee': 'two',
    'drie': 'three',
    'vier': 'four',
    'vijf': 'five',
    'zes': 'six',
    'zeven': 'seven',
    'negen': 'nine',
    'tien': 'ten',
    'elf': 'eleven',
    'twaalf': 'twelve',
    'twintig': 'twenty',
    'dertig': 'thirty',
    'honderd': 'hundred',
    'half': 'half',
    'halve': 'half',
    'kwart': 'quarter',
  },
  'pl': {
    'jeden': 'one',
    'dwa': 'two',
    'dwie': 'two',
    'trzy': 'three',
    'cztery': 'four',
    'pięć': 'five',
    'sześć': 'six',
    'siedem': 'seven',
    'osiem': 'eight',
    'dziewięć': 'nine',
    'dziesięć': 'ten',
    'jedenaście': 'eleven',
    'dwanaście': 'twelve',
    'dwadzieścia': 'twenty',
    'trzydzieści': 'thirty',
    'sto': 'hundred',
    'pół': 'half',
    'połowa': 'half',
    'ćwierć': 'quarter',
  },
};

const Map<String, Map<String, String>> _units = {
  'de': {
    'gramm': 'grams',
    'gramms': 'grams',
    'kilo': 'kg',
    'kilogramm': 'kg',
    'milliliter': 'ml',
    'liter': 'l',
    'scheibe': 'slice',
    'scheiben': 'slice',
    'stück': 'piece',
    'stücke': 'piece',
    'tasse': 'cup',
    'tassen': 'cup',
    'glas': 'cup',
    'handvoll': 'handful',
    'schüssel': 'bowl',
    'teller': 'bowl',
    'esslöffel': 'tablespoon',
    'teelöffel': 'teaspoon',
    'portion': 'serving',
    'portionen': 'serving',
    'unze': 'oz',
    'pfund': 'pound',
  },
  'es': {
    'gramo': 'grams',
    'gramos': 'grams',
    'kilo': 'kg',
    'kilogramo': 'kg',
    'mililitro': 'ml',
    'mililitros': 'ml',
    'litro': 'l',
    'litros': 'l',
    'rebanada': 'slice',
    'rebanadas': 'slice',
    'rodaja': 'slice',
    'rodajas': 'slice',
    'pieza': 'piece',
    'piezas': 'piece',
    'trozo': 'piece',
    'trozos': 'piece',
    'taza': 'cup',
    'tazas': 'cup',
    'vaso': 'cup',
    'puñado': 'handful',
    'tazón': 'bowl',
    'plato': 'bowl',
    'cucharada': 'tablespoon',
    'cucharadita': 'teaspoon',
    'porción': 'serving',
    'onza': 'oz',
    'libra': 'pound',
  },
  'nl': {
    'gram': 'grams',
    'kilo': 'kg',
    'kilogram': 'kg',
    'milliliter': 'ml',
    'liter': 'l',
    'plak': 'slice',
    'plakje': 'slice',
    'plakjes': 'slice',
    'stuk': 'piece',
    'stukje': 'piece',
    'stukjes': 'piece',
    'kopje': 'cup',
    'glas': 'cup',
    'handvol': 'handful',
    'kom': 'bowl',
    'bord': 'bowl',
    'eetlepel': 'tablespoon',
    'theelepel': 'teaspoon',
    'portie': 'serving',
  },
  'pl': {
    'gram': 'grams',
    'gramy': 'grams',
    'gramów': 'grams',
    'kilo': 'kg',
    'kilogram': 'kg',
    'mililitr': 'ml',
    'litr': 'l',
    'plasterek': 'slice',
    'plaster': 'slice',
    'kawałek': 'piece',
    'kawałki': 'piece',
    'filiżanka': 'cup',
    'szklanka': 'cup',
    'kubek': 'cup',
    'garść': 'handful',
    'miska': 'bowl',
    'talerz': 'bowl',
    'łyżka': 'tablespoon',
    'łyżeczka': 'teaspoon',
    'porcja': 'serving',
  },
};

const Map<String, Map<String, String>> _connectors = {
  'de': {'und': 'and', 'mit': 'with', 'plus': 'plus', 'sowie': 'and'},
  'es': {'y': 'and', 'e': 'and', 'con': 'with', 'más': 'plus'},
  'nl': {'en': 'and', 'met': 'with', 'plus': 'plus'},
  'pl': {'i': 'and', 'oraz': 'and', 'z': 'with', 'ze': 'with', 'plus': 'plus'},
};

const Map<String, Map<String, String>> _articles = {
  'de': {
    'ein': 'a',
    'eine': 'a',
    'einen': 'a',
    'einem': 'a',
    'etwas': 'some',
    'der': 'the',
    'die': 'the',
    'das': 'the',
  },
  'es': {
    'un': 'a',
    'una': 'a',
    'unos': 'some',
    'unas': 'some',
    'algo': 'some',
    'de': 'of',
    'del': 'of',
    'el': 'the',
    'la': 'the',
    'los': 'the',
    'las': 'the',
  },
  'nl': {
    'een': 'a',
    'wat': 'some',
    'de': 'the',
    'het': 'the',
    'van': 'of',
  },
  'pl': {
    'trochę': 'some',
    'kilka': 'a few',
    'parę': 'a couple',
  },
};

const Map<String, Map<String, String>> _fillers = {
  'de': {
    'ich': '',
    'habe': '',
    'hatte': '',
    'gegessen': '',
    'esse': '',
    'gerade': '',
    'heute': '',
    'auch': '',
    'dann': '',
    'noch': '',
    'möchte': '',
    'hinzufügen': '',
  },
  'es': {
    'yo': '',
    'he': '',
    'comí': '',
    'comido': '',
    'tomé': '',
    'comer': '',
    'hoy': '',
    'también': '',
    'luego': '',
    'añadir': '',
    'quiero': '',
  },
  'nl': {
    'ik': '',
    'heb': '',
    'gegeten': '',
    'at': '',
    'vandaag': '',
    'ook': '',
    'daarna': '',
    'toevoegen': '',
    'wil': '',
  },
  'pl': {
    'zjadłem': '',
    'zjadłam': '',
    'jadłem': '',
    'jadłam': '',
    'miałem': '',
    'miałam': '',
    'dzisiaj': '',
    'też': '',
    'potem': '',
    'dodać': '',
    'chcę': '',
  },
};

/// English food label → localized synonyms per language. Values must match the
/// English food database labels (compared case-insensitively).
const Map<String, Map<String, List<String>>> _foodTable = {
  // ── Fruit ──
  'apple': {
    'pl': ['jabłko', 'jabłka', 'jabłek'],
    'nl': ['appel', 'appels'],
    'es': ['manzana', 'manzanas'],
    'de': ['apfel', 'äpfel'],
  },
  'banana': {
    'pl': ['banan', 'banany', 'banana'],
    'nl': ['banaan', 'bananen'],
    'es': ['plátano', 'plátanos', 'banana'],
    'de': ['banane', 'bananen'],
  },
  'orange': {
    'pl': ['pomarańcza', 'pomarańcze'],
    'nl': ['sinaasappel', 'sinaasappels'],
    'es': ['naranja', 'naranjas'],
    'de': ['orange', 'orangen', 'apfelsine'],
  },
  'pear': {
    'pl': ['gruszka', 'gruszki'],
    'nl': ['peer', 'peren'],
    'es': ['pera', 'peras'],
    'de': ['birne', 'birnen'],
  },
  'peach': {
    'pl': ['brzoskwinia', 'brzoskwinie'],
    'nl': ['perzik', 'perziken'],
    'es': ['melocotón', 'durazno'],
    'de': ['pfirsich', 'pfirsiche'],
  },
  'grape': {
    'pl': ['winogrono', 'winogrona'],
    'nl': ['druif', 'druiven'],
    'es': ['uva', 'uvas'],
    'de': ['traube', 'trauben', 'weintraube'],
  },
  'strawberry': {
    'pl': ['truskawka', 'truskawki'],
    'nl': ['aardbei', 'aardbeien'],
    'es': ['fresa', 'fresas', 'frutilla'],
    'de': ['erdbeere', 'erdbeeren'],
  },
  'blueberry': {
    'pl': ['borówka', 'borówki', 'jagoda', 'jagody'],
    'nl': ['bosbes', 'bosbessen', 'blauwe bes'],
    'es': ['arándano', 'arándanos'],
    'de': ['blaubeere', 'blaubeeren', 'heidelbeere'],
  },
  'raspberry': {
    'pl': ['malina', 'maliny'],
    'nl': ['framboos', 'frambozen'],
    'es': ['frambuesa', 'frambuesas'],
    'de': ['himbeere', 'himbeeren'],
  },
  'watermelon': {
    'pl': ['arbuz', 'arbuza'],
    'nl': ['watermeloen'],
    'es': ['sandía'],
    'de': ['wassermelone'],
  },
  'melon': {
    'pl': ['melon'],
    'nl': ['meloen'],
    'es': ['melón'],
    'de': ['melone'],
  },
  'pineapple': {
    'pl': ['ananas'],
    'nl': ['ananas'],
    'es': ['piña'],
    'de': ['ananas'],
  },
  'mango': {
    'pl': ['mango'],
    'nl': ['mango'],
    'es': ['mango'],
    'de': ['mango'],
  },
  'lemon': {
    'pl': ['cytryna', 'cytryny'],
    'nl': ['citroen'],
    'es': ['limón', 'limones'],
    'de': ['zitrone', 'zitronen'],
  },
  'kiwi': {
    'pl': ['kiwi'],
    'nl': ['kiwi'],
    'es': ['kiwi'],
    'de': ['kiwi'],
  },
  'cherry': {
    'pl': ['wiśnia', 'wiśnie', 'czereśnia'],
    'nl': ['kers', 'kersen'],
    'es': ['cereza', 'cerezas'],
    'de': ['kirsche', 'kirschen'],
  },
  'plum': {
    'pl': ['śliwka', 'śliwki'],
    'nl': ['pruim', 'pruimen'],
    'es': ['ciruela', 'ciruelas'],
    'de': ['pflaume', 'pflaumen'],
  },
  'apricot': {
    'pl': ['morela', 'morele'],
    'nl': ['abrikoos', 'abrikozen'],
    'es': ['albaricoque', 'damasco'],
    'de': ['aprikose', 'aprikosen'],
  },
  'avocado': {
    'pl': ['awokado'],
    'nl': ['avocado'],
    'es': ['aguacate', 'palta'],
    'de': ['avocado'],
  },
  'pomegranate': {
    'pl': ['granat'],
    'nl': ['granaatappel'],
    'es': ['granada'],
    'de': ['granatapfel'],
  },
  'coconut': {
    'pl': ['kokos'],
    'nl': ['kokosnoot', 'kokos'],
    'es': ['coco'],
    'de': ['kokosnuss', 'kokos'],
  },
  // ── Vegetables ──
  'tomato': {
    'pl': ['pomidor', 'pomidory'],
    'nl': ['tomaat', 'tomaten'],
    'es': ['tomate', 'tomates'],
    'de': ['tomate', 'tomaten'],
  },
  'potato': {
    'pl': ['ziemniak', 'ziemniaki', 'kartofel'],
    'nl': ['aardappel', 'aardappels', 'aardappelen'],
    'es': ['patata', 'patatas', 'papa'],
    'de': ['kartoffel', 'kartoffeln'],
  },
  'sweet potato': {
    'pl': ['batat', 'słodki ziemniak'],
    'nl': ['zoete aardappel'],
    'es': ['batata', 'boniato', 'camote'],
    'de': ['süßkartoffel'],
  },
  'carrot': {
    'pl': ['marchew', 'marchewka', 'marchewki'],
    'nl': ['wortel', 'wortels'],
    'es': ['zanahoria', 'zanahorias'],
    'de': ['karotte', 'karotten', 'möhre', 'möhren'],
  },
  'onion': {
    'pl': ['cebula'],
    'nl': ['ui', 'uien'],
    'es': ['cebolla', 'cebollas'],
    'de': ['zwiebel', 'zwiebeln'],
  },
  'garlic': {
    'pl': ['czosnek'],
    'nl': ['knoflook'],
    'es': ['ajo'],
    'de': ['knoblauch'],
  },
  'cucumber': {
    'pl': ['ogórek', 'ogórki'],
    'nl': ['komkommer'],
    'es': ['pepino'],
    'de': ['gurke', 'gurken'],
  },
  'lettuce': {
    'pl': ['sałata'],
    'nl': ['sla'],
    'es': ['lechuga'],
    'de': ['salat', 'kopfsalat'],
  },
  'spinach': {
    'pl': ['szpinak'],
    'nl': ['spinazie'],
    'es': ['espinaca', 'espinacas'],
    'de': ['spinat'],
  },
  'broccoli': {
    'pl': ['brokuł', 'brokuły'],
    'nl': ['broccoli'],
    'es': ['brócoli'],
    'de': ['brokkoli'],
  },
  'cauliflower': {
    'pl': ['kalafior'],
    'nl': ['bloemkool'],
    'es': ['coliflor'],
    'de': ['blumenkohl'],
  },
  'cabbage': {
    'pl': ['kapusta'],
    'nl': ['kool'],
    'es': ['col', 'repollo'],
    'de': ['kohl'],
  },
  'bell pepper': {
    'pl': ['papryka'],
    'nl': ['paprika'],
    'es': ['pimiento', 'pimientos'],
    'de': ['paprika'],
  },
  'zucchini': {
    'pl': ['cukinia'],
    'nl': ['courgette'],
    'es': ['calabacín'],
    'de': ['zucchini'],
  },
  'eggplant': {
    'pl': ['bakłażan'],
    'nl': ['aubergine'],
    'es': ['berenjena'],
    'de': ['aubergine'],
  },
  'corn': {
    'pl': ['kukurydza'],
    'nl': ['maïs'],
    'es': ['maíz', 'choclo'],
    'de': ['mais'],
  },
  'green peas': {
    'pl': ['groszek', 'groch'],
    'nl': ['erwten', 'doperwten'],
    'es': ['guisantes', 'arvejas'],
    'de': ['erbsen'],
  },
  'green beans': {
    'pl': ['fasolka', 'fasolka szparagowa'],
    'nl': ['sperziebonen'],
    'es': ['judías verdes', 'ejotes'],
    'de': ['grüne bohnen'],
  },
  'pumpkin': {
    'pl': ['dynia'],
    'nl': ['pompoen'],
    'es': ['calabaza'],
    'de': ['kürbis'],
  },
  'mushroom': {
    'pl': ['pieczarka', 'pieczarki', 'grzyby'],
    'nl': ['champignon', 'champignons'],
    'es': ['champiñón', 'champiñones', 'seta'],
    'de': ['pilz', 'pilze', 'champignon'],
  },
  // ── Protein ──
  'chicken': {
    'pl': ['kurczak', 'kurczaka'],
    'nl': ['kip'],
    'es': ['pollo'],
    'de': ['hähnchen', 'huhn'],
  },
  'chicken breast': {
    'pl': ['pierś z kurczaka', 'filet z kurczaka'],
    'nl': ['kipfilet', 'kippenborst'],
    'es': ['pechuga de pollo', 'pechuga'],
    'de': ['hähnchenbrust', 'hühnerbrust'],
  },
  'beef': {
    'pl': ['wołowina'],
    'nl': ['rundvlees', 'rund'],
    'es': ['ternera', 'carne de res'],
    'de': ['rindfleisch', 'rind'],
  },
  'ground beef': {
    'pl': ['mielona', 'mięso mielone'],
    'nl': ['gehakt'],
    'es': ['carne picada', 'carne molida'],
    'de': ['hackfleisch'],
  },
  'steak': {
    'pl': ['stek'],
    'nl': ['biefstuk'],
    'es': ['filete', 'bistec'],
    'de': ['steak'],
  },
  'pork': {
    'pl': ['wieprzowina'],
    'nl': ['varkensvlees'],
    'es': ['cerdo', 'puerco'],
    'de': ['schweinefleisch', 'schwein'],
  },
  'lamb': {
    'pl': ['jagnięcina', 'baranina'],
    'nl': ['lamsvlees', 'lam'],
    'es': ['cordero'],
    'de': ['lammfleisch', 'lamm'],
  },
  'turkey': {
    'pl': ['indyk'],
    'nl': ['kalkoen'],
    'es': ['pavo'],
    'de': ['pute', 'truthahn'],
  },
  'bacon': {
    'pl': ['bekon', 'boczek'],
    'nl': ['spek', 'bacon'],
    'es': ['tocino', 'panceta'],
    'de': ['speck'],
  },
  'ham': {
    'pl': ['szynka'],
    'nl': ['ham'],
    'es': ['jamón'],
    'de': ['schinken'],
  },
  'sausage': {
    'pl': ['kiełbasa', 'parówka', 'parówki'],
    'nl': ['worst', 'worstje'],
    'es': ['salchicha', 'chorizo'],
    'de': ['wurst', 'würstchen'],
  },
  'fish': {
    'pl': ['ryba', 'ryby'],
    'nl': ['vis'],
    'es': ['pescado'],
    'de': ['fisch'],
  },
  'salmon': {
    'pl': ['łosoś'],
    'nl': ['zalm'],
    'es': ['salmón'],
    'de': ['lachs'],
  },
  'tuna': {
    'pl': ['tuńczyk'],
    'nl': ['tonijn'],
    'es': ['atún'],
    'de': ['thunfisch'],
  },
  'shrimp': {
    'pl': ['krewetka', 'krewetki'],
    'nl': ['garnaal', 'garnalen'],
    'es': ['camarón', 'camarones', 'gamba', 'gambas'],
    'de': ['garnele', 'garnelen', 'shrimps'],
  },
  'egg': {
    'pl': ['jajko', 'jajka', 'jaja'],
    'nl': ['ei', 'eieren'],
    'es': ['huevo', 'huevos'],
    'de': ['ei', 'eier'],
  },
  'tofu': {
    'pl': ['tofu'],
    'nl': ['tofu'],
    'es': ['tofu'],
    'de': ['tofu'],
  },
  // ── Grains / carbs ──
  'rice': {
    'pl': ['ryż', 'ryżu'],
    'nl': ['rijst'],
    'es': ['arroz'],
    'de': ['reis'],
  },
  'pasta': {
    'pl': ['makaron', 'makaronu'],
    'nl': ['pasta'],
    'es': ['pasta', 'fideos'],
    'de': ['nudeln', 'pasta'],
  },
  'noodles': {
    'pl': ['kluski'],
    'nl': ['noedels'],
    'es': ['tallarines'],
    'de': ['nudeln'],
  },
  'bread': {
    'pl': ['chleb', 'chleba', 'pieczywo'],
    'nl': ['brood'],
    'es': ['pan'],
    'de': ['brot'],
  },
  'oatmeal': {
    'pl': ['owsianka', 'płatki owsiane'],
    'nl': ['havermout'],
    'es': ['avena'],
    'de': ['haferbrei', 'haferflocken'],
  },
  'quinoa': {
    'pl': ['komosa', 'quinoa'],
    'nl': ['quinoa'],
    'es': ['quinoa', 'quinua'],
    'de': ['quinoa'],
  },
  'cereal': {
    'pl': ['płatki'],
    'nl': ['ontbijtgranen', 'cornflakes'],
    'es': ['cereal', 'cereales'],
    'de': ['müsli', 'cerealien'],
  },
  // ── Dairy ──
  'milk': {
    'pl': ['mleko', 'mleka'],
    'nl': ['melk'],
    'es': ['leche'],
    'de': ['milch'],
  },
  'cheese': {
    'pl': ['ser', 'sera'],
    'nl': ['kaas'],
    'es': ['queso'],
    'de': ['käse'],
  },
  'yogurt': {
    'pl': ['jogurt', 'jogurtu'],
    'nl': ['yoghurt'],
    'es': ['yogur', 'yogurt'],
    'de': ['joghurt'],
  },
  'greek yogurt': {
    'pl': ['jogurt grecki'],
    'nl': ['griekse yoghurt'],
    'es': ['yogur griego'],
    'de': ['griechischer joghurt'],
  },
  'butter': {
    'pl': ['masło', 'masła'],
    'nl': ['boter'],
    'es': ['mantequilla'],
    'de': ['butter'],
  },
  'cottage cheese': {
    'pl': ['twaróg', 'serek wiejski'],
    'nl': ['kwark', 'hüttenkäse'],
    'es': ['requesón'],
    'de': ['hüttenkäse', 'quark'],
  },
  // ── Drinks ──
  'water': {
    'pl': ['woda', 'wody'],
    'nl': ['water'],
    'es': ['agua'],
    'de': ['wasser'],
  },
  'coffee': {
    'pl': ['kawa', 'kawę', 'kawy'],
    'nl': ['koffie'],
    'es': ['café'],
    'de': ['kaffee'],
  },
  'tea': {
    'pl': ['herbata', 'herbatę', 'herbaty'],
    'nl': ['thee'],
    'es': ['té'],
    'de': ['tee'],
  },
  'juice': {
    'pl': ['sok', 'soku'],
    'nl': ['sap', 'vruchtensap'],
    'es': ['jugo', 'zumo'],
    'de': ['saft'],
  },
  'beer': {
    'pl': ['piwo'],
    'nl': ['bier'],
    'es': ['cerveza'],
    'de': ['bier'],
  },
  'wine': {
    'pl': ['wino'],
    'nl': ['wijn'],
    'es': ['vino'],
    'de': ['wein'],
  },
  'smoothie': {
    'pl': ['smoothie', 'koktajl'],
    'nl': ['smoothie'],
    'es': ['batido', 'smoothie'],
    'de': ['smoothie'],
  },
  // ── Dishes / snacks / sweets ──
  'pizza': {
    'pl': ['pizza', 'pizzę'],
    'nl': ['pizza'],
    'es': ['pizza'],
    'de': ['pizza'],
  },
  'hamburg': {
    'pl': ['hamburger', 'burger'],
    'nl': ['hamburger', 'burger'],
    'es': ['hamburguesa'],
    'de': ['hamburger', 'burger'],
  },
  'hot dog': {
    'pl': ['hot dog'],
    'nl': ['hotdog'],
    'es': ['perrito caliente', 'hot dog'],
    'de': ['hotdog'],
  },
  'sandwich': {
    'pl': ['kanapka', 'kanapki'],
    'nl': ['boterham', 'sandwich'],
    'es': ['bocadillo', 'sándwich', 'emparedado'],
    'de': ['sandwich', 'butterbrot'],
  },
  'soup': {
    'pl': ['zupa', 'zupę'],
    'nl': ['soep'],
    'es': ['sopa'],
    'de': ['suppe'],
  },
  'salad': {
    'pl': ['sałatka', 'sałatkę'],
    'nl': ['salade'],
    'es': ['ensalada'],
    'de': ['salat'],
  },
  'french fries': {
    'pl': ['frytki'],
    'nl': ['friet', 'patat', 'frieten'],
    'es': ['patatas fritas', 'papas fritas'],
    'de': ['pommes', 'pommes frites'],
  },
  'sushi': {
    'pl': ['sushi'],
    'nl': ['sushi'],
    'es': ['sushi'],
    'de': ['sushi'],
  },
  'omelette': {
    'pl': ['omlet'],
    'nl': ['omelet'],
    'es': ['tortilla', 'omelette'],
    'de': ['omelett'],
  },
  'pancake': {
    'pl': ['naleśnik', 'naleśniki', 'placek'],
    'nl': ['pannenkoek', 'pannenkoeken'],
    'es': ['panqueque', 'tortita'],
    'de': ['pfannkuchen', 'pfannkuchen'],
  },
  'chocolate': {
    'pl': ['czekolada', 'czekoladę'],
    'nl': ['chocolade', 'chocola'],
    'es': ['chocolate'],
    'de': ['schokolade'],
  },
  'cake': {
    'pl': ['ciasto', 'tort'],
    'nl': ['taart', 'cake'],
    'es': ['pastel', 'torta', 'tarta'],
    'de': ['kuchen', 'torte'],
  },
  'cookie': {
    'pl': ['ciasteczko', 'ciasteczka'],
    'nl': ['koekje', 'koekjes'],
    'es': ['galleta', 'galletas'],
    'de': ['keks', 'kekse', 'plätzchen'],
  },
  'ice cream': {
    'pl': ['lody'],
    'nl': ['ijs', 'roomijs'],
    'es': ['helado'],
    'de': ['eis', 'eiscreme'],
  },
  'candy': {
    'pl': ['cukierek', 'cukierki', 'słodycze'],
    'nl': ['snoep', 'snoepje'],
    'es': ['caramelo', 'dulce', 'dulces'],
    'de': ['bonbon', 'süßigkeiten'],
  },
  'honey': {
    'pl': ['miód'],
    'nl': ['honing'],
    'es': ['miel'],
    'de': ['honig'],
  },
  'sugar': {
    'pl': ['cukier', 'cukru'],
    'nl': ['suiker'],
    'es': ['azúcar'],
    'de': ['zucker'],
  },
  'mixed nuts': {
    'pl': ['orzechy', 'orzeszki'],
    'nl': ['noten', 'gemengde noten'],
    'es': ['nueces', 'frutos secos'],
    'de': ['nüsse', 'gemischte nüsse'],
  },
  'almond': {
    'pl': ['migdał', 'migdały'],
    'nl': ['amandel', 'amandelen'],
    'es': ['almendra', 'almendras'],
    'de': ['mandel', 'mandeln'],
  },
  'walnut': {
    'pl': ['orzech włoski', 'orzechy włoskie'],
    'nl': ['walnoot', 'walnoten'],
    'es': ['nuez', 'nueces de nogal'],
    'de': ['walnuss', 'walnüsse'],
  },
  'peanut': {
    'pl': ['orzeszki ziemne', 'fistaszki'],
    'nl': ['pinda', 'pinda\'s'],
    'es': ['cacahuete', 'cacahuetes', 'maní'],
    'de': ['erdnuss', 'erdnüsse'],
  },
  'peanut butter': {
    'pl': ['masło orzechowe'],
    'nl': ['pindakaas'],
    'es': ['mantequilla de maní', 'crema de cacahuete'],
    'de': ['erdnussbutter'],
  },
  'raisins': {
    'pl': ['rodzynki'],
    'nl': ['rozijnen'],
    'es': ['pasas'],
    'de': ['rosinen'],
  },
  'olive oil': {
    'pl': ['oliwa', 'oliwa z oliwek'],
    'nl': ['olijfolie'],
    'es': ['aceite de oliva'],
    'de': ['olivenöl'],
  },
};

// ════════════════════════════════════════════════════════════════════════════
// TRUE PER-LANGUAGE SPOKEN-FOOD PARSER (no English pivot)
//
// `parseSpokenFoods` reads the transcript directly in the user's language. It
// recognises localized numbers, fractions, units, connectors and filler words
// natively, and resolves each food phrase against a multilingual food index
// (built by inverting `_foodTable`) using accent-folded, inflection-tolerant
// matching. The result is a list of `SpokenItem`s: each carries either an
// explicit weight (grams) or a spoken piece count, plus a `foodQuery` that is
// the canonical English DB label when the food was recognised, or the cleaned
// native phrase when it wasn't (so the caller can still fuzzy-match / surface
// it). No step round-trips the whole sentence through English.
// ════════════════════════════════════════════════════════════════════════════

/// One parsed spoken food. [grams] is set when the speaker gave a weight or
/// volume; [pieceCount] is set when they gave a count ("two apples", "a
/// banana") and should be multiplied by the matched food's typical piece
/// weight by the caller. [resolved] is true when [foodQuery] is a canonical
/// English DB label resolved from the multilingual index.
class SpokenItem {
  final String foodQuery;
  final double? grams;
  final double? pieceCount;
  final bool resolved;
  const SpokenItem({
    required this.foodQuery,
    this.grams,
    this.pieceCount,
    required this.resolved,
  });
}

/// English canonical number-word → value. Localized number words are mapped to
/// these canonical words by `_numbers[lang]`, so this table closes the loop for
/// every language (and is used directly for English).
const Map<String, double> _enNumberValues = {
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'twenty': 20,
  'thirty': 30,
  'hundred': 100,
  'half': 0.5,
  'quarter': 0.25,
};

/// English canonical unit → grams per unit. Count-style units (piece/serving)
/// live in [_countUnits] instead and are returned as a piece count.
const Map<String, double> _enUnitGrams = {
  'grams': 1,
  'kg': 1000,
  'ml': 1,
  'l': 1000,
  'slice': 30,
  'cup': 240,
  'handful': 30,
  'bowl': 300,
  'tablespoon': 15,
  'teaspoon': 5,
  'oz': 28.35,
  'pound': 453.6,
};
const Set<String> _countUnits = {'piece', 'serving'};

/// English-side tables so English is parsed by the very same native pipeline
/// (English is just one more language, not a privileged target).
const Map<String, String> _numbersEn = {
  'one': 'one',
  'two': 'two',
  'three': 'three',
  'four': 'four',
  'five': 'five',
  'six': 'six',
  'seven': 'seven',
  'eight': 'eight',
  'nine': 'nine',
  'ten': 'ten',
  'eleven': 'eleven',
  'twelve': 'twelve',
  'twenty': 'twenty',
  'thirty': 'thirty',
  'hundred': 'hundred',
  'half': 'half',
  'quarter': 'quarter',
};
const Map<String, String> _unitsEn = {
  'g': 'grams',
  'gram': 'grams',
  'grams': 'grams',
  'kg': 'kg',
  'kilo': 'kg',
  'kilogram': 'kg',
  'ml': 'ml',
  'milliliter': 'ml',
  'l': 'l',
  'liter': 'l',
  'litre': 'l',
  'slice': 'slice',
  'slices': 'slice',
  'piece': 'piece',
  'pieces': 'piece',
  'cup': 'cup',
  'cups': 'cup',
  'glass': 'cup',
  'handful': 'handful',
  'bowl': 'bowl',
  'plate': 'bowl',
  'tablespoon': 'tablespoon',
  'tbsp': 'tablespoon',
  'teaspoon': 'teaspoon',
  'tsp': 'teaspoon',
  'serving': 'serving',
  'servings': 'serving',
  'oz': 'oz',
  'ounce': 'oz',
  'ounces': 'oz',
  'pound': 'pound',
  'pounds': 'pound',
  'lb': 'pound',
  'lbs': 'pound',
};
const Map<String, String> _connectorsEn = {
  'and': 'and',
  'with': 'with',
  'plus': 'plus',
};
const Map<String, String> _articlesEn = {
  'a': 'a',
  'an': 'a',
  'some': 'some',
  'the': 'the',
  'of': 'of',
};
const Set<String> _fillersEn = {
  'i', 'we', 'just', 'also', 'then', 'today', 'tonight', 'please', //
  'ate', 'eat', 'eaten', 'had', 'have', 'having', 'got', 'consumed', //
  'about', 'around', 'roughly', 'approximately', 'like', 'my', //
};

/// Resolved per-language parse data, built once and cached.
class _LangPack {
  final Map<String, double> numberValue; // localized word -> numeric value
  final Map<String, double?> unitGrams; // localized unit -> grams (null=count)
  final Set<String> connectors; // localized split words
  final Set<String> articleCount; // localized words meaning "a/an" -> 1
  final Set<String> drop; // filler / article words to ignore
  final Map<String, String> foodIndex; // accent-folded localized term -> EN
  const _LangPack({
    required this.numberValue,
    required this.unitGrams,
    required this.connectors,
    required this.articleCount,
    required this.drop,
    required this.foodIndex,
  });
}

final Map<String, _LangPack> _langPackCache = {};

_LangPack _langPack(String lang) {
  return _langPackCache.putIfAbsent(lang, () => _buildLangPack(lang));
}

_LangPack _buildLangPack(String lang) {
  final isEn = lang == 'en';
  final numbers = isEn ? _numbersEn : (_numbers[lang] ?? const {});
  final units = isEn ? _unitsEn : (_units[lang] ?? const {});
  final connectors = isEn ? _connectorsEn : (_connectors[lang] ?? const {});
  final articles = isEn ? _articlesEn : (_articles[lang] ?? const {});
  final fillers =
      isEn ? const <String, String>{} : (_fillers[lang] ?? const {});

  final numberValue = <String, double>{};
  numbers.forEach((local, enWord) {
    final v = _enNumberValues[enWord];
    if (v != null) numberValue[local] = v;
  });

  final unitGrams = <String, double?>{};
  units.forEach((local, enUnit) {
    if (_countUnits.contains(enUnit)) {
      unitGrams[local] = null; // count unit
    } else {
      final g = _enUnitGrams[enUnit];
      if (g != null) unitGrams[local] = g;
    }
  });

  final articleCount = <String>{};
  final drop = <String>{};
  articles.forEach((local, en) {
    if (en == 'a') {
      articleCount.add(local);
    } else {
      drop.add(local); // "some", "the", "of"
    }
  });
  // Filler words (verbs like "comido", "gegessen") are dropped entirely.
  fillers.forEach((local, _) => drop.add(local));
  if (isEn) drop.addAll(_fillersEn);

  // Multilingual food index: every localized synonym (and the English label
  // itself) resolves to the canonical English DB label. Stored accent-folded.
  final foodIndex = <String, String>{};
  _foodTable.forEach((english, byLang) {
    foodIndex[_fold(english)] = english;
    final terms = isEn ? const <String>[] : (byLang[lang] ?? const <String>[]);
    for (final t in terms) {
      foodIndex[_fold(t)] = english;
    }
  });

  return _LangPack(
    numberValue: numberValue,
    unitGrams: unitGrams,
    connectors: connectors.keys.toSet(),
    articleCount: articleCount,
    drop: drop,
    foodIndex: foodIndex,
  );
}

/// Lowercase + strip diacritics so "jabłka"/"plátano"/"Hähnchen" compare
/// cleanly. Polish ł is handled explicitly (it has no NFD decomposition).
String _fold(String s) {
  const map = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', 'ę': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', 'ø': 'o', //
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
    'ñ': 'n', 'ń': 'n', 'ç': 'c', 'ć': 'c', 'ł': 'l', 'ś': 's', //
    'ż': 'z', 'ź': 'z', 'ą': 'a', 'ß': 'ss', //
  };
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final cur = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    cur[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      cur[j + 1] = [cur[j] + 1, prev[j + 1] + 1, prev[j] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j <= b.length; j++) {
      prev[j] = cur[j];
    }
  }
  return prev[b.length];
}

bool _fuzzyEq(String a, String b) {
  if (a == b) return true;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen < 4) return false;
  final d = _levenshtein(a, b);
  // Tolerate one edit for short words, two for longer ones — covers Polish
  // case endings (jabłko/jabłka), Dutch/German plurals (appel/appels).
  return d <= (maxLen >= 7 ? 2 : 1);
}

/// Resolve an accent-folded native food phrase to a canonical English DB label
/// using the multilingual index. Tries the whole phrase, then sliding windows,
/// then inflection-tolerant single-word matching. Returns null when unknown.
String? _resolveFood(List<String> words, _LangPack pack) {
  if (words.isEmpty) return null;
  // Whole phrase, then longest sub-phrases first.
  for (var len = words.length; len >= 1; len--) {
    for (var start = 0; start + len <= words.length; start++) {
      final key = words.sublist(start, start + len).join(' ');
      final hit = pack.foodIndex[key];
      if (hit != null) return hit;
    }
  }
  // Inflection-tolerant single-word matching against every index key.
  for (final w in words) {
    if (w.length < 3) continue;
    for (final entry in pack.foodIndex.entries) {
      if (entry.key.contains(' ')) continue; // single-word keys only here
      if (_fuzzyEq(w, entry.key)) return entry.value;
    }
  }
  return null;
}

/// Parse a spoken transcript in [lang] into structured food items without
/// pivoting through English. See [SpokenItem].
List<SpokenItem> parseSpokenFoods(String text, String lang) {
  final pack = _langPack(lang);

  // Normalise: lowercase, turn most punctuation into spaces, keep commas as
  // explicit separators, normalise decimal commas inside numbers (1,5 -> 1.5).
  var cleaned = text.toLowerCase().replaceAll(RegExp(r'[.!?¿¡;:()"]'), ' ');
  cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  cleaned = cleaned.replaceAll(',', ' , ');
  final raw = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  // Split into segments on connectors and commas.
  final segments = <List<String>>[];
  var current = <String>[];
  for (final tok in raw) {
    if (tok == ',' || pack.connectors.contains(tok)) {
      if (current.isNotEmpty) segments.add(current);
      current = <String>[];
    } else {
      current.add(tok);
    }
  }
  if (current.isNotEmpty) segments.add(current);

  final items = <SpokenItem>[];
  for (final seg in segments) {
    double? qty;
    double? unitGrams; // grams-per-unit when a weight/volume unit was given
    var isCountUnit = false;
    var sawArticle = false;
    final foodWords = <String>[];

    for (var i = 0; i < seg.length; i++) {
      final tok = seg[i];
      final folded = _fold(tok);
      if (pack.drop.contains(tok) || pack.drop.contains(folded)) {
        continue; // filler / "some" / "the" / "of"
      }
      // Number: digit or localized number word. Combine "X and a half"? We keep
      // it simple — a fraction word adds to the running quantity.
      final asDigit = double.tryParse(tok);
      final asWord = pack.numberValue[tok] ?? pack.numberValue[folded];
      if (foodWords.isEmpty && (asDigit != null || asWord != null)) {
        final v = asDigit ?? asWord!;
        qty = (qty == null) ? v : (v < 1 ? qty + v : qty * v);
        continue;
      }
      // Unit token (only meaningful before the food name).
      if (foodWords.isEmpty &&
          (pack.unitGrams.containsKey(tok) ||
              pack.unitGrams.containsKey(folded))) {
        final g = pack.unitGrams.containsKey(tok)
            ? pack.unitGrams[tok]
            : pack.unitGrams[folded];
        if (g == null) {
          isCountUnit = true;
        } else {
          unitGrams = g;
        }
        continue;
      }
      // Article meaning "a/an" → an implicit count of one.
      if (foodWords.isEmpty &&
          (pack.articleCount.contains(tok) ||
              pack.articleCount.contains(folded))) {
        sawArticle = true;
        continue;
      }
      foodWords.add(folded);
    }

    if (foodWords.isEmpty) continue;

    final resolved = _resolveFood(foodWords, pack);
    final query = resolved ?? foodWords.join(' ');

    double? grams;
    double? pieceCount;
    if (unitGrams != null) {
      grams = (qty ?? 1) * unitGrams;
    } else if (isCountUnit) {
      pieceCount = qty ?? 1;
    } else if (qty != null) {
      // Bare number with no unit → a count of pieces.
      pieceCount = qty;
    } else if (sawArticle) {
      pieceCount = 1;
    }

    items.add(SpokenItem(
      foodQuery: query,
      grams: grams,
      pieceCount: pieceCount,
      resolved: resolved != null,
    ));
  }

  // Merge duplicate foods spoken twice ("rice ... and rice").
  if (items.length > 1) {
    final byKey = <String, SpokenItem>{};
    final order = <String>[];
    for (final it in items) {
      final key = it.foodQuery;
      final ex = byKey[key];
      if (ex == null) {
        byKey[key] = it;
        order.add(key);
      } else {
        byKey[key] = SpokenItem(
          foodQuery: key,
          grams: (ex.grams ?? 0) + (it.grams ?? 0) == 0
              ? null
              : (ex.grams ?? 0) + (it.grams ?? 0),
          pieceCount: (ex.pieceCount ?? 0) + (it.pieceCount ?? 0) == 0
              ? null
              : (ex.pieceCount ?? 0) + (it.pieceCount ?? 0),
          resolved: ex.resolved || it.resolved,
        );
      }
    }
    return [for (final k in order) byKey[k]!];
  }
  return items;
}
