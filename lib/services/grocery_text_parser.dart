import 'dart:math' as math;

import 'grocery_food_lexicon.dart';
import 'pantry_photo_service.dart';

/// One product the on-device language model read from an OCR line.
class GroceryModelItem {
  const GroceryModelItem({required this.line, required this.name});

  /// Index into the OCR lines the item was read from.
  final int line;

  /// Generic English grocery name proposed by the model.
  final String name;
}

/// Turns receipt / packaging OCR text into reviewed-ready food candidates.
///
/// Only foods and drinks are kept. Receipt metadata ("Receipt number",
/// totals, VAT, payment, store, dates, discounts, deposits, bags) and
/// household items are rejected in every supported language, and every
/// result is mapped to a canonical English pantry name.
class GroceryTextParser {
  GroceryTextParser._();

  /// Words that only ever appear on receipt metadata lines.
  static const Set<String> _receiptMetadata = {
    // receipt / invoice
    'receipt', 'receiptnumber', 'kassabon', 'bon', 'bonnummer', 'bonnr',
    'kassenbon', 'kassenzettel', 'beleg', 'belegnummer', 'quittung',
    'ticket', 'tiquet', 'factura', 'facture', 'fattura', 'fatura',
    'invoice', 'faktura', 'paragon', 'fiskalny', 'niefiskalny', 'rachunek',
    'recu', 'scontrino', 'recibo', 'talao', 'copy', 'kopie', 'duplicate',
    'duplicado', 'number', 'nummer', 'numer', 'numero', 'nr', 'no',
    // totals & tax
    'total', 'totaal', 'subtotaal', 'subtotal', 'summe', 'zwischensumme',
    'gesamt', 'gesamtbetrag', 'endbetrag', 'suma', 'razem', 'totale',
    'importe', 'betalen', 'zahlen', 'zaplaty', 'zaplacono', 'pagar',
    'payer', 'pagare', 'tax', 'taxes', 'vat', 'btw', 'mwst', 'ust', 'iva',
    'ptu', 'tva', 'igic', 'netto', 'brutto', 'excl', 'incl', 'inkl',
    // payment
    'cash', 'contant', 'contanten', 'bargeld', 'efectivo', 'gotowka',
    'especes', 'contanti', 'dinheiro', 'numerario', 'card', 'cards',
    'kaart', 'pinnen', 'betaalkaart', 'karte', 'kartenzahlung', 'tarjeta',
    'karta', 'kartka', 'carte', 'carta', 'cartao', 'visa', 'mastercard',
    'maestro', 'amex', 'vpay', 'debit', 'credit', 'contactless',
    'kontaktlos', 'contactloos', 'girocard', 'pin', 'paid', 'payment',
    'betaald', 'betaling', 'bezahlt', 'zahlung', 'gegeben', 'pagado', 'pago',
    'platnosc', 'paiement', 'pagamento', 'change', 'wisselgeld', 'terug',
    'ruckgeld', 'cambio', 'vuelto', 'reszta', 'rendu', 'resto', 'troco',
    'balance', 'saldo', 'tip', 'fooi', 'trinkgeld', 'propina', 'napiwek',
    // store, staff & terminal
    'store', 'shop', 'winkel', 'filiaal', 'filiale', 'tienda', 'sklep',
    'magasin', 'negozio', 'loja', 'kassa', 'kasse', 'caja', 'kasa',
    'checkout', 'till', 'cashier', 'kassier', 'kassiere', 'kassierer',
    'kassiererin', 'kasjer', 'cajero', 'cajera', 'caissier', 'cassiere',
    'operador', 'operator', 'bediener', 'served', 'terminal', 'transaction',
    'transactie', 'transaktion', 'transaccion', 'transakcja', 'trx', 'auth',
    'autorisatie', 'autorisierung', 'merchant', 'tid', 'mid', 'aid', 'ref',
    'referentie', 'referenz', 'referencia', 'tel', 'phone', 'telefon',
    'telefoon', 'telefono', 'fax', 'www', 'http', 'https', 'com', 'iban',
    'bic', 'kvk', 'nip', 'regon', 'cif', 'nif', 'uid', 'steuernummer',
    'contribuinte', 'opening', 'geopend', 'openingstijden', 'offnungszeiten',
    'horario', 'godziny', 'customer', 'klant', 'kunde', 'cliente', 'klient',
    'client', 'member', 'lid',
    // dates / counts / prices
    'date', 'datum', 'fecha', 'data', 'time', 'tijd', 'zeit', 'uhrzeit',
    'hora', 'godzina', 'heure', 'ora', 'qty', 'aantal', 'anzahl',
    'cantidad', 'ilosc', 'quantite', 'quantita', 'quantidade', 'items',
    'artikel', 'artikelen', 'articulos', 'pozycje', 'articles', 'articoli',
    'artigos', 'amount', 'bedrag', 'betrag', 'kwota', 'montant', 'importo',
    'valor', 'price', 'prijs', 'preis', 'precio', 'cena', 'prix', 'prezzo',
    'preco',
    // discounts & loyalty
    'discount', 'korting', 'rabatt', 'rabat', 'descuento', 'remise',
    'sconto', 'desconto', 'coupon', 'kupon', 'gutschein', 'voucher', 'bonus',
    'bonuskaart', 'actie', 'aktion', 'promo', 'promocja', 'promocion',
    'oferta', 'offer', 'savings', 'saved', 'voordeel', 'ersparnis',
    'ahorro', 'oszczednosc', 'economie', 'risparmio', 'poupanca', 'spaar',
    'sparen', 'points', 'punten', 'punkte', 'punkty', 'puntos', 'punti',
    'pontos', 'loyalty', 'payback', 'clubcard', 'zegels',
    // greetings
    'thank', 'thanks', 'bedankt', 'dank', 'danke', 'gracias', 'dziekujemy',
    'merci', 'grazie', 'obrigado', 'welcome', 'welkom', 'willkommen',
    'bienvenido', 'witamy', 'bienvenue', 'benvenuto', 'visit', 'bezoek',
    'besuch', 'visita', 'wizyte',
  };

