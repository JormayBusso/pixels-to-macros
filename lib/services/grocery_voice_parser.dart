import '../screens/voice/voice_translation.dart';
import 'grocery_food_lexicon.dart';
import 'grocery_text_parser.dart';
import 'pantry_photo_service.dart';

/// Purchase parsing never applies meal portions or fuzzy household matching.
class GroceryVoiceParser {
  GroceryVoiceParser._();

  static List<PantryPhotoCandidate> parse(
      String transcript, String languageCode) {
    final language = languageCode.toLowerCase().split(RegExp('[-_]')).first;
    final purchases =
        parseSpokenFoods(transcript, language, groceryPurchases: true);
    final candidates = GroceryTextParser.sumPurchases([
      for (final purchase in purchases)
        if (purchase.resolved)
          PantryPhotoCandidate(
              GroceryFoodLexicon.match(purchase.foodQuery) ??
                  purchase.foodQuery,
              quantity: purchase.quantity ?? 1,
              unit: purchase.unit),
    ]);
    return [
      for (final candidate in candidates)
        PantryPhotoCandidate(candidate.name,
            quantity: candidate.quantity,
            unit: candidate.unit,
            sourceText: transcript),
    ];
  }
}
