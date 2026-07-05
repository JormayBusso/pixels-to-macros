/// The core food groups the app gives daily/weekly balance recommendations for
/// (fruit, vegetables, protein, dairy, grains). Drinks, snacks, sweets, sauces
/// and other categories are intentionally not tracked as a "serving" group.
enum FoodGroup { fruit, vegetables, protein, dairy, grains }

/// Grams that count as roughly one serving of each group (EFSA / WHO-style
/// portion sizes). Used to convert logged weight into servings.
const Map<FoodGroup, double> kServingGrams = {
  FoodGroup.fruit: 80,
  FoodGroup.vegetables: 80,
  FoodGroup.protein: 100,
  FoodGroup.dairy: 200,
  FoodGroup.grains: 60,
};

/// Recommended servings per day for each group (general healthy-eating
/// guidance — not personalised medical advice).
const Map<FoodGroup, double> kRecommendedDailyServings = {
  FoodGroup.fruit: 2,
  FoodGroup.vegetables: 3,
  FoodGroup.protein: 2,
  FoodGroup.dairy: 2.5,
  FoodGroup.grains: 4,
};

/// Maps a [FoodData.category] (and, as a fallback, a food [label]) to a tracked
/// [FoodGroup], or null when the food is not part of a recommended group
/// (drinks, snacks, sweets, sauces, oils, mixed dishes, …).
FoodGroup? foodGroupForCategory(String category, [String label = '']) {
  switch (category.toLowerCase().trim()) {
    case 'fruit':
      return FoodGroup.fruit;
    case 'vegetable':
    case 'veg':
    case 'vegetables':
      return FoodGroup.vegetables;
    case 'dairy':
      return FoodGroup.dairy;
    case 'grain':
    case 'grains':
    case 'cereal':
    case 'bread':
    case 'pasta':
    case 'rice':
    case 'starch':
      return FoodGroup.grains;
    case 'protein':
    case 'meat':
    case 'poultry':
    case 'fish':
    case 'seafood':
    case 'egg':
    case 'eggs':
    case 'legume':
    case 'legumes':
    case 'nut':
    case 'nuts':
      return FoodGroup.protein;
    default:
      return null;
  }
}