  /// Words that start the footer: no product appears after them.
  static const Set<String> _totalWords = {
    'total',
    'totaal',
    'summe',
    'gesamt',
    'gesamtbetrag',
    'endbetrag',
    'suma',
    'razem',
    'totale',
    'betalen',
    'zaplaty',
  };

  /// Store chains — only skipped when the line names no food.
  static const Set<String> _storeNames = {
    'lidl',
    'aldi',
    'albert',
    'heijn',
    'jumbo',
    'rewe',
    'edeka',
    'carrefour',
    'tesco',
    'mercadona',
    'biedronka',
    'zabka',
    'auchan',
    'spar',
    'kaufland',
    'penny',
    'netto',
    'dirk',
    'coop',
    'leclerc',
    'intermarche',
    'esselunga',
    'conad',
    'continente',
    'pingo',
    'walmart',
    'costco',
    'sainsbury',
    'sainsburys',
    'asda',
    'morrisons',
    'waitrose',
    'eroski',
    'lewiatan',
    'stokrotka',
    'delhaize',
    'colruyt',
    'migros',
    'billa',
    'hofer',
    'plus',
    'hoogvliet',
    'vomar',
    'dekamarkt',
    'picnic',
    'ekoplaza',
    'monoprix',
    'franprix',
    'eurospar',
    'dino',
    'polomarket',
  };

