/// Serving size option for a countable food (e.g., small/medium/large banana).
class ServingOption {
  final String label;
  final double gramsPerUnit;

  const ServingOption(this.label, this.gramsPerUnit);
}

/// Serving configuration for foods that are naturally counted (pieces, slices).
class ServingConfig {
  final String countLabel;        // e.g., "How many bananas?"
  final String sizeLabel;         // e.g., "Select size"
  final List<ServingOption> sizes;

  const ServingConfig({
    required this.countLabel,
    required this.sizeLabel,
    required this.sizes,
  });

  /// Total grams for [count] items of the selected [size].
  double totalGrams(int count, ServingOption size) => count * size.gramsPerUnit;
}

/// Pre-defined serving configs for common countable foods.
/// Keys are lowercase food labels matching the database.
const Map<String, ServingConfig> servingConfigs = {
  // ── Fruits ──────────────────────────────────────────────────────────────
  'banana': ServingConfig(
    countLabel: 'How many bananas?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~100g)', 100),
      ServingOption('Medium (~120g)', 120),
      ServingOption('Large (~140g)', 140),
    ],
  ),
  'apple': ServingConfig(
    countLabel: 'How many apples?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~150g)', 150),
      ServingOption('Medium (~180g)', 180),
      ServingOption('Large (~220g)', 220),
    ],
  ),
  'orange': ServingConfig(
    countLabel: 'How many oranges?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~100g)', 100),
      ServingOption('Medium (~130g)', 130),
      ServingOption('Large (~185g)', 185),
    ],
  ),
  'peach': ServingConfig(
    countLabel: 'How many peaches?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~130g)', 130),
      ServingOption('Medium (~150g)', 150),
      ServingOption('Large (~175g)', 175),
    ],
  ),
  'pear': ServingConfig(
    countLabel: 'How many pears?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~150g)', 150),
      ServingOption('Medium (~180g)', 180),
      ServingOption('Large (~210g)', 210),
    ],
  ),
  'kiwi': ServingConfig(
    countLabel: 'How many kiwis?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~60g)', 60),
      ServingOption('Medium (~75g)', 75),
      ServingOption('Large (~90g)', 90),
    ],
  ),
  'egg': ServingConfig(
    countLabel: 'How many eggs?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~45g)', 45),
      ServingOption('Medium (~55g)', 55),
      ServingOption('Large (~65g)', 65),
    ],
  ),
  'mango': ServingConfig(
    countLabel: 'How many mangos?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~200g)', 200),
      ServingOption('Medium (~300g)', 300),
      ServingOption('Large (~400g)', 400),
    ],
  ),
  'avocado': ServingConfig(
    countLabel: 'How many avocados?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~100g)', 100),
      ServingOption('Medium (~150g)', 150),
      ServingOption('Large (~200g)', 200),
    ],
  ),

  // ── Bread & baked ───────────────────────────────────────────────────────
  'bread': ServingConfig(
    countLabel: 'How many slices?',
    sizeLabel: 'Select type',
    sizes: [
      ServingOption('White bread (~30g/slice)', 30),
      ServingOption('Brown/wheat bread (~35g/slice)', 35),
      ServingOption('Dark/rye bread (~40g/slice)', 40),
    ],
  ),
  'Pita Bread': ServingConfig(
    countLabel: 'How many pitas?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~30g)', 30),
      ServingOption('Medium/regular (~60g)', 60),
      ServingOption('Large (~90g)', 90),
    ],
  ),
  'Tortilla': ServingConfig(
    countLabel: 'How many tortillas?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small 6" (~30g)', 30),
      ServingOption('Medium 8" (~45g)', 45),
      ServingOption('Large 10" (~65g)', 65),
    ],
  ),
  'Bagel': ServingConfig(
    countLabel: 'How many bagels?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Mini (~55g)', 55),
      ServingOption('Regular (~90g)', 90),
      ServingOption('Large (~110g)', 110),
    ],
  ),
  'Croissant': ServingConfig(
    countLabel: 'How many croissants?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Mini (~30g)', 30),
      ServingOption('Regular (~55g)', 55),
      ServingOption('Large (~75g)', 75),
    ],
  ),
  'Pancake': ServingConfig(
    countLabel: 'How many pancakes?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small 4" (~35g)', 35),
      ServingOption('Medium 6" (~55g)', 55),
      ServingOption('Large 8" (~75g)', 75),
    ],
  ),

  // ── Snacks & sweets ────────────────────────────────────────────────────
  'Cookie': ServingConfig(
    countLabel: 'How many cookies?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~20g)', 20),
      ServingOption('Medium (~35g)', 35),
      ServingOption('Large (~50g)', 50),
    ],
  ),
  'Donut': ServingConfig(
    countLabel: 'How many donuts?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Mini (~25g)', 25),
      ServingOption('Regular (~60g)', 60),
      ServingOption('Large (~85g)', 85),
    ],
  ),
  'Muffin': ServingConfig(
    countLabel: 'How many muffins?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Mini (~30g)', 30),
      ServingOption('Regular (~60g)', 60),
      ServingOption('Large (~110g)', 110),
    ],
  ),
  'Meatball': ServingConfig(
    countLabel: 'How many meatballs?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~20g)', 20),
      ServingOption('Medium (~35g)', 35),
      ServingOption('Large (~55g)', 55),
    ],
  ),
  'sausage': ServingConfig(
    countLabel: 'How many sausages?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small/cocktail (~30g)', 30),
      ServingOption('Medium/regular (~75g)', 75),
      ServingOption('Large/bratwurst (~100g)', 100),
    ],
  ),
  'Chicken Wing': ServingConfig(
    countLabel: 'How many wings?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~25g)', 25),
      ServingOption('Medium (~40g)', 40),
      ServingOption('Large (~55g)', 55),
    ],
  ),
  'wonton dumplings': ServingConfig(
    countLabel: 'How many dumplings?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~15g each)', 15),
      ServingOption('Medium (~25g each)', 25),
      ServingOption('Large (~35g each)', 35),
    ],
  ),
  'Gyoza': ServingConfig(
    countLabel: 'How many gyoza?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~20g each)', 20),
      ServingOption('Regular (~30g each)', 30),
    ],
  ),
  'Falafel': ServingConfig(
    countLabel: 'How many falafel?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Small (~20g)', 20),
      ServingOption('Regular (~35g)', 35),
      ServingOption('Large (~50g)', 50),
    ],
  ),
  'Spring Roll': ServingConfig(
    countLabel: 'How many spring rolls?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Mini (~25g)', 25),
      ServingOption('Regular (~50g)', 50),
      ServingOption('Large (~80g)', 80),
    ],
  ),
  'Chicken Nuggets': ServingConfig(
    countLabel: 'How many nuggets?',
    sizeLabel: 'Select size',
    sizes: [
      ServingOption('Regular (~18g each)', 18),
    ],
  ),
};

/// Look up the serving config for a food label (case-insensitive).
ServingConfig? getServingConfig(String foodLabel) {
  // Exact match first.
  if (servingConfigs.containsKey(foodLabel)) return servingConfigs[foodLabel];
  // Case-insensitive fallback.
  final lower = foodLabel.toLowerCase();
  for (final entry in servingConfigs.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}