  static final _letters = RegExp(r'\p{L}', unicode: true);
  static final _date = RegExp(r'\b\d{1,4}[./-]\d{1,2}[./-]\d{2,4}\b');
  static final _clock = RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b');
  static final _percent = RegExp(r'\d\s*%');
  static final _emailAddress = RegExp(
      r'[\p{L}\d._%+-]+\s*@\s*[\p{L}\d.-]+\s*\.\s*\p{L}{2,}',
      unicode: true);
  static final _countUnit = RegExp(
      r'(?:^|\s)(\d{1,2})\s*(?:st|stk|stuk|stuks|stück|stuck|szt|pcs|pc|pz|uds|ud|un|unid)\b\.?',
      caseSensitive: false);
  static final _countTimes =
      RegExp(r'(?:^|\s)(\d{1,2})\s*[x×*]\s*(?=\S)', caseSensitive: false);
  static final _leadingCount = RegExp(
      r'^\s*(\d{1,2})\s+(?!(?:kg|g|ml|l)\b)(?=\p{L})',
      unicode: true,
      caseSensitive: false);
  static final _timesCount =
      RegExp(r'[x×]\s*(\d{1,2})\s*$', caseSensitive: false);
  static final _weighedKg = RegExp(
      r'(\d+[.,]\d{1,3})\s*kg\b(?=.*(?:/\s*kg|[x×*@]))',
      caseSensitive: false);
  static final _packageAmount = RegExp(
      r'(?<![\d.,/])(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l)\b',
      caseSensitive: false);
  static final _multipack = RegExp(
      r'(?:^|\s)(\d{1,2})\s*[x×*]\s*(?=\d+(?:[.,]\d+)?\s*(?:kg|g|ml|l)\b)',
      caseSensitive: false);

  static bool _hasMetadata(List<String> words) {
    for (final word in words) {
      if (_receiptMetadata.contains(word)) return true;
      // German/Dutch compounds: "Gesamtsumme", "Kassenbonnummer".
      if (word.length >= 7) {
        for (final term in _receiptMetadata) {
          if (term.length >= 5 && word.endsWith(term)) return true;
        }
      }
    }
    return false;
  }

  /// True when [line] is receipt metadata rather than a product line.
  static bool isReceiptMetadata(String line) {
    final words = GroceryFoodLexicon.tokens(line);
    if (_hasMetadata(words)) return true;
    if (_emailAddress.hasMatch(line) || line.contains('://')) return true;
    // "BTW 9%" is tax, but "Mleko 2%" / "Vollmilch 3,5%" is a product.
    if (_percent.hasMatch(line) ||
        _date.hasMatch(line) ||
        _clock.hasMatch(line)) {
      return GroceryFoodLexicon.match(line) == null;
    }
    return false;
  }

  static bool _isTotal(String line) =>
      GroceryFoodLexicon.tokens(line).any(_totalWords.contains);

  /// A line holding only a quantity/price ("2 x 1,29", "0,512 kg x 2,49/kg").
  static bool _isBareQuantity(String line) {
    final letters = GroceryFoodLexicon.tokens(line)
        .where((w) => !{
              'x',
              'st',
              'stk',
              'stuk',
              'stuks',
              'stuck',
              'szt',
              'pcs',
              'pc',
              'kg',
              'g',
              'ml',
              'l',
              'eur',
              'euro',
              'zl',
              'pln',
              'usd',
              'gbp',
              'chf',
              'a',
              'b',
              'c',
              'd',
              'e',
              'per',
              'je',
              'por',
              'ud',
              'uds',
              'un',
              'pz',
            }.contains(w))
        .isEmpty;
    return letters && _quantity(line) != null;
  }

  static double? _count(String line) {
    // "4x125g" describes one package, not its receipt purchase count.
    final purchaseText = line.replaceAll(_multipack, ' ');
    for (final pattern in [
      _countUnit,
      _countTimes,
      _timesCount,
      _leadingCount
    ]) {
      final match = pattern.firstMatch(purchaseText);
      final count = match == null ? null : int.tryParse(match.group(1)!);
      if (count != null && count > 0 && count <= 50) {
        return count.toDouble();
      }
    }
    return null;
  }

  /// Explicit package contents multiplied by an explicit purchase count.
  /// Currency, percentages and unit prices never supply a package amount.
  static PantryPhotoCandidate? _quantity(String line) {
    final weighed = _weighedKg.firstMatch(line);
    if (weighed != null && _count(line) == null && !_multipack.hasMatch(line)) {
      final kg = double.tryParse(weighed.group(1)!.replaceAll(',', '.'));
      if (kg != null && kg > 0 && kg <= 25) {
        return PantryPhotoCandidate('', quantity: kg, unit: 'kg');
      }
    }
    final amount = _packageAmount.firstMatch(line);
    if (amount != null) {
      final value = double.tryParse(amount.group(1)!.replaceAll(',', '.'));
      if (value != null && value > 0 && value.isFinite) {
        return PantryPhotoCandidate('',
            quantity: value *
                (double.tryParse(_multipack.firstMatch(line)?.group(1) ?? '') ??
                    1) *
                (_count(line) ?? 1),
            unit: amount.group(2)!.toLowerCase());
      }
    }
    final count = _count(line);
    return count == null ? null : PantryPhotoCandidate('', quantity: count);
  }

  /// Index of the first footer (total) line once a product was seen, so
  /// payment/footer lines are never read as products.
  static int _footerStart(List<String> lines) {
    var sawFood = false;
    for (var i = 0; i < lines.length; i++) {
      if (sawFood && _isTotal(lines[i])) return i;
      if (!isReceiptMetadata(lines[i]) &&
          GroceryFoodLexicon.match(lines[i]) != null) {
        sawFood = true;
      }
    }
    return lines.length;
  }

  /// Parse receipt OCR [lines] into food candidates.
  ///
  /// When [modelItems] (on-device language model output) is given, each is
  /// validated against its source line; lexicon matches fill lines the
  /// model skipped. Without a model, only lexicon-recognised foods are kept.
  static List<PantryPhotoCandidate> parseReceipt(List<String> lines,
      {List<GroceryModelItem>? modelItems}) {
    final end = _footerStart(lines);
    final byLine = <int, String>{};
    if (modelItems != null) {
      for (final item in modelItems) {
        if (item.line < 0 || item.line >= end) continue;
        final source = lines[item.line];
        if (isReceiptMetadata(source) || GroceryFoodLexicon.isNonFood(source)) {
          continue;
        }
        final name = canonicalModelName(item.name);
        if (name == null) continue;
        byLine.putIfAbsent(item.line, () => name);
      }
    }
    for (var i = 0; i < end; i++) {
      if (byLine.containsKey(i) || isReceiptMetadata(lines[i])) continue;
      final food = GroceryFoodLexicon.match(lines[i]);
      if (food != null) byLine[i] = food;
    }

    final candidates = <PantryPhotoCandidate>[];
    final order = byLine.keys.toList()..sort();
    final usedQuantityLines = <int>{};
    for (final i in order) {
      var quantity = _quantity(lines[i]);
      var sourceText = lines[i];
      // Prefer a following quantity row; a preceding row is used only once.
      if (_count(lines[i]) == null) {
        for (final adjacent in [i + 1, i - 1]) {
          if (adjacent < 0 ||
              adjacent >= end ||
              byLine.containsKey(adjacent) ||
              usedQuantityLines.contains(adjacent) ||
              isReceiptMetadata(lines[adjacent]) ||
              !_isBareQuantity(lines[adjacent])) {
            continue;
          }
          final extra = _quantity(lines[adjacent])!;
          if (quantity?.unit != null && extra.unit == null) {
            quantity = PantryPhotoCandidate('',
                quantity: quantity!.quantity * extra.quantity,
                unit: quantity.unit);
          } else if (quantity == null) {
            quantity = extra;
          } else {
            continue;
          }
          usedQuantityLines.add(adjacent);
          sourceText = adjacent > i
              ? '${lines[i]}\n${lines[adjacent]}'
              : '${lines[adjacent]}\n${lines[i]}';
          break;
        }
      }
      candidates.add(PantryPhotoCandidate(byLine[i]!,
          quantity: quantity?.quantity ?? 1,
          unit: quantity?.unit,
          sourceText: sourceText));
    }
    return sumPurchases(candidates);
  }

  /// Separate purchases add up. Compatible metric units are converted to the
  /// first purchase's unit; count/mass/volume conflicts remain separate rows.
  static List<PantryPhotoCandidate> sumPurchases(
      Iterable<PantryPhotoCandidate> items) {
    final merged = <String, PantryPhotoCandidate>{};
    final order = <String>[];
    for (final item in items) {
      if (item.name.trim().isEmpty ||
          !item.quantity.isFinite ||
          item.quantity <= 0) {
        continue;
      }
      final unit = item.unit?.toLowerCase();
      final dimension = switch (unit) {
        'g' || 'kg' => 'mass',
        'ml' || 'l' => 'volume',
        null || '' || 'pcs' => 'count',
        _ => 'unit:$unit',
      };
      final key = '${GroceryFoodLexicon.fold(item.name.trim())}|$dimension';
      final previous = merged[key];
      if (previous == null) {
        order.add(key);
        merged[key] = item;
      } else {
        double factor(String? u) =>
            {'kg', 'l'}.contains(u?.toLowerCase()) ? 1000 : 1;
        final sources = [
          if (previous.sourceText != null) previous.sourceText!,
          if (item.sourceText != null) item.sourceText!,
        ];
        merged[key] = PantryPhotoCandidate(item.name,
            quantity: previous.quantity +
                item.quantity * factor(unit) / factor(previous.unit),
            unit: previous.unit,
            sourceText: sources.isEmpty ? null : sources.join('\n'));
      }
    }
    return [for (final key in order) merged[key]!];
  }

  /// Validate a model-proposed English name; null when it is not a food.
  static String? canonicalModelName(String raw) {
    final name = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.length < 2 || name.length > 48) return null;
    if (!_letters.hasMatch(name)) return null;
    if (GroceryFoodLexicon.isNonFood(name)) return null;
    final words = GroceryFoodLexicon.tokens(name);
    if (_hasMetadata(words)) return null;
    if (words.isNotEmpty && words.every(_storeNames.contains)) return null;
    final known = GroceryFoodLexicon.match(name);
    // Keep the model's more specific name ("Greek yogurt", "Kidney beans")
    // unless it is just a known synonym of a canonical entry.
    if (known != null &&
        GroceryFoodLexicon.index[GroceryFoodLexicon.fold(name)] == known) {
      return known;
    }
    return name[0].toUpperCase() + name.substring(1);
  }

  /// Packaging headers after which text lists ingredients or allergens,
  /// never the product itself.
  static const Set<String> _ingredientHeaders = {
    'ingredients',
    'ingredient',
    'ingredienten',
    'zutaten',
    'ingredientes',
    'skladniki',
    'ingredienti',
    'ingrediente',
    'nutrition',
    'voedingswaarde',
    'voedingswaarden',
    'nahrwerte',
    'nahrwertangaben',
    'nutricional',
    'nutrizionali',
    'odzywcza',
    'nutritionnelle',
    'allergens',
    'allergenen',
    'allergene',
    'alergenos',
    'alergeny',
    'allergeni',
    'contains',
    'bevat',
    'enthalt',
    'contiene',
    'zawiera',
    'contient',
    'contem',
  };

  /// Nutrition-table / storage words: the line is not a product name.
  static const Set<String> _nutritionWords = {
    'spuren',
    'sporen',
    'trazas',
    'traces',
    'tracce',
    'energy',
    'energie',
    'energia',
    'kcal',
    'kj',
    'fat',
    'vet',
    'fett',
    'grasas',
    'tluszcz',
    'matieres',
    'grassi',
    'gordura',
    'carbohydrate',
    'carbohydrates',
    'koolhydraten',
    'kohlenhydrate',
    'hidratos',
    'weglowodany',
    'glucides',
    'carboidrati',
    'eiwit',
    'eiweiss',
    'protein',
    'proteins',
    'proteinas',
    'bialko',
    'proteines',
    'proteine',
    'fibre',
    'fiber',
    'vezels',
    'ballaststoffe',
    'fibra',
    'blonnik',
    'fibres',
    'sugars',
    'suikers',
    'davon',
    'waarvan',
    'wartosc',
    'tenminste',
    'mindestens',
    'consumir',
    'najlepiej',
    'bewaren',
    'lagern',
    'conservar',
    'przechowywac',
    'conserver',
    'conservare',
  };

  static final _wordList = RegExp(r',\s*\p{L}', unicode: true);

  /// Extract product candidates from packaging/fridge-photo OCR [text].
  ///
  /// [aliases] are the app's existing English product aliases; the
  /// multilingual lexicon covers other languages. Ingredient lists and
  /// nutrition tables are skipped until the next blank-line block.
  static List<PantryPhotoCandidate> parsePackaging(
      String text, Map<String, String> aliases) {
    final candidates = <PantryPhotoCandidate>[];
    var skippingSection = false;
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) {
        skippingSection = false;
        continue;
      }
      final words = GroceryFoodLexicon.tokens(line);
      if (words.any(_ingredientHeaders.contains)) {
        skippingSection = true;
        continue;
      }
      // Comma word lists are ingredient lists, never a product name.
      if (_wordList.hasMatch(line) || words.any(_nutritionWords.contains)) {
        continue;
      }
      if (skippingSection ||
          isReceiptMetadata(line) ||
          GroceryFoodLexicon.isNonFood(line)) {
        continue;
      }
      var products = PantryPhotoService.matchProducts(line, aliases);
      if (products.isEmpty) {
        final food = GroceryFoodLexicon.match(line);
        if (food != null) products = [food];
      }
      if (products.isEmpty) continue;
      final prefix = RegExp(
              r'^\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|pcs|x|×)?\s+(.+)$',
              caseSensitive: false)
          .firstMatch(line);
      final suffix = RegExp(r'^(.+?)\s*[x×]\s*(\d+)\s*$', caseSensitive: false)
          .firstMatch(line);
      double quantity = 1;
      String? unit;
      if (products.length == 1 && prefix != null) {
        final rest = prefix.group(3)!;
        final restProducts = PantryPhotoService.matchProducts(rest, aliases);
        if (restProducts.contains(products.single) ||
            GroceryFoodLexicon.match(rest) == products.single) {
          quantity =
              double.tryParse(prefix.group(1)!.replaceAll(',', '.')) ?? 1;
          unit = prefix.group(2)?.toLowerCase();
        }
      } else if (products.length == 1 && suffix != null) {
        quantity = double.tryParse(suffix.group(2)!) ?? 1;
      }
      if ({'pcs', 'x', '×'}.contains(unit)) unit = null;
      for (final product in products) {
        candidates.add(PantryPhotoCandidate(product,
            quantity: math.max(0, quantity), unit: unit));
      }
    }
    return mergePantryCandidates(candidates);
  }

  /// Validate model-proposed packaging products (no line grounding needed
  /// beyond the model being given only this photo's text).
  static List<PantryPhotoCandidate> parsePackagingModel(
      List<GroceryModelItem> items, List<String> lines) {
    final out = <PantryPhotoCandidate>[];
    for (final item in items) {
      if (item.line < 0 || item.line >= lines.length) continue;
      final source = lines[item.line];
      if (GroceryFoodLexicon.isNonFood(source)) continue;
      final name = canonicalModelName(item.name);
      if (name != null) out.add(PantryPhotoCandidate(name));
    }
    return mergePantryCandidates(out);
  }
}
