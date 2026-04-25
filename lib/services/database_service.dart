import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/food_data.dart';
import '../models/grocery_item.dart';
import '../models/ground_truth.dart';
import '../models/scan_benchmark.dart';
import '../models/scan_result.dart';
import '../models/user_preferences.dart';

/// Singleton service wrapping the local SQLite database.
///
/// Tables:
///   • food_data    – reference densities & kcal (seeded on first run)
///   • scan_results – historical scan metadata
///   • detected_foods – per-scan detected items
///   • user_preferences – name, calorie goal, onboarding flag
///   • ground_truth    – actual weighed measurements for evaluation
///   • benchmarks      – per-scan performance timing data
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ── Initialization ────────────────────────────────────────────────────────

  Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, AppConstants.databaseName);

    return openDatabase(
      path,
      version: 13,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // food_data — reference table
    await db.execute('''
      CREATE TABLE food_data (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        label            TEXT    NOT NULL UNIQUE,
        density_min      REAL    NOT NULL,
        density_max      REAL    NOT NULL,
        kcal_per_100g    REAL    NOT NULL,
        category         TEXT    NOT NULL,
        protein_per_100g REAL    NOT NULL DEFAULT 0,
        carbs_per_100g   REAL    NOT NULL DEFAULT 0,
        fat_per_100g     REAL    NOT NULL DEFAULT 0
      )
    ''');

    // scan_results — one row per scan session
    await db.execute('''
      CREATE TABLE scan_results (
        id                    INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp             TEXT    NOT NULL,
        depth_mode            TEXT    NOT NULL,
        top_camera_position   TEXT,
        top_camera_transform  TEXT,
        side_camera_position  TEXT,
        side_camera_transform TEXT
      )
    ''');

    // detected_foods — items found in each scan
    await db.execute('''
      CREATE TABLE detected_foods (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id     INTEGER NOT NULL,
        label       TEXT    NOT NULL,
        volume_cm3  REAL    NOT NULL,
        calories_min REAL   NOT NULL,
        calories_max REAL   NOT NULL,
        FOREIGN KEY (scan_id) REFERENCES scan_results(id)
          ON DELETE CASCADE
      )
    ''');

    // Seed initial food data
    await _seed(db);

    // user_preferences — single row
    await db.execute('''
      CREATE TABLE user_preferences (
        id                       INTEGER PRIMARY KEY AUTOINCREMENT,
        name                     TEXT    NOT NULL DEFAULT '',
        daily_calorie_goal       INTEGER NOT NULL DEFAULT 2000,
        onboarding_complete      INTEGER NOT NULL DEFAULT 0,
        has_seen_scan_tutorial   INTEGER NOT NULL DEFAULT 0,
        nutrition_goal           TEXT    NOT NULL DEFAULT 'maintain',
        daily_carb_limit_g       INTEGER NOT NULL DEFAULT 250,
        daily_protein_target_g   INTEGER NOT NULL DEFAULT 80,
        daily_fat_target_g       INTEGER NOT NULL DEFAULT 65,
        mascot_type              TEXT    NOT NULL DEFAULT 'auto',
        theme_color_seed         TEXT    NOT NULL DEFAULT 'green'
      )
    ''');
    await db.insert('user_preferences', const UserPreferences().toMap());

    // ground_truth — actual measurements for evaluation
    await db.execute('''
      CREATE TABLE ground_truth (
        id                   INTEGER PRIMARY KEY AUTOINCREMENT,
        detected_food_id     INTEGER NOT NULL,
        scan_id              INTEGER NOT NULL,
        actual_weight_grams  REAL    NOT NULL,
        actual_calories      REAL,
        notes                TEXT,
        timestamp            TEXT    NOT NULL,
        FOREIGN KEY (detected_food_id) REFERENCES detected_foods(id) ON DELETE CASCADE,
        FOREIGN KEY (scan_id) REFERENCES scan_results(id) ON DELETE CASCADE
      )
    ''');

    // benchmarks — per-scan performance timing
    await db.execute('''
      CREATE TABLE benchmarks (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id           INTEGER NOT NULL,
        capture_top_ms    INTEGER NOT NULL,
        capture_side_ms   INTEGER NOT NULL,
        inference_ms      INTEGER NOT NULL,
        total_ms          INTEGER NOT NULL,
        peak_memory_bytes INTEGER NOT NULL DEFAULT 0,
        depth_mode        TEXT    NOT NULL,
        timestamp         TEXT    NOT NULL,
        FOREIGN KEY (scan_id) REFERENCES scan_results(id) ON DELETE CASCADE
      )
    ''');

    // grocery_list — user shopping list
    await db.execute('''
      CREATE TABLE grocery_list (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT    NOT NULL,
        category   TEXT,
        quantity   INTEGER NOT NULL DEFAULT 1,
        checked    INTEGER NOT NULL DEFAULT 0,
        created_at TEXT    NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _seed(db);
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_preferences (
          id                       INTEGER PRIMARY KEY AUTOINCREMENT,
          name                     TEXT    NOT NULL DEFAULT '',
          daily_calorie_goal       INTEGER NOT NULL DEFAULT 2000,
          onboarding_complete      INTEGER NOT NULL DEFAULT 0,
          has_seen_scan_tutorial   INTEGER NOT NULL DEFAULT 0
        )
      ''');
      final rows = await db.query('user_preferences');
      if (rows.isEmpty) {
        await db.insert('user_preferences', const UserPreferences().toMap());
      }
    }
    if (oldVersion < 4) {
      // Add scan tutorial flag — safe to run even if column already exists
      try {
        await db.execute(
          'ALTER TABLE user_preferences ADD COLUMN has_seen_scan_tutorial INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {
        // Column already exists from fresh v4 install — ignore
      }
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ground_truth (
          id                   INTEGER PRIMARY KEY AUTOINCREMENT,
          detected_food_id     INTEGER NOT NULL,
          scan_id              INTEGER NOT NULL,
          actual_weight_grams  REAL    NOT NULL,
          actual_calories      REAL,
          notes                TEXT,
          timestamp            TEXT    NOT NULL,
          FOREIGN KEY (detected_food_id) REFERENCES detected_foods(id) ON DELETE CASCADE,
          FOREIGN KEY (scan_id) REFERENCES scan_results(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 6) {
      // Camera pose columns on scan_results
      try {
        await db.execute('ALTER TABLE scan_results ADD COLUMN top_camera_position TEXT');
        await db.execute('ALTER TABLE scan_results ADD COLUMN top_camera_transform TEXT');
        await db.execute('ALTER TABLE scan_results ADD COLUMN side_camera_position TEXT');
        await db.execute('ALTER TABLE scan_results ADD COLUMN side_camera_transform TEXT');
      } catch (_) {
        // Columns already exist from fresh v6 install
      }

      // Benchmarks table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS benchmarks (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          scan_id         INTEGER NOT NULL,
          capture_top_ms  INTEGER NOT NULL,
          capture_side_ms INTEGER NOT NULL,
          inference_ms    INTEGER NOT NULL,
          total_ms        INTEGER NOT NULL,
          depth_mode      TEXT    NOT NULL,
          timestamp       TEXT    NOT NULL,
          FOREIGN KEY (scan_id) REFERENCES scan_results(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 7) {
      // Add memory usage column to benchmarks
      try {
        await db.execute(
          'ALTER TABLE benchmarks ADD COLUMN peak_memory_bytes INTEGER NOT NULL DEFAULT 0',
        );
      } catch (_) {}
    }
    if (oldVersion < 8) {
      // Macro columns for food_data
      for (final col in [
        'protein_per_100g REAL NOT NULL DEFAULT 0',
        'carbs_per_100g   REAL NOT NULL DEFAULT 0',
        'fat_per_100g     REAL NOT NULL DEFAULT 0',
      ]) {
        try { await db.execute('ALTER TABLE food_data ADD COLUMN $col'); } catch (_) {}
      }
      // Backfill macro values for existing seed foods
      await _backfillMacros(db);
      // Goal columns for user_preferences
      for (final col in [
        "nutrition_goal TEXT NOT NULL DEFAULT 'maintain'",
        'daily_carb_limit_g INTEGER NOT NULL DEFAULT 250',
        'daily_protein_target_g INTEGER NOT NULL DEFAULT 80',
        'daily_fat_target_g INTEGER NOT NULL DEFAULT 65',
      ]) {
        try { await db.execute('ALTER TABLE user_preferences ADD COLUMN $col'); } catch (_) {}
      }
    }
    if (oldVersion < 9) {
      for (final col in [
        "mascot_type TEXT NOT NULL DEFAULT 'auto'",
        "theme_color_seed TEXT NOT NULL DEFAULT 'green'",
      ]) {
        try { await db.execute('ALTER TABLE user_preferences ADD COLUMN $col'); } catch (_) {}
      }
    }
    if (oldVersion < 10) {
      // Re-seed food_data with all 103 FoodSeg103 classes
      await _seed(db);
    }
    if (oldVersion < 11) {
      // Corrected apparent/bulk density values (g/cm³) for as-plated foods.
      // Sources: USDA FoodData Central, FAO food composition tables,
      // and published bulk-density measurements for common foods.
      const densityUpdates = [
        // (label,            densityMin, densityMax)
        ('candy',             1.30, 1.55), // hard candy ~1.4-1.6 g/cm³
        ('cake',              0.35, 0.55), // sponge/layer cake, very light
        ('strawberry',        0.75, 0.90), // fresh flesh ~0.9 g/cm³
        ('raspberry',         0.55, 0.70), // on-plate bulk
        ('blueberry',         0.72, 0.85), // fresh blueberry
        ('watermelon',        0.88, 0.98), // flesh is ~96% water
        ('melon',             0.82, 0.92), // cantaloupe / honeydew flesh
        ('pineapple',         0.85, 0.97), // fresh cut flesh
        ('lemon',             0.95, 1.05), // citrus close to water density
        ('grape',             0.88, 0.98), // fresh grape, quite dense
        ('tomato',            0.85, 0.98), // tomato flesh ~0.9-1.0
        ('cucumber',          0.88, 0.98), // ~96% water
        ('white radish',      0.87, 0.97), // firm daikon
        ('carrot',            0.95, 1.05), // dense root vegetable
        ('bean sprouts',      0.50, 0.65), // mung sprouts with air gaps
        ('okra',              0.62, 0.78), // whole okra pods
        ('pepper',            0.60, 0.75), // cut bell pepper
        ('black fungus',      0.65, 0.85), // soaked / cooked wood-ear
        ('enoki mushroom',    0.42, 0.62), // delicate enoki
        ('noodles',           0.85, 1.05), // cooked, water-absorbed
        ('bamboo shoots',     0.80, 0.95), // cooked bamboo shoots
        ('asparagus',         0.55, 0.75), // spears with some air
        ('kelp',              0.90, 1.05), // cooked / soaked kelp
        ('eggplant',          0.60, 0.80), // cooked eggplant
      ];
      final batch = db.batch();
      for (final (label, dMin, dMax) in densityUpdates) {
        batch.update(
          'food_data',
          {'density_min': dMin, 'density_max': dMax},
          where: 'label = ?',
          whereArgs: [label],
        );
      }
      await batch.commit(noResult: true);
    }
    if (oldVersion < 12) {
      // Insert extended food database (200+ new common foods).
      // Uses conflictAlgorithm: ignore, so existing entries are preserved.
      await _seed(db);

      // Grocery list table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS grocery_list (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          name       TEXT    NOT NULL,
          category   TEXT,
          quantity   INTEGER NOT NULL DEFAULT 1,
          checked    INTEGER NOT NULL DEFAULT 0,
          created_at TEXT    NOT NULL
        )
      ''');
    }
    if (oldVersion < 13) {
      // Clean up duplicate aliases and confusing labels.
      // Remove 'Chicken' (duplicate of 'chicken duck' / now 'chicken').
      // Remove 'Fries' (duplicate of 'french fries').
      await db.delete('food_data', where: 'label = ?', whereArgs: ['Chicken']);
      await db.delete('food_data', where: 'label = ?', whereArgs: ['Fries']);

      // Rename 'chicken duck' → 'chicken' (cleaner label).
      await db.update(
        'food_data',
        {'label': 'chicken'},
        where: 'label = ?',
        whereArgs: ['chicken duck'],
      );

      // Re-seed to add any new items.
      await _seed(db);
    }
  }

  /// Updates protein/carbs/fat for foods that were seeded before v8.
  Future<void> _backfillMacros(Database db) async {
    const updates = [
      ('Apple',      0.3,  14.0,  0.2), ('Banana',     1.1,  23.0,  0.3),
      ('Orange',     0.9,  12.0,  0.1), ('Strawberry', 0.7,   7.7,  0.3),
      ('Grapes',     0.7,  18.0,  0.2), ('Watermelon', 0.6,   7.6,  0.2),
      ('Mango',      0.8,  15.0,  0.4), ('Pineapple',  0.5,  13.0,  0.1),
      ('Broccoli',   2.8,   7.2,  0.4), ('Carrot',     0.9,  10.0,  0.2),
      ('Tomato',     0.9,   3.9,  0.2), ('Cucumber',   0.7,   3.6,  0.1),
      ('Lettuce',    1.4,   2.9,  0.2), ('Potato',     2.0,  17.0,  0.1),
      ('Sweet Potato',1.6, 20.0,  0.1), ('Spinach',    2.9,   3.6,  0.4),
      ('Bell Pepper',1.0,   6.0,  0.3), ('Onion',      1.1,   9.3,  0.1),
      ('Rice',       2.7,  28.0,  0.3), ('Pasta',      5.1,  25.0,  0.9),
      ('Bread',      9.0,  49.0,  3.2), ('Noodles',    4.5,  25.0,  1.0),
      ('Oatmeal',    2.5,  12.0,  1.5), ('Corn',       3.3,  19.0,  1.4),
      ('Chicken',   31.0,   0.0,  3.6), ('Beef',      26.0,   0.0, 17.0),
      ('Pork',      25.0,   0.0, 14.0), ('Fish',      22.0,   0.0, 12.0),
      ('Salmon',    20.0,   0.0, 13.0), ('Shrimp',    20.0,   0.9,  1.7),
      ('Egg',       13.0,   1.1, 11.0), ('Tofu',       8.1,   2.0,  4.2),
      ('Cheese',    25.0,   1.3, 33.0), ('Yogurt',    10.0,   3.6,  0.4),
      ('Salad',      1.5,   3.0,  0.5), ('Soup',       2.0,   6.0,  1.5),
      ('Stew',       8.0,  10.0,  4.0), ('Curry',      7.0,  12.0,  5.0),
      ('Pizza',     11.0,  33.0, 10.0), ('Sushi',      6.7,  19.0,  5.0),
      ('Fries',      3.4,  41.0, 15.0), ('Cake',       4.5,  55.0, 14.0),
    ];
    final batch = db.batch();
    for (final (label, p, c, f) in updates) {
      batch.update(
        'food_data',
        {'protein_per_100g': p, 'carbs_per_100g': c, 'fat_per_100g': f},
        where: 'label = ?',
        whereArgs: [label],
      );
    }
    await batch.commit(noResult: true);
  }

  // ── Seed data (103 FoodSeg103 classes + common aliases) ─────────────────

  Future<void> _seed(Database db) async {
    const seeds = [
      // ── 0. background (skipped) ─────────────────────────────────────────

      // ── 1–10: Sweets / Snacks / Dairy ────────────────────────────────────
      FoodData(label: 'candy',               densityMin: 1.30, densityMax: 1.55, kcalPer100g: 394, category: 'snack',     proteinPer100g:  1.0, carbsPer100g: 90.0, fatPer100g:  2.0),
      FoodData(label: 'egg tart',            densityMin: 0.75, densityMax: 0.90, kcalPer100g: 280, category: 'mixed',     proteinPer100g:  6.0, carbsPer100g: 28.0, fatPer100g: 16.0),
      FoodData(label: 'french fries',        densityMin: 0.45, densityMax: 0.60, kcalPer100g: 312, category: 'mixed',     proteinPer100g:  3.4, carbsPer100g: 41.0, fatPer100g: 15.0),
      FoodData(label: 'chocolate',           densityMin: 1.10, densityMax: 1.30, kcalPer100g: 546, category: 'snack',     proteinPer100g:  5.0, carbsPer100g: 60.0, fatPer100g: 31.0),
      FoodData(label: 'biscuit',             densityMin: 0.40, densityMax: 0.55, kcalPer100g: 440, category: 'snack',     proteinPer100g:  7.0, carbsPer100g: 65.0, fatPer100g: 18.0),
      FoodData(label: 'popcorn',             densityMin: 0.04, densityMax: 0.08, kcalPer100g: 375, category: 'snack',     proteinPer100g: 11.0, carbsPer100g: 74.0, fatPer100g:  4.5),
      FoodData(label: 'pudding',             densityMin: 0.95, densityMax: 1.05, kcalPer100g: 130, category: 'mixed',     proteinPer100g:  3.0, carbsPer100g: 20.0, fatPer100g:  4.0),
      FoodData(label: 'ice cream',           densityMin: 0.55, densityMax: 0.70, kcalPer100g: 207, category: 'dairy',     proteinPer100g:  3.5, carbsPer100g: 24.0, fatPer100g: 11.0),
      FoodData(label: 'cheese butter',       densityMin: 1.00, densityMax: 1.15, kcalPer100g: 402, category: 'dairy',     proteinPer100g: 25.0, carbsPer100g:  1.3, fatPer100g: 33.0),
      FoodData(label: 'cake',                densityMin: 0.35, densityMax: 0.55, kcalPer100g: 347, category: 'mixed',     proteinPer100g:  4.5, carbsPer100g: 55.0, fatPer100g: 14.0),

      // ── 11–16: Drinks ────────────────────────────────────────────────────
      FoodData(label: 'wine',                densityMin: 0.99, densityMax: 1.02, kcalPer100g:  85, category: 'drink',     proteinPer100g:  0.1, carbsPer100g:  2.6, fatPer100g:  0.0),
      FoodData(label: 'milkshake',           densityMin: 0.95, densityMax: 1.05, kcalPer100g: 112, category: 'drink',     proteinPer100g:  3.5, carbsPer100g: 18.0, fatPer100g:  3.0),
      FoodData(label: 'coffee',              densityMin: 0.99, densityMax: 1.01, kcalPer100g:   2, category: 'drink',     proteinPer100g:  0.3, carbsPer100g:  0.0, fatPer100g:  0.0),
      FoodData(label: 'juice',               densityMin: 1.00, densityMax: 1.05, kcalPer100g:  46, category: 'drink',     proteinPer100g:  0.5, carbsPer100g: 11.0, fatPer100g:  0.1),
      FoodData(label: 'milk',                densityMin: 1.03, densityMax: 1.04, kcalPer100g:  42, category: 'drink',     proteinPer100g:  3.4, carbsPer100g:  5.0, fatPer100g:  1.0),
      FoodData(label: 'tea',                 densityMin: 0.99, densityMax: 1.01, kcalPer100g:   1, category: 'drink',     proteinPer100g:  0.0, carbsPer100g:  0.3, fatPer100g:  0.0),

      // ── 17–23: Nuts & Legumes ────────────────────────────────────────────
      FoodData(label: 'almond',              densityMin: 0.55, densityMax: 0.65, kcalPer100g: 579, category: 'nut',       proteinPer100g: 21.0, carbsPer100g: 22.0, fatPer100g: 50.0),
      FoodData(label: 'red beans',           densityMin: 0.80, densityMax: 0.90, kcalPer100g: 127, category: 'legume',    proteinPer100g:  8.7, carbsPer100g: 22.0, fatPer100g:  0.5),
      FoodData(label: 'cashew',              densityMin: 0.55, densityMax: 0.65, kcalPer100g: 553, category: 'nut',       proteinPer100g: 18.0, carbsPer100g: 30.0, fatPer100g: 44.0),
      FoodData(label: 'dried cranberries',   densityMin: 0.55, densityMax: 0.70, kcalPer100g: 308, category: 'fruit',     proteinPer100g:  0.1, carbsPer100g: 82.0, fatPer100g:  1.4),
      FoodData(label: 'soy',                 densityMin: 0.75, densityMax: 0.85, kcalPer100g: 173, category: 'legume',    proteinPer100g: 17.0, carbsPer100g:  9.9, fatPer100g:  9.0),
      FoodData(label: 'walnut',              densityMin: 0.50, densityMax: 0.60, kcalPer100g: 654, category: 'nut',       proteinPer100g: 15.0, carbsPer100g: 14.0, fatPer100g: 65.0),
      FoodData(label: 'peanut',              densityMin: 0.55, densityMax: 0.65, kcalPer100g: 567, category: 'nut',       proteinPer100g: 26.0, carbsPer100g: 16.0, fatPer100g: 49.0),

      // ── 24: Egg ──────────────────────────────────────────────────────────
      FoodData(label: 'egg',                 densityMin: 0.95, densityMax: 1.05, kcalPer100g: 155, category: 'protein',   proteinPer100g: 13.0, carbsPer100g:  1.1, fatPer100g: 11.0),

      // ── 25–45: Fruits ────────────────────────────────────────────────────
      FoodData(label: 'apple',               densityMin: 0.75, densityMax: 0.85, kcalPer100g:  52, category: 'fruit',     proteinPer100g:  0.3, carbsPer100g: 14.0, fatPer100g:  0.2),
      FoodData(label: 'date',                densityMin: 1.05, densityMax: 1.20, kcalPer100g: 277, category: 'fruit',     proteinPer100g:  1.8, carbsPer100g: 75.0, fatPer100g:  0.2),
      FoodData(label: 'apricot',             densityMin: 0.75, densityMax: 0.85, kcalPer100g:  48, category: 'fruit',     proteinPer100g:  1.4, carbsPer100g: 11.0, fatPer100g:  0.4),
      FoodData(label: 'avocado',             densityMin: 0.90, densityMax: 1.00, kcalPer100g: 160, category: 'fruit',     proteinPer100g:  2.0, carbsPer100g:  9.0, fatPer100g: 15.0),
      FoodData(label: 'banana',              densityMin: 0.80, densityMax: 0.95, kcalPer100g:  89, category: 'fruit',     proteinPer100g:  1.1, carbsPer100g: 23.0, fatPer100g:  0.3),
      FoodData(label: 'strawberry',          densityMin: 0.75, densityMax: 0.90, kcalPer100g:  32, category: 'fruit',     proteinPer100g:  0.7, carbsPer100g:  7.7, fatPer100g:  0.3),
      FoodData(label: 'cherry',              densityMin: 0.85, densityMax: 0.95, kcalPer100g:  50, category: 'fruit',     proteinPer100g:  1.0, carbsPer100g: 12.0, fatPer100g:  0.3),
      FoodData(label: 'blueberry',           densityMin: 0.72, densityMax: 0.85, kcalPer100g:  57, category: 'fruit',     proteinPer100g:  0.7, carbsPer100g: 14.0, fatPer100g:  0.3),
      FoodData(label: 'raspberry',           densityMin: 0.55, densityMax: 0.70, kcalPer100g:  52, category: 'fruit',     proteinPer100g:  1.2, carbsPer100g: 12.0, fatPer100g:  0.7),
      FoodData(label: 'mango',               densityMin: 0.75, densityMax: 0.85, kcalPer100g:  60, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g: 15.0, fatPer100g:  0.4),
      FoodData(label: 'olives',              densityMin: 0.85, densityMax: 0.95, kcalPer100g: 115, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g:  6.3, fatPer100g: 11.0),
      FoodData(label: 'peach',               densityMin: 0.75, densityMax: 0.85, kcalPer100g:  39, category: 'fruit',     proteinPer100g:  0.9, carbsPer100g: 10.0, fatPer100g:  0.3),
      FoodData(label: 'lemon',               densityMin: 0.95, densityMax: 1.05, kcalPer100g:  29, category: 'fruit',     proteinPer100g:  1.1, carbsPer100g:  9.3, fatPer100g:  0.3),
      FoodData(label: 'pear',                densityMin: 0.75, densityMax: 0.85, kcalPer100g:  57, category: 'fruit',     proteinPer100g:  0.4, carbsPer100g: 15.0, fatPer100g:  0.1),
      FoodData(label: 'fig',                 densityMin: 0.85, densityMax: 0.95, kcalPer100g:  74, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g: 19.0, fatPer100g:  0.3),
      FoodData(label: 'pineapple',           densityMin: 0.85, densityMax: 0.97, kcalPer100g:  50, category: 'fruit',     proteinPer100g:  0.5, carbsPer100g: 13.0, fatPer100g:  0.1),
      FoodData(label: 'grape',               densityMin: 0.88, densityMax: 0.98, kcalPer100g:  69, category: 'fruit',     proteinPer100g:  0.7, carbsPer100g: 18.0, fatPer100g:  0.2),
      FoodData(label: 'kiwi',                densityMin: 0.80, densityMax: 0.90, kcalPer100g:  61, category: 'fruit',     proteinPer100g:  1.1, carbsPer100g: 15.0, fatPer100g:  0.5),
      FoodData(label: 'melon',               densityMin: 0.82, densityMax: 0.92, kcalPer100g:  34, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g:  8.2, fatPer100g:  0.2),
      FoodData(label: 'orange',              densityMin: 0.75, densityMax: 0.85, kcalPer100g:  47, category: 'fruit',     proteinPer100g:  0.9, carbsPer100g: 12.0, fatPer100g:  0.1),
      FoodData(label: 'watermelon',          densityMin: 0.88, densityMax: 0.98, kcalPer100g:  30, category: 'fruit',     proteinPer100g:  0.6, carbsPer100g:  7.6, fatPer100g:  0.2),

      // ── 46–56: Meats & Seafood ───────────────────────────────────────────
      FoodData(label: 'steak',               densityMin: 1.00, densityMax: 1.15, kcalPer100g: 271, category: 'protein',   proteinPer100g: 26.0, carbsPer100g:  0.0, fatPer100g: 18.0),
      FoodData(label: 'pork',                densityMin: 1.00, densityMax: 1.10, kcalPer100g: 242, category: 'protein',   proteinPer100g: 25.0, carbsPer100g:  0.0, fatPer100g: 14.0),
      FoodData(label: 'chicken',             densityMin: 1.00, densityMax: 1.10, kcalPer100g: 165, category: 'protein',   proteinPer100g: 31.0, carbsPer100g:  0.0, fatPer100g:  3.6),
      FoodData(label: 'sausage',             densityMin: 0.90, densityMax: 1.05, kcalPer100g: 301, category: 'protein',   proteinPer100g: 12.0, carbsPer100g:  2.0, fatPer100g: 27.0),
      FoodData(label: 'fried meat',          densityMin: 0.85, densityMax: 1.00, kcalPer100g: 280, category: 'protein',   proteinPer100g: 23.0, carbsPer100g: 10.0, fatPer100g: 17.0),
      FoodData(label: 'lamb',                densityMin: 1.00, densityMax: 1.10, kcalPer100g: 294, category: 'protein',   proteinPer100g: 25.0, carbsPer100g:  0.0, fatPer100g: 21.0),
      FoodData(label: 'sauce',               densityMin: 1.00, densityMax: 1.15, kcalPer100g:  80, category: 'mixed',     proteinPer100g:  1.5, carbsPer100g: 12.0, fatPer100g:  3.0),
      FoodData(label: 'crab',                densityMin: 0.90, densityMax: 1.00, kcalPer100g:  97, category: 'protein',   proteinPer100g: 19.0, carbsPer100g:  0.0, fatPer100g:  1.5),
      FoodData(label: 'fish',                densityMin: 0.95, densityMax: 1.05, kcalPer100g: 206, category: 'protein',   proteinPer100g: 22.0, carbsPer100g:  0.0, fatPer100g: 12.0),
      FoodData(label: 'shellfish',           densityMin: 0.90, densityMax: 1.00, kcalPer100g:  85, category: 'protein',   proteinPer100g: 18.0, carbsPer100g:  3.0, fatPer100g:  1.0),
      FoodData(label: 'shrimp',              densityMin: 0.90, densityMax: 1.00, kcalPer100g:  99, category: 'protein',   proteinPer100g: 20.0, carbsPer100g:  0.9, fatPer100g:  1.7),

      // ── 57–65: Grains & Prepared ─────────────────────────────────────────
      FoodData(label: 'bread',               densityMin: 0.30, densityMax: 0.45, kcalPer100g: 265, category: 'grain',     proteinPer100g:  9.0, carbsPer100g: 49.0, fatPer100g:  3.2),
      FoodData(label: 'corn',                densityMin: 0.70, densityMax: 0.85, kcalPer100g:  86, category: 'grain',     proteinPer100g:  3.3, carbsPer100g: 19.0, fatPer100g:  1.4),
      FoodData(label: 'hamburg',             densityMin: 0.70, densityMax: 0.85, kcalPer100g: 295, category: 'mixed',     proteinPer100g: 17.0, carbsPer100g: 24.0, fatPer100g: 14.0),
      FoodData(label: 'pizza',               densityMin: 0.60, densityMax: 0.80, kcalPer100g: 266, category: 'mixed',     proteinPer100g: 11.0, carbsPer100g: 33.0, fatPer100g: 10.0),
      FoodData(label: 'hanamaki baozi',      densityMin: 0.50, densityMax: 0.65, kcalPer100g: 215, category: 'grain',     proteinPer100g:  6.5, carbsPer100g: 40.0, fatPer100g:  3.0),
      FoodData(label: 'wonton dumplings',    densityMin: 0.80, densityMax: 0.95, kcalPer100g: 220, category: 'mixed',     proteinPer100g:  9.0, carbsPer100g: 28.0, fatPer100g:  8.0),
      FoodData(label: 'taro',                densityMin: 0.85, densityMax: 0.95, kcalPer100g: 112, category: 'vegetable', proteinPer100g:  1.5, carbsPer100g: 27.0, fatPer100g:  0.1),
      FoodData(label: 'rice',                densityMin: 0.75, densityMax: 0.90, kcalPer100g: 130, category: 'grain',     proteinPer100g:  2.7, carbsPer100g: 28.0, fatPer100g:  0.3),
      FoodData(label: 'tofu',                densityMin: 0.90, densityMax: 1.00, kcalPer100g:  76, category: 'protein',   proteinPer100g:  8.1, carbsPer100g:  2.0, fatPer100g:  4.2),

      // ── 66–99: Vegetables ────────────────────────────────────────────────
      FoodData(label: 'eggplant',            densityMin: 0.60, densityMax: 0.80, kcalPer100g:  25, category: 'vegetable', proteinPer100g:  1.0, carbsPer100g:  6.0, fatPer100g:  0.2),
      FoodData(label: 'potato',              densityMin: 0.90, densityMax: 1.05, kcalPer100g:  77, category: 'vegetable', proteinPer100g:  2.0, carbsPer100g: 17.0, fatPer100g:  0.1),
      FoodData(label: 'garlic',              densityMin: 0.90, densityMax: 1.05, kcalPer100g: 149, category: 'vegetable', proteinPer100g:  6.4, carbsPer100g: 33.0, fatPer100g:  0.5),
      FoodData(label: 'cauliflower',         densityMin: 0.35, densityMax: 0.50, kcalPer100g:  25, category: 'vegetable', proteinPer100g:  1.9, carbsPer100g:  5.0, fatPer100g:  0.3),
      FoodData(label: 'tomato',              densityMin: 0.85, densityMax: 0.98, kcalPer100g:  18, category: 'vegetable', proteinPer100g:  0.9, carbsPer100g:  3.9, fatPer100g:  0.2),
      FoodData(label: 'kelp',                densityMin: 0.90, densityMax: 1.05, kcalPer100g:  43, category: 'vegetable', proteinPer100g:  1.7, carbsPer100g: 10.0, fatPer100g:  0.6),
      FoodData(label: 'seaweed',             densityMin: 0.20, densityMax: 0.35, kcalPer100g:  35, category: 'vegetable', proteinPer100g:  5.8, carbsPer100g:  5.1, fatPer100g:  0.3),
      FoodData(label: 'spring onion',        densityMin: 0.50, densityMax: 0.65, kcalPer100g:  32, category: 'vegetable', proteinPer100g:  1.8, carbsPer100g:  7.3, fatPer100g:  0.2),
      FoodData(label: 'rape',                densityMin: 0.35, densityMax: 0.50, kcalPer100g:  22, category: 'vegetable', proteinPer100g:  1.5, carbsPer100g:  3.2, fatPer100g:  0.3),
      FoodData(label: 'ginger',              densityMin: 0.90, densityMax: 1.05, kcalPer100g:  80, category: 'vegetable', proteinPer100g:  1.8, carbsPer100g: 18.0, fatPer100g:  0.8),
      FoodData(label: 'okra',                densityMin: 0.62, densityMax: 0.78, kcalPer100g:  33, category: 'vegetable', proteinPer100g:  1.9, carbsPer100g:  7.5, fatPer100g:  0.2),
      FoodData(label: 'lettuce',             densityMin: 0.20, densityMax: 0.35, kcalPer100g:  15, category: 'vegetable', proteinPer100g:  1.4, carbsPer100g:  2.9, fatPer100g:  0.2),
      FoodData(label: 'pumpkin',             densityMin: 0.70, densityMax: 0.85, kcalPer100g:  26, category: 'vegetable', proteinPer100g:  1.0, carbsPer100g:  7.0, fatPer100g:  0.1),
      FoodData(label: 'cucumber',            densityMin: 0.88, densityMax: 0.98, kcalPer100g:  15, category: 'vegetable', proteinPer100g:  0.7, carbsPer100g:  3.6, fatPer100g:  0.1),
      FoodData(label: 'white radish',        densityMin: 0.87, densityMax: 0.97, kcalPer100g:  18, category: 'vegetable', proteinPer100g:  0.7, carbsPer100g:  4.1, fatPer100g:  0.1),
      FoodData(label: 'carrot',              densityMin: 0.95, densityMax: 1.05, kcalPer100g:  41, category: 'vegetable', proteinPer100g:  0.9, carbsPer100g: 10.0, fatPer100g:  0.2),
      FoodData(label: 'asparagus',           densityMin: 0.55, densityMax: 0.75, kcalPer100g:  20, category: 'vegetable', proteinPer100g:  2.2, carbsPer100g:  3.9, fatPer100g:  0.1),
      FoodData(label: 'bamboo shoots',       densityMin: 0.80, densityMax: 0.95, kcalPer100g:  27, category: 'vegetable', proteinPer100g:  2.6, carbsPer100g:  5.2, fatPer100g:  0.3),
      FoodData(label: 'broccoli',            densityMin: 0.40, densityMax: 0.55, kcalPer100g:  34, category: 'vegetable', proteinPer100g:  2.8, carbsPer100g:  7.2, fatPer100g:  0.4),
      FoodData(label: 'celery stick',        densityMin: 0.55, densityMax: 0.70, kcalPer100g:  16, category: 'vegetable', proteinPer100g:  0.7, carbsPer100g:  3.0, fatPer100g:  0.2),
      FoodData(label: 'cilantro mint',       densityMin: 0.25, densityMax: 0.40, kcalPer100g:  23, category: 'vegetable', proteinPer100g:  2.1, carbsPer100g:  3.7, fatPer100g:  0.5),
      FoodData(label: 'snow peas',           densityMin: 0.50, densityMax: 0.65, kcalPer100g:  42, category: 'vegetable', proteinPer100g:  2.8, carbsPer100g:  7.6, fatPer100g:  0.2),
      FoodData(label: 'cabbage',             densityMin: 0.35, densityMax: 0.50, kcalPer100g:  25, category: 'vegetable', proteinPer100g:  1.3, carbsPer100g:  6.0, fatPer100g:  0.1),
      FoodData(label: 'bean sprouts',        densityMin: 0.50, densityMax: 0.65, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  3.0, carbsPer100g:  6.0, fatPer100g:  0.2),
      FoodData(label: 'onion',               densityMin: 0.85, densityMax: 0.95, kcalPer100g:  40, category: 'vegetable', proteinPer100g:  1.1, carbsPer100g:  9.3, fatPer100g:  0.1),
      FoodData(label: 'pepper',              densityMin: 0.60, densityMax: 0.75, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  1.0, carbsPer100g:  6.0, fatPer100g:  0.3),
      FoodData(label: 'green beans',         densityMin: 0.55, densityMax: 0.70, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  1.8, carbsPer100g:  7.0, fatPer100g:  0.1),
      FoodData(label: 'french beans',        densityMin: 0.55, densityMax: 0.70, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  1.8, carbsPer100g:  7.0, fatPer100g:  0.1),
      FoodData(label: 'king oyster mushroom',densityMin: 0.55, densityMax: 0.70, kcalPer100g:  35, category: 'vegetable', proteinPer100g:  3.3, carbsPer100g:  6.0, fatPer100g:  0.4),
      FoodData(label: 'white mushroom',      densityMin: 0.50, densityMax: 0.65, kcalPer100g:  22, category: 'vegetable', proteinPer100g:  3.1, carbsPer100g:  3.3, fatPer100g:  0.3),
      FoodData(label: 'shiitake',            densityMin: 0.55, densityMax: 0.70, kcalPer100g:  34, category: 'vegetable', proteinPer100g:  2.2, carbsPer100g:  7.0, fatPer100g:  0.5),
      FoodData(label: 'enoki mushroom',      densityMin: 0.42, densityMax: 0.62, kcalPer100g:  37, category: 'vegetable', proteinPer100g:  2.7, carbsPer100g:  7.8, fatPer100g:  0.3),
      FoodData(label: 'oyster mushroom',     densityMin: 0.50, densityMax: 0.65, kcalPer100g:  33, category: 'vegetable', proteinPer100g:  3.3, carbsPer100g:  6.1, fatPer100g:  0.4),
      FoodData(label: 'black fungus',        densityMin: 0.65, densityMax: 0.85, kcalPer100g:  40, category: 'vegetable', proteinPer100g:  0.5, carbsPer100g: 10.0, fatPer100g:  0.2),

      // ── 100–103: Noodles & Others ────────────────────────────────────────
      FoodData(label: 'dough',               densityMin: 0.75, densityMax: 0.90, kcalPer100g: 289, category: 'grain',     proteinPer100g:  8.0, carbsPer100g: 55.0, fatPer100g:  3.5),
      FoodData(label: 'noodles',             densityMin: 0.85, densityMax: 1.05, kcalPer100g: 138, category: 'grain',     proteinPer100g:  4.5, carbsPer100g: 25.0, fatPer100g:  1.0),
      FoodData(label: 'rice noodle',         densityMin: 0.70, densityMax: 0.85, kcalPer100g: 109, category: 'grain',     proteinPer100g:  0.9, carbsPer100g: 25.0, fatPer100g:  0.2),
      FoodData(label: 'others',              densityMin: 0.60, densityMax: 0.90, kcalPer100g: 150, category: 'mixed',     proteinPer100g:  5.0, carbsPer100g: 20.0, fatPer100g:  5.0),

      // ── Common aliases (map user-friendly names to FS103 equivalents) ──────
      // NOTE: Only include aliases that don't duplicate an existing FS103 label.
      // Removed: Chicken (dup of chicken duck), Fries (dup of french fries).
      FoodData(label: 'Beef',                densityMin: 1.00, densityMax: 1.15, kcalPer100g: 250, category: 'protein',   proteinPer100g: 26.0, carbsPer100g:  0.0, fatPer100g: 17.0),
      FoodData(label: 'Salmon',              densityMin: 0.95, densityMax: 1.05, kcalPer100g: 208, category: 'protein',   proteinPer100g: 20.0, carbsPer100g:  0.0, fatPer100g: 13.0),
      FoodData(label: 'Yogurt',              densityMin: 1.00, densityMax: 1.10, kcalPer100g:  59, category: 'dairy',     proteinPer100g: 10.0, carbsPer100g:  3.6, fatPer100g:  0.4),
      FoodData(label: 'Pasta',               densityMin: 0.80, densityMax: 0.95, kcalPer100g: 131, category: 'grain',     proteinPer100g:  5.1, carbsPer100g: 25.0, fatPer100g:  0.9),
      FoodData(label: 'Oatmeal',             densityMin: 0.65, densityMax: 0.80, kcalPer100g:  71, category: 'grain',     proteinPer100g:  2.5, carbsPer100g: 12.0, fatPer100g:  1.5),
      FoodData(label: 'Sweet Potato',        densityMin: 0.85, densityMax: 1.00, kcalPer100g:  86, category: 'vegetable', proteinPer100g:  1.6, carbsPer100g: 20.0, fatPer100g:  0.1),
      FoodData(label: 'Spinach',             densityMin: 0.25, densityMax: 0.40, kcalPer100g:  23, category: 'vegetable', proteinPer100g:  2.9, carbsPer100g:  3.6, fatPer100g:  0.4),
      FoodData(label: 'Bell Pepper',         densityMin: 0.45, densityMax: 0.55, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  1.0, carbsPer100g:  6.0, fatPer100g:  0.3),
      FoodData(label: 'Salad',               densityMin: 0.25, densityMax: 0.45, kcalPer100g:  20, category: 'mixed',     proteinPer100g:  1.5, carbsPer100g:  3.0, fatPer100g:  0.5),
      FoodData(label: 'Soup',                densityMin: 0.95, densityMax: 1.05, kcalPer100g:  40, category: 'mixed',     proteinPer100g:  2.0, carbsPer100g:  6.0, fatPer100g:  1.5),
      FoodData(label: 'Stew',                densityMin: 0.90, densityMax: 1.05, kcalPer100g:  90, category: 'mixed',     proteinPer100g:  8.0, carbsPer100g: 10.0, fatPer100g:  4.0),
      FoodData(label: 'Curry',               densityMin: 0.90, densityMax: 1.05, kcalPer100g: 110, category: 'mixed',     proteinPer100g:  7.0, carbsPer100g: 12.0, fatPer100g:  5.0),
      FoodData(label: 'Sushi',               densityMin: 0.85, densityMax: 1.00, kcalPer100g: 143, category: 'mixed',     proteinPer100g:  6.7, carbsPer100g: 19.0, fatPer100g:  5.0),

      // ── Extended common foods (v12) ──────────────────────────────────────

      // Proteins
      FoodData(label: 'Turkey',              densityMin: 1.00, densityMax: 1.10, kcalPer100g: 135, category: 'protein',   proteinPer100g: 30.0, carbsPer100g:  0.0, fatPer100g:  1.0),
      FoodData(label: 'Duck',                densityMin: 1.00, densityMax: 1.10, kcalPer100g: 337, category: 'protein',   proteinPer100g: 19.0, carbsPer100g:  0.0, fatPer100g: 28.0),
      FoodData(label: 'Bacon',               densityMin: 0.60, densityMax: 0.80, kcalPer100g: 541, category: 'protein',   proteinPer100g: 37.0, carbsPer100g:  1.4, fatPer100g: 42.0),
      FoodData(label: 'Ham',                 densityMin: 1.00, densityMax: 1.10, kcalPer100g: 145, category: 'protein',   proteinPer100g: 21.0, carbsPer100g:  1.5, fatPer100g:  6.0),
      FoodData(label: 'Tuna',                densityMin: 1.00, densityMax: 1.10, kcalPer100g: 132, category: 'protein',   proteinPer100g: 28.0, carbsPer100g:  0.0, fatPer100g:  1.0),
      FoodData(label: 'Cod',                 densityMin: 0.95, densityMax: 1.05, kcalPer100g:  82, category: 'protein',   proteinPer100g: 18.0, carbsPer100g:  0.0, fatPer100g:  0.7),
      FoodData(label: 'Tilapia',             densityMin: 0.95, densityMax: 1.05, kcalPer100g: 128, category: 'protein',   proteinPer100g: 26.0, carbsPer100g:  0.0, fatPer100g:  2.7),
      FoodData(label: 'Sardines',            densityMin: 1.00, densityMax: 1.10, kcalPer100g: 208, category: 'protein',   proteinPer100g: 25.0, carbsPer100g:  0.0, fatPer100g: 11.0),
      FoodData(label: 'Anchovies',           densityMin: 1.00, densityMax: 1.10, kcalPer100g: 131, category: 'protein',   proteinPer100g: 20.0, carbsPer100g:  0.0, fatPer100g:  5.0),
      FoodData(label: 'Scallops',            densityMin: 0.95, densityMax: 1.05, kcalPer100g:  69, category: 'protein',   proteinPer100g: 12.0, carbsPer100g:  3.2, fatPer100g:  0.5),
      FoodData(label: 'Lobster',             densityMin: 0.95, densityMax: 1.05, kcalPer100g:  89, category: 'protein',   proteinPer100g: 19.0, carbsPer100g:  0.0, fatPer100g:  0.9),
      FoodData(label: 'Mussels',             densityMin: 0.90, densityMax: 1.00, kcalPer100g:  86, category: 'protein',   proteinPer100g: 12.0, carbsPer100g:  3.7, fatPer100g:  2.2),
      FoodData(label: 'Venison',             densityMin: 1.00, densityMax: 1.10, kcalPer100g: 158, category: 'protein',   proteinPer100g: 30.0, carbsPer100g:  0.0, fatPer100g:  3.2),
      FoodData(label: 'Bison',               densityMin: 1.00, densityMax: 1.10, kcalPer100g: 143, category: 'protein',   proteinPer100g: 28.0, carbsPer100g:  0.0, fatPer100g:  2.4),
      FoodData(label: 'Ground Beef',         densityMin: 0.95, densityMax: 1.10, kcalPer100g: 254, category: 'protein',   proteinPer100g: 17.0, carbsPer100g:  0.0, fatPer100g: 20.0),
      FoodData(label: 'Meatball',            densityMin: 0.90, densityMax: 1.05, kcalPer100g: 250, category: 'protein',   proteinPer100g: 15.0, carbsPer100g:  8.0, fatPer100g: 18.0),
      FoodData(label: 'Chicken Wing',        densityMin: 0.85, densityMax: 1.00, kcalPer100g: 290, category: 'protein',   proteinPer100g: 27.0, carbsPer100g:  0.0, fatPer100g: 19.0),
      FoodData(label: 'Chicken Breast',      densityMin: 1.00, densityMax: 1.10, kcalPer100g: 165, category: 'protein',   proteinPer100g: 31.0, carbsPer100g:  0.0, fatPer100g:  3.6),
      FoodData(label: 'Chicken Thigh',       densityMin: 1.00, densityMax: 1.10, kcalPer100g: 209, category: 'protein',   proteinPer100g: 26.0, carbsPer100g:  0.0, fatPer100g: 11.0),
      FoodData(label: 'Rib Eye Steak',       densityMin: 1.00, densityMax: 1.12, kcalPer100g: 291, category: 'protein',   proteinPer100g: 24.0, carbsPer100g:  0.0, fatPer100g: 22.0),
      FoodData(label: 'Liver',               densityMin: 1.05, densityMax: 1.15, kcalPer100g: 135, category: 'protein',   proteinPer100g: 21.0, carbsPer100g:  3.9, fatPer100g:  3.6),

      // Dairy & Eggs
      FoodData(label: 'Butter',              densityMin: 0.91, densityMax: 0.95, kcalPer100g: 717, category: 'dairy',     proteinPer100g:  0.9, carbsPer100g:  0.1, fatPer100g: 81.0),
      FoodData(label: 'Cream Cheese',        densityMin: 1.00, densityMax: 1.10, kcalPer100g: 342, category: 'dairy',     proteinPer100g:  6.0, carbsPer100g:  4.1, fatPer100g: 34.0),
      FoodData(label: 'Mozzarella',          densityMin: 1.05, densityMax: 1.15, kcalPer100g: 280, category: 'dairy',     proteinPer100g: 28.0, carbsPer100g:  3.1, fatPer100g: 17.0),
      FoodData(label: 'Cheddar',             densityMin: 1.05, densityMax: 1.15, kcalPer100g: 403, category: 'dairy',     proteinPer100g: 25.0, carbsPer100g:  1.3, fatPer100g: 33.0),
      FoodData(label: 'Parmesan',            densityMin: 1.10, densityMax: 1.25, kcalPer100g: 431, category: 'dairy',     proteinPer100g: 38.0, carbsPer100g:  4.1, fatPer100g: 29.0),
      FoodData(label: 'Feta Cheese',         densityMin: 1.00, densityMax: 1.15, kcalPer100g: 264, category: 'dairy',     proteinPer100g: 14.0, carbsPer100g:  4.1, fatPer100g: 21.0),
      FoodData(label: 'Cottage Cheese',      densityMin: 0.95, densityMax: 1.05, kcalPer100g:  98, category: 'dairy',     proteinPer100g: 11.0, carbsPer100g:  3.4, fatPer100g:  4.3),
      FoodData(label: 'Sour Cream',          densityMin: 1.00, densityMax: 1.05, kcalPer100g: 198, category: 'dairy',     proteinPer100g:  2.4, carbsPer100g:  4.6, fatPer100g: 19.0),
      FoodData(label: 'Whipped Cream',       densityMin: 0.30, densityMax: 0.50, kcalPer100g: 257, category: 'dairy',     proteinPer100g:  3.2, carbsPer100g: 12.5, fatPer100g: 22.0),
      FoodData(label: 'Greek Yogurt',        densityMin: 1.05, densityMax: 1.10, kcalPer100g:  97, category: 'dairy',     proteinPer100g: 10.0, carbsPer100g:  3.6, fatPer100g:  5.0),
      FoodData(label: 'Scrambled Eggs',      densityMin: 0.85, densityMax: 0.95, kcalPer100g: 149, category: 'protein',   proteinPer100g: 10.0, carbsPer100g:  1.6, fatPer100g: 11.0),
      FoodData(label: 'Omelette',            densityMin: 0.80, densityMax: 0.95, kcalPer100g: 154, category: 'protein',   proteinPer100g: 11.0, carbsPer100g:  0.7, fatPer100g: 12.0),

      // Grains & Cereals
      FoodData(label: 'Quinoa',              densityMin: 0.75, densityMax: 0.90, kcalPer100g: 120, category: 'grain',     proteinPer100g:  4.4, carbsPer100g: 21.0, fatPer100g:  1.9),
      FoodData(label: 'Couscous',            densityMin: 0.70, densityMax: 0.85, kcalPer100g: 112, category: 'grain',     proteinPer100g:  3.8, carbsPer100g: 23.0, fatPer100g:  0.2),
      FoodData(label: 'Barley',              densityMin: 0.75, densityMax: 0.90, kcalPer100g: 123, category: 'grain',     proteinPer100g:  2.3, carbsPer100g: 28.0, fatPer100g:  0.4),
      FoodData(label: 'Bulgur',              densityMin: 0.70, densityMax: 0.85, kcalPer100g:  83, category: 'grain',     proteinPer100g:  3.1, carbsPer100g: 19.0, fatPer100g:  0.2),
      FoodData(label: 'Polenta',             densityMin: 0.85, densityMax: 1.00, kcalPer100g:  85, category: 'grain',     proteinPer100g:  2.0, carbsPer100g: 17.0, fatPer100g:  1.0),
      FoodData(label: 'Brown Rice',          densityMin: 0.75, densityMax: 0.90, kcalPer100g: 123, category: 'grain',     proteinPer100g:  2.7, carbsPer100g: 26.0, fatPer100g:  1.0),
      FoodData(label: 'Wild Rice',           densityMin: 0.70, densityMax: 0.85, kcalPer100g: 101, category: 'grain',     proteinPer100g:  4.0, carbsPer100g: 21.0, fatPer100g:  0.3),
      FoodData(label: 'Cereal',              densityMin: 0.25, densityMax: 0.45, kcalPer100g: 379, category: 'grain',     proteinPer100g:  8.0, carbsPer100g: 84.0, fatPer100g:  1.5),
      FoodData(label: 'Granola',             densityMin: 0.45, densityMax: 0.60, kcalPer100g: 471, category: 'grain',     proteinPer100g: 10.0, carbsPer100g: 64.0, fatPer100g: 20.0),
      FoodData(label: 'Muesli',              densityMin: 0.40, densityMax: 0.55, kcalPer100g: 340, category: 'grain',     proteinPer100g: 10.0, carbsPer100g: 66.0, fatPer100g:  5.0),
      FoodData(label: 'Tortilla',            densityMin: 0.65, densityMax: 0.80, kcalPer100g: 237, category: 'grain',     proteinPer100g:  6.0, carbsPer100g: 40.0, fatPer100g:  5.6),
      FoodData(label: 'Pita Bread',          densityMin: 0.50, densityMax: 0.65, kcalPer100g: 275, category: 'grain',     proteinPer100g:  9.0, carbsPer100g: 55.0, fatPer100g:  1.2),
      FoodData(label: 'Bagel',               densityMin: 0.55, densityMax: 0.70, kcalPer100g: 257, category: 'grain',     proteinPer100g: 10.0, carbsPer100g: 50.0, fatPer100g:  1.6),
      FoodData(label: 'Croissant',           densityMin: 0.30, densityMax: 0.45, kcalPer100g: 406, category: 'grain',     proteinPer100g:  8.2, carbsPer100g: 46.0, fatPer100g: 21.0),
      FoodData(label: 'Pancake',             densityMin: 0.70, densityMax: 0.85, kcalPer100g: 227, category: 'grain',     proteinPer100g:  6.4, carbsPer100g: 28.0, fatPer100g: 10.0),
      FoodData(label: 'Waffle',              densityMin: 0.55, densityMax: 0.70, kcalPer100g: 291, category: 'grain',     proteinPer100g:  7.9, carbsPer100g: 33.0, fatPer100g: 14.0),
      FoodData(label: 'French Toast',        densityMin: 0.65, densityMax: 0.80, kcalPer100g: 229, category: 'grain',     proteinPer100g:  8.0, carbsPer100g: 26.0, fatPer100g: 10.0),
      FoodData(label: 'Cracker',             densityMin: 0.35, densityMax: 0.55, kcalPer100g: 484, category: 'grain',     proteinPer100g: 10.0, carbsPer100g: 67.0, fatPer100g: 20.0),

      // Prepared Meals
      FoodData(label: 'Burrito',             densityMin: 0.85, densityMax: 1.00, kcalPer100g: 180, category: 'mixed',     proteinPer100g:  9.0, carbsPer100g: 20.0, fatPer100g:  7.0),
      FoodData(label: 'Taco',                densityMin: 0.65, densityMax: 0.80, kcalPer100g: 226, category: 'mixed',     proteinPer100g: 12.0, carbsPer100g: 15.0, fatPer100g: 13.0),
      FoodData(label: 'Nachos',              densityMin: 0.45, densityMax: 0.60, kcalPer100g: 346, category: 'mixed',     proteinPer100g:  7.0, carbsPer100g: 37.0, fatPer100g: 19.0),
      FoodData(label: 'Quesadilla',          densityMin: 0.70, densityMax: 0.85, kcalPer100g: 255, category: 'mixed',     proteinPer100g: 12.0, carbsPer100g: 22.0, fatPer100g: 13.0),
      FoodData(label: 'Pad Thai',            densityMin: 0.80, densityMax: 0.95, kcalPer100g: 155, category: 'mixed',     proteinPer100g:  8.0, carbsPer100g: 18.0, fatPer100g:  6.0),
      FoodData(label: 'Fried Rice',          densityMin: 0.80, densityMax: 0.95, kcalPer100g: 163, category: 'mixed',     proteinPer100g:  5.0, carbsPer100g: 22.0, fatPer100g:  6.0),
      FoodData(label: 'Lasagna',             densityMin: 0.90, densityMax: 1.05, kcalPer100g: 135, category: 'mixed',     proteinPer100g:  8.0, carbsPer100g: 13.0, fatPer100g:  6.0),
      FoodData(label: 'Mac and Cheese',      densityMin: 0.85, densityMax: 1.00, kcalPer100g: 164, category: 'mixed',     proteinPer100g:  7.0, carbsPer100g: 17.0, fatPer100g:  8.0),
      FoodData(label: 'Risotto',             densityMin: 0.85, densityMax: 1.00, kcalPer100g: 143, category: 'mixed',     proteinPer100g:  4.0, carbsPer100g: 20.0, fatPer100g:  5.0),
      FoodData(label: 'Paella',              densityMin: 0.85, densityMax: 1.00, kcalPer100g: 150, category: 'mixed',     proteinPer100g:  8.0, carbsPer100g: 18.0, fatPer100g:  5.0),
      FoodData(label: 'Ramen',               densityMin: 0.90, densityMax: 1.05, kcalPer100g:  70, category: 'mixed',     proteinPer100g:  4.0, carbsPer100g:  8.0, fatPer100g:  2.5),
      FoodData(label: 'Pho',                 densityMin: 0.95, densityMax: 1.05, kcalPer100g:  45, category: 'mixed',     proteinPer100g:  3.5, carbsPer100g:  5.0, fatPer100g:  1.0),
      FoodData(label: 'Gyoza',               densityMin: 0.85, densityMax: 1.00, kcalPer100g: 230, category: 'mixed',     proteinPer100g: 10.0, carbsPer100g: 25.0, fatPer100g: 10.0),
      FoodData(label: 'Spring Roll',         densityMin: 0.65, densityMax: 0.80, kcalPer100g: 220, category: 'mixed',     proteinPer100g:  5.0, carbsPer100g: 28.0, fatPer100g: 10.0),
      FoodData(label: 'Sandwich',            densityMin: 0.55, densityMax: 0.75, kcalPer100g: 250, category: 'mixed',     proteinPer100g: 12.0, carbsPer100g: 28.0, fatPer100g: 10.0),
      FoodData(label: 'Wrap',                densityMin: 0.60, densityMax: 0.80, kcalPer100g: 220, category: 'mixed',     proteinPer100g: 10.0, carbsPer100g: 25.0, fatPer100g:  9.0),
      FoodData(label: 'Hot Dog',             densityMin: 0.80, densityMax: 0.95, kcalPer100g: 290, category: 'mixed',     proteinPer100g: 10.0, carbsPer100g: 18.0, fatPer100g: 20.0),
      FoodData(label: 'Kebab',               densityMin: 0.85, densityMax: 1.00, kcalPer100g: 200, category: 'mixed',     proteinPer100g: 15.0, carbsPer100g: 12.0, fatPer100g: 10.0),
      FoodData(label: 'Shawarma',            densityMin: 0.85, densityMax: 1.00, kcalPer100g: 215, category: 'mixed',     proteinPer100g: 14.0, carbsPer100g: 16.0, fatPer100g: 11.0),
      FoodData(label: 'Falafel',             densityMin: 0.80, densityMax: 0.95, kcalPer100g: 333, category: 'mixed',     proteinPer100g: 13.0, carbsPer100g: 32.0, fatPer100g: 18.0),
      FoodData(label: 'Hummus',              densityMin: 0.95, densityMax: 1.10, kcalPer100g: 166, category: 'mixed',     proteinPer100g:  8.0, carbsPer100g: 14.0, fatPer100g: 10.0),
      FoodData(label: 'Guacamole',           densityMin: 0.90, densityMax: 1.05, kcalPer100g: 160, category: 'mixed',     proteinPer100g:  2.0, carbsPer100g:  9.0, fatPer100g: 15.0),
      FoodData(label: 'Salsa',               densityMin: 0.95, densityMax: 1.05, kcalPer100g:  36, category: 'mixed',     proteinPer100g:  1.5, carbsPer100g:  7.0, fatPer100g:  0.2),
      FoodData(label: 'Fish and Chips',      densityMin: 0.65, densityMax: 0.80, kcalPer100g: 230, category: 'mixed',     proteinPer100g: 12.0, carbsPer100g: 22.0, fatPer100g: 11.0),
      FoodData(label: 'Chicken Nuggets',     densityMin: 0.65, densityMax: 0.80, kcalPer100g: 296, category: 'mixed',     proteinPer100g: 15.0, carbsPer100g: 18.0, fatPer100g: 18.0),
      FoodData(label: 'Fried Chicken',       densityMin: 0.80, densityMax: 0.95, kcalPer100g: 260, category: 'protein',   proteinPer100g: 24.0, carbsPer100g: 10.0, fatPer100g: 14.0),
      FoodData(label: 'Grilled Chicken',     densityMin: 1.00, densityMax: 1.10, kcalPer100g: 165, category: 'protein',   proteinPer100g: 31.0, carbsPer100g:  0.0, fatPer100g:  3.6),
      FoodData(label: 'Roast Beef',          densityMin: 1.00, densityMax: 1.10, kcalPer100g: 173, category: 'protein',   proteinPer100g: 28.0, carbsPer100g:  0.0, fatPer100g:  6.0),
      FoodData(label: 'Pulled Pork',         densityMin: 0.90, densityMax: 1.05, kcalPer100g: 200, category: 'protein',   proteinPer100g: 23.0, carbsPer100g:  5.0, fatPer100g: 10.0),
      FoodData(label: 'Chili',               densityMin: 0.90, densityMax: 1.05, kcalPer100g: 120, category: 'mixed',     proteinPer100g:  9.0, carbsPer100g: 10.0, fatPer100g:  5.0),

      // Vegetables (extended)
      FoodData(label: 'Zucchini',            densityMin: 0.70, densityMax: 0.85, kcalPer100g:  17, category: 'vegetable', proteinPer100g:  1.2, carbsPer100g:  3.1, fatPer100g:  0.3),
      FoodData(label: 'Artichoke',           densityMin: 0.75, densityMax: 0.90, kcalPer100g:  47, category: 'vegetable', proteinPer100g:  3.3, carbsPer100g: 11.0, fatPer100g:  0.2),
      FoodData(label: 'Beet',                densityMin: 0.90, densityMax: 1.05, kcalPer100g:  43, category: 'vegetable', proteinPer100g:  1.6, carbsPer100g: 10.0, fatPer100g:  0.2),
      FoodData(label: 'Brussels Sprouts',    densityMin: 0.50, densityMax: 0.65, kcalPer100g:  43, category: 'vegetable', proteinPer100g:  3.4, carbsPer100g:  9.0, fatPer100g:  0.3),
      FoodData(label: 'Kale',                densityMin: 0.20, densityMax: 0.35, kcalPer100g:  49, category: 'vegetable', proteinPer100g:  4.3, carbsPer100g:  9.0, fatPer100g:  0.9),
      FoodData(label: 'Swiss Chard',         densityMin: 0.25, densityMax: 0.40, kcalPer100g:  19, category: 'vegetable', proteinPer100g:  1.8, carbsPer100g:  3.7, fatPer100g:  0.2),
      FoodData(label: 'Radish',              densityMin: 0.85, densityMax: 0.95, kcalPer100g:  16, category: 'vegetable', proteinPer100g:  0.7, carbsPer100g:  3.4, fatPer100g:  0.1),
      FoodData(label: 'Turnip',              densityMin: 0.85, densityMax: 0.95, kcalPer100g:  28, category: 'vegetable', proteinPer100g:  0.9, carbsPer100g:  6.4, fatPer100g:  0.1),
      FoodData(label: 'Leek',                densityMin: 0.50, densityMax: 0.65, kcalPer100g:  61, category: 'vegetable', proteinPer100g:  1.5, carbsPer100g: 14.0, fatPer100g:  0.3),
      FoodData(label: 'Fennel',              densityMin: 0.55, densityMax: 0.70, kcalPer100g:  31, category: 'vegetable', proteinPer100g:  1.2, carbsPer100g:  7.3, fatPer100g:  0.2),
      FoodData(label: 'Endive',              densityMin: 0.25, densityMax: 0.40, kcalPer100g:  17, category: 'vegetable', proteinPer100g:  1.3, carbsPer100g:  3.4, fatPer100g:  0.2),
      FoodData(label: 'Watercress',          densityMin: 0.20, densityMax: 0.35, kcalPer100g:  11, category: 'vegetable', proteinPer100g:  2.3, carbsPer100g:  1.3, fatPer100g:  0.1),
      FoodData(label: 'Arugula',             densityMin: 0.20, densityMax: 0.35, kcalPer100g:  25, category: 'vegetable', proteinPer100g:  2.6, carbsPer100g:  3.7, fatPer100g:  0.7),
      FoodData(label: 'Coleslaw',            densityMin: 0.55, densityMax: 0.70, kcalPer100g:  99, category: 'vegetable', proteinPer100g:  1.0, carbsPer100g: 10.0, fatPer100g:  6.5),
      FoodData(label: 'Corn on the Cob',     densityMin: 0.85, densityMax: 0.95, kcalPer100g:  96, category: 'vegetable', proteinPer100g:  3.4, carbsPer100g: 21.0, fatPer100g:  1.5),
      FoodData(label: 'Roasted Vegetables',  densityMin: 0.55, densityMax: 0.70, kcalPer100g:  80, category: 'vegetable', proteinPer100g:  2.0, carbsPer100g: 10.0, fatPer100g:  4.0),
      FoodData(label: 'Pickles',             densityMin: 0.90, densityMax: 1.00, kcalPer100g:  11, category: 'vegetable', proteinPer100g:  0.3, carbsPer100g:  2.3, fatPer100g:  0.2),
      FoodData(label: 'Kimchi',              densityMin: 0.85, densityMax: 0.95, kcalPer100g:  15, category: 'vegetable', proteinPer100g:  1.1, carbsPer100g:  2.4, fatPer100g:  0.5),
      FoodData(label: 'Sauerkraut',          densityMin: 0.85, densityMax: 0.95, kcalPer100g:  19, category: 'vegetable', proteinPer100g:  0.9, carbsPer100g:  4.3, fatPer100g:  0.1),

      // Fruits (extended)
      FoodData(label: 'Coconut',             densityMin: 0.45, densityMax: 0.60, kcalPer100g: 354, category: 'fruit',     proteinPer100g:  3.3, carbsPer100g: 15.0, fatPer100g: 33.0),
      FoodData(label: 'Pomegranate',         densityMin: 0.80, densityMax: 0.90, kcalPer100g:  83, category: 'fruit',     proteinPer100g:  1.7, carbsPer100g: 19.0, fatPer100g:  1.2),
      FoodData(label: 'Passion Fruit',       densityMin: 0.80, densityMax: 0.90, kcalPer100g:  97, category: 'fruit',     proteinPer100g:  2.2, carbsPer100g: 23.0, fatPer100g:  0.7),
      FoodData(label: 'Papaya',              densityMin: 0.80, densityMax: 0.90, kcalPer100g:  43, category: 'fruit',     proteinPer100g:  0.5, carbsPer100g: 11.0, fatPer100g:  0.3),
      FoodData(label: 'Guava',               densityMin: 0.80, densityMax: 0.90, kcalPer100g:  68, category: 'fruit',     proteinPer100g:  2.6, carbsPer100g: 14.0, fatPer100g:  1.0),
      FoodData(label: 'Lychee',              densityMin: 0.85, densityMax: 0.95, kcalPer100g:  66, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g: 17.0, fatPer100g:  0.4),
      FoodData(label: 'Dragonfruit',         densityMin: 0.80, densityMax: 0.90, kcalPer100g:  60, category: 'fruit',     proteinPer100g:  1.2, carbsPer100g: 13.0, fatPer100g:  0.4),
      FoodData(label: 'Grapefruit',          densityMin: 0.80, densityMax: 0.90, kcalPer100g:  42, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g: 11.0, fatPer100g:  0.1),
      FoodData(label: 'Plum',                densityMin: 0.80, densityMax: 0.90, kcalPer100g:  46, category: 'fruit',     proteinPer100g:  0.7, carbsPer100g: 11.0, fatPer100g:  0.3),
      FoodData(label: 'Nectarine',           densityMin: 0.80, densityMax: 0.90, kcalPer100g:  44, category: 'fruit',     proteinPer100g:  1.1, carbsPer100g: 11.0, fatPer100g:  0.3),
      FoodData(label: 'Blackberry',          densityMin: 0.60, densityMax: 0.75, kcalPer100g:  43, category: 'fruit',     proteinPer100g:  1.4, carbsPer100g: 10.0, fatPer100g:  0.5),
      FoodData(label: 'Cranberry',           densityMin: 0.60, densityMax: 0.75, kcalPer100g:  46, category: 'fruit',     proteinPer100g:  0.4, carbsPer100g: 12.0, fatPer100g:  0.1),
      FoodData(label: 'Cantaloupe',          densityMin: 0.82, densityMax: 0.92, kcalPer100g:  34, category: 'fruit',     proteinPer100g:  0.8, carbsPer100g:  8.2, fatPer100g:  0.2),
      FoodData(label: 'Honeydew',            densityMin: 0.82, densityMax: 0.92, kcalPer100g:  36, category: 'fruit',     proteinPer100g:  0.5, carbsPer100g:  9.1, fatPer100g:  0.1),
      FoodData(label: 'Fruit Salad',         densityMin: 0.75, densityMax: 0.90, kcalPer100g:  50, category: 'fruit',     proteinPer100g:  0.5, carbsPer100g: 12.0, fatPer100g:  0.2),
      FoodData(label: 'Dried Fruit Mix',     densityMin: 0.60, densityMax: 0.75, kcalPer100g: 325, category: 'fruit',     proteinPer100g:  2.0, carbsPer100g: 80.0, fatPer100g:  0.5),
      FoodData(label: 'Raisins',             densityMin: 0.65, densityMax: 0.80, kcalPer100g: 299, category: 'fruit',     proteinPer100g:  3.1, carbsPer100g: 79.0, fatPer100g:  0.5),

      // Nuts & Seeds (extended)
      FoodData(label: 'Pistachio',           densityMin: 0.50, densityMax: 0.60, kcalPer100g: 560, category: 'nut',       proteinPer100g: 20.0, carbsPer100g: 28.0, fatPer100g: 45.0),
      FoodData(label: 'Pecan',               densityMin: 0.45, densityMax: 0.55, kcalPer100g: 691, category: 'nut',       proteinPer100g:  9.2, carbsPer100g: 14.0, fatPer100g: 72.0),
      FoodData(label: 'Macadamia',           densityMin: 0.55, densityMax: 0.65, kcalPer100g: 718, category: 'nut',       proteinPer100g:  7.9, carbsPer100g: 14.0, fatPer100g: 76.0),
      FoodData(label: 'Hazelnut',            densityMin: 0.55, densityMax: 0.65, kcalPer100g: 628, category: 'nut',       proteinPer100g: 15.0, carbsPer100g: 17.0, fatPer100g: 61.0),
      FoodData(label: 'Pine Nuts',           densityMin: 0.55, densityMax: 0.65, kcalPer100g: 673, category: 'nut',       proteinPer100g: 14.0, carbsPer100g: 13.0, fatPer100g: 68.0),
      FoodData(label: 'Sunflower Seeds',     densityMin: 0.45, densityMax: 0.55, kcalPer100g: 584, category: 'nut',       proteinPer100g: 21.0, carbsPer100g: 20.0, fatPer100g: 51.0),
      FoodData(label: 'Pumpkin Seeds',       densityMin: 0.50, densityMax: 0.60, kcalPer100g: 559, category: 'nut',       proteinPer100g: 30.0, carbsPer100g: 11.0, fatPer100g: 49.0),
      FoodData(label: 'Chia Seeds',          densityMin: 0.70, densityMax: 0.85, kcalPer100g: 486, category: 'nut',       proteinPer100g: 17.0, carbsPer100g: 42.0, fatPer100g: 31.0),
      FoodData(label: 'Flax Seeds',          densityMin: 0.65, densityMax: 0.80, kcalPer100g: 534, category: 'nut',       proteinPer100g: 18.0, carbsPer100g: 29.0, fatPer100g: 42.0),
      FoodData(label: 'Sesame Seeds',        densityMin: 0.60, densityMax: 0.75, kcalPer100g: 573, category: 'nut',       proteinPer100g: 18.0, carbsPer100g: 23.0, fatPer100g: 50.0),
      FoodData(label: 'Trail Mix',           densityMin: 0.55, densityMax: 0.70, kcalPer100g: 462, category: 'nut',       proteinPer100g: 14.0, carbsPer100g: 44.0, fatPer100g: 29.0),
      FoodData(label: 'Peanut Butter',       densityMin: 1.00, densityMax: 1.15, kcalPer100g: 588, category: 'nut',       proteinPer100g: 25.0, carbsPer100g: 20.0, fatPer100g: 50.0),
      FoodData(label: 'Almond Butter',       densityMin: 1.00, densityMax: 1.10, kcalPer100g: 614, category: 'nut',       proteinPer100g: 21.0, carbsPer100g: 19.0, fatPer100g: 56.0),

      // Legumes (extended)
      FoodData(label: 'Chickpeas',           densityMin: 0.80, densityMax: 0.90, kcalPer100g: 164, category: 'legume',    proteinPer100g:  9.0, carbsPer100g: 27.0, fatPer100g:  2.6),
      FoodData(label: 'Black Beans',         densityMin: 0.80, densityMax: 0.90, kcalPer100g: 132, category: 'legume',    proteinPer100g:  8.9, carbsPer100g: 24.0, fatPer100g:  0.5),
      FoodData(label: 'Lentils',             densityMin: 0.80, densityMax: 0.90, kcalPer100g: 116, category: 'legume',    proteinPer100g:  9.0, carbsPer100g: 20.0, fatPer100g:  0.4),
      FoodData(label: 'White Beans',         densityMin: 0.80, densityMax: 0.90, kcalPer100g: 139, category: 'legume',    proteinPer100g:  9.7, carbsPer100g: 25.0, fatPer100g:  0.4),
      FoodData(label: 'Edamame',             densityMin: 0.70, densityMax: 0.85, kcalPer100g: 121, category: 'legume',    proteinPer100g: 12.0, carbsPer100g:  9.0, fatPer100g:  5.2),
      FoodData(label: 'Green Peas',          densityMin: 0.70, densityMax: 0.85, kcalPer100g:  81, category: 'legume',    proteinPer100g:  5.4, carbsPer100g: 14.0, fatPer100g:  0.4),

      // Snacks & Sweets (extended)
      FoodData(label: 'Potato Chips',        densityMin: 0.06, densityMax: 0.12, kcalPer100g: 536, category: 'snack',     proteinPer100g:  7.0, carbsPer100g: 53.0, fatPer100g: 35.0),
      FoodData(label: 'Tortilla Chips',      densityMin: 0.10, densityMax: 0.18, kcalPer100g: 489, category: 'snack',     proteinPer100g:  7.0, carbsPer100g: 63.0, fatPer100g: 24.0),
      FoodData(label: 'Pretzel',             densityMin: 0.30, densityMax: 0.50, kcalPer100g: 380, category: 'snack',     proteinPer100g:  9.0, carbsPer100g: 79.0, fatPer100g:  3.5),
      FoodData(label: 'Granola Bar',         densityMin: 0.60, densityMax: 0.80, kcalPer100g: 440, category: 'snack',     proteinPer100g:  8.0, carbsPer100g: 63.0, fatPer100g: 18.0),
      FoodData(label: 'Protein Bar',         densityMin: 0.85, densityMax: 1.00, kcalPer100g: 350, category: 'snack',     proteinPer100g: 25.0, carbsPer100g: 35.0, fatPer100g: 12.0),
      FoodData(label: 'Energy Ball',         densityMin: 0.90, densityMax: 1.05, kcalPer100g: 400, category: 'snack',     proteinPer100g: 10.0, carbsPer100g: 45.0, fatPer100g: 20.0),
      FoodData(label: 'Cookie',              densityMin: 0.50, densityMax: 0.70, kcalPer100g: 488, category: 'snack',     proteinPer100g:  5.5, carbsPer100g: 65.0, fatPer100g: 23.0),
      FoodData(label: 'Brownie',             densityMin: 0.80, densityMax: 0.95, kcalPer100g: 466, category: 'snack',     proteinPer100g:  5.7, carbsPer100g: 54.0, fatPer100g: 25.0),
      FoodData(label: 'Donut',               densityMin: 0.35, densityMax: 0.50, kcalPer100g: 452, category: 'snack',     proteinPer100g:  5.0, carbsPer100g: 51.0, fatPer100g: 25.0),
      FoodData(label: 'Muffin',              densityMin: 0.45, densityMax: 0.60, kcalPer100g: 377, category: 'snack',     proteinPer100g:  5.5, carbsPer100g: 50.0, fatPer100g: 18.0),
      FoodData(label: 'Pie',                 densityMin: 0.60, densityMax: 0.80, kcalPer100g: 267, category: 'snack',     proteinPer100g:  3.0, carbsPer100g: 32.0, fatPer100g: 14.0),
      FoodData(label: 'Cheesecake',          densityMin: 0.90, densityMax: 1.05, kcalPer100g: 321, category: 'snack',     proteinPer100g:  5.5, carbsPer100g: 26.0, fatPer100g: 22.0),
      FoodData(label: 'Tiramisu',            densityMin: 0.70, densityMax: 0.85, kcalPer100g: 283, category: 'snack',     proteinPer100g:  5.0, carbsPer100g: 30.0, fatPer100g: 15.0),
      FoodData(label: 'Dark Chocolate',      densityMin: 1.15, densityMax: 1.35, kcalPer100g: 598, category: 'snack',     proteinPer100g:  7.8, carbsPer100g: 46.0, fatPer100g: 43.0),
      FoodData(label: 'White Chocolate',     densityMin: 1.10, densityMax: 1.30, kcalPer100g: 539, category: 'snack',     proteinPer100g:  6.0, carbsPer100g: 59.0, fatPer100g: 32.0),
      FoodData(label: 'Jelly',               densityMin: 0.95, densityMax: 1.05, kcalPer100g:  78, category: 'snack',     proteinPer100g:  1.7, carbsPer100g: 18.0, fatPer100g:  0.0),
      FoodData(label: 'Jam',                 densityMin: 1.10, densityMax: 1.25, kcalPer100g: 250, category: 'snack',     proteinPer100g:  0.4, carbsPer100g: 65.0, fatPer100g:  0.1),
      FoodData(label: 'Honey',               densityMin: 1.35, densityMax: 1.45, kcalPer100g: 304, category: 'snack',     proteinPer100g:  0.3, carbsPer100g: 82.0, fatPer100g:  0.0),
      FoodData(label: 'Maple Syrup',         densityMin: 1.30, densityMax: 1.40, kcalPer100g: 260, category: 'snack',     proteinPer100g:  0.0, carbsPer100g: 67.0, fatPer100g:  0.1),

      // Condiments & Sauces
      FoodData(label: 'Ketchup',             densityMin: 1.05, densityMax: 1.15, kcalPer100g: 101, category: 'mixed',     proteinPer100g:  1.0, carbsPer100g: 27.0, fatPer100g:  0.1),
      FoodData(label: 'Mustard',             densityMin: 1.00, densityMax: 1.10, kcalPer100g:  66, category: 'mixed',     proteinPer100g:  4.4, carbsPer100g:  5.3, fatPer100g:  4.0),
      FoodData(label: 'Mayonnaise',          densityMin: 0.90, densityMax: 1.00, kcalPer100g: 680, category: 'mixed',     proteinPer100g:  1.0, carbsPer100g:  0.6, fatPer100g: 75.0),
      FoodData(label: 'Soy Sauce',           densityMin: 1.10, densityMax: 1.20, kcalPer100g:  53, category: 'mixed',     proteinPer100g:  8.1, carbsPer100g:  5.0, fatPer100g:  0.0),
      FoodData(label: 'Olive Oil',           densityMin: 0.91, densityMax: 0.92, kcalPer100g: 884, category: 'mixed',     proteinPer100g:  0.0, carbsPer100g:  0.0, fatPer100g:100.0),
      FoodData(label: 'Vinegar',             densityMin: 1.00, densityMax: 1.02, kcalPer100g:  18, category: 'mixed',     proteinPer100g:  0.0, carbsPer100g:  0.6, fatPer100g:  0.0),
      FoodData(label: 'BBQ Sauce',           densityMin: 1.10, densityMax: 1.20, kcalPer100g: 172, category: 'mixed',     proteinPer100g:  0.8, carbsPer100g: 41.0, fatPer100g:  0.6),
      FoodData(label: 'Pesto',               densityMin: 0.95, densityMax: 1.10, kcalPer100g: 311, category: 'mixed',     proteinPer100g:  5.0, carbsPer100g:  6.0, fatPer100g: 30.0),
      FoodData(label: 'Ranch Dressing',      densityMin: 0.95, densityMax: 1.05, kcalPer100g: 310, category: 'mixed',     proteinPer100g:  1.0, carbsPer100g:  6.5, fatPer100g: 31.0),
      FoodData(label: 'Tahini',              densityMin: 1.00, densityMax: 1.15, kcalPer100g: 595, category: 'mixed',     proteinPer100g: 17.0, carbsPer100g: 21.0, fatPer100g: 54.0),

      // Drinks (extended)
      FoodData(label: 'Smoothie',            densityMin: 0.95, densityMax: 1.05, kcalPer100g:  60, category: 'drink',     proteinPer100g:  1.5, carbsPer100g: 13.0, fatPer100g:  0.5),
      FoodData(label: 'Hot Chocolate',       densityMin: 1.00, densityMax: 1.05, kcalPer100g:  77, category: 'drink',     proteinPer100g:  3.5, carbsPer100g: 10.5, fatPer100g:  2.5),
      FoodData(label: 'Lemonade',            densityMin: 1.00, densityMax: 1.05, kcalPer100g:  40, category: 'drink',     proteinPer100g:  0.0, carbsPer100g: 10.0, fatPer100g:  0.0),
      FoodData(label: 'Beer',                densityMin: 1.00, densityMax: 1.02, kcalPer100g:  43, category: 'drink',     proteinPer100g:  0.5, carbsPer100g:  3.6, fatPer100g:  0.0),
      FoodData(label: 'Protein Shake',       densityMin: 1.00, densityMax: 1.05, kcalPer100g:  70, category: 'drink',     proteinPer100g: 12.0, carbsPer100g:  5.0, fatPer100g:  1.0),
      FoodData(label: 'Coconut Water',       densityMin: 1.00, densityMax: 1.02, kcalPer100g:  19, category: 'drink',     proteinPer100g:  0.7, carbsPer100g:  3.7, fatPer100g:  0.2),
    ];

    final batch = db.batch();
    for (final food in seeds) {
      batch.insert('food_data', food.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  // ── food_data CRUD ───────────────────────────────────────────────────────

  Future<List<FoodData>> getAllFoods() async {
    final db = await database;
    final rows = await db.query('food_data', orderBy: 'label ASC');
    return rows.map(FoodData.fromMap).toList();
  }

  Future<FoodData?> getFoodByLabel(String label) async {
    final db = await database;
    final rows = await db.query(
      'food_data',
      where: 'label = ? COLLATE NOCASE',
      whereArgs: [label],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FoodData.fromMap(rows.first);
  }

  Future<int> insertFood(FoodData food) async {
    final db = await database;
    return db.insert('food_data', food.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── scan_results CRUD ────────────────────────────────────────────────────

  Future<int> insertScanResult(ScanResult result) async {
    final db = await database;
    final scanId = await db.insert('scan_results', result.toMap());

    final batch = db.batch();
    for (final food in result.foods) {
      batch.insert('detected_foods', {
        ...food.toMap(),
        'scan_id': scanId,
      });
    }
    await batch.commit(noResult: true);
    return scanId;
  }

  Future<List<ScanResult>> getAllScanResults() async {
    final db = await database;
    final scanRows =
        await db.query('scan_results', orderBy: 'timestamp DESC');
    final results = <ScanResult>[];

    for (final row in scanRows) {
      final foodRows = await db.query(
        'detected_foods',
        where: 'scan_id = ?',
        whereArgs: [row['id']],
      );
      results.add(ScanResult.fromMap(
        row,
        foods: foodRows.map(DetectedFood.fromMap).toList(),
      ));
    }
    return results;
  }

  Future<void> deleteScanResult(int scanId) async {
    final db = await database;
    await db.delete('detected_foods', where: 'scan_id = ?', whereArgs: [scanId]);
    await db.delete('scan_results', where: 'id = ?', whereArgs: [scanId]);
  }

  Future<void> updateDetectedFood(
    int foodId, {
    required String label,
    required double caloriesMin,
    required double caloriesMax,
  }) async {
    final db = await database;
    await db.update(
      'detected_foods',
      {
        'label': label,
        'calories_min': caloriesMin,
        'calories_max': caloriesMax,
      },
      where: 'id = ?',
      whereArgs: [foodId],
    );
  }

  Future<void> deleteFood(int foodId) async {
    final db = await database;
    await db.delete('food_data', where: 'id = ?', whereArgs: [foodId]);
  }

  // ── user_preferences CRUD ────────────────────────────────────────────────

  Future<UserPreferences> getUserPreferences() async {
    final db = await database;
    final rows = await db.query('user_preferences', limit: 1);
    if (rows.isEmpty) return const UserPreferences();
    return UserPreferences.fromMap(rows.first);
  }

  Future<void> saveUserPreferences(UserPreferences prefs) async {
    final db = await database;
    final rows = await db.query('user_preferences', limit: 1);
    if (rows.isEmpty) {
      await db.insert('user_preferences', prefs.toMap());
    } else {
      await db.update(
        'user_preferences',
        prefs.toMap(),
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    }
  }

  // ── ground_truth CRUD ────────────────────────────────────────────────────

  Future<int> insertGroundTruth(GroundTruth gt) async {
    final db = await database;
    return db.insert('ground_truth', gt.toMap());
  }

  Future<List<GroundTruth>> getGroundTruthForScan(int scanId) async {
    final db = await database;
    final rows = await db.query(
      'ground_truth',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    return rows.map(GroundTruth.fromMap).toList();
  }

  Future<GroundTruth?> getGroundTruthForFood(int detectedFoodId) async {
    final db = await database;
    final rows = await db.query(
      'ground_truth',
      where: 'detected_food_id = ?',
      whereArgs: [detectedFoodId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GroundTruth.fromMap(rows.first);
  }

  Future<List<GroundTruth>> getAllGroundTruths() async {
    final db = await database;
    final rows = await db.query('ground_truth', orderBy: 'timestamp DESC');
    return rows.map(GroundTruth.fromMap).toList();
  }

  Future<void> deleteGroundTruth(int gtId) async {
    final db = await database;
    await db.delete('ground_truth', where: 'id = ?', whereArgs: [gtId]);
  }

  // ── Benchmarks (Part 17) ────────────────────────────────────────────────

  Future<int> insertBenchmark(ScanBenchmark benchmark) async {
    final db = await database;
    return db.insert('benchmarks', benchmark.toMap());
  }

  Future<List<ScanBenchmark>> getAllBenchmarks() async {
    final db = await database;
    final rows = await db.query('benchmarks', orderBy: 'timestamp DESC');
    return rows.map(ScanBenchmark.fromMap).toList();
  }

  Future<ScanBenchmark?> getBenchmarkForScan(int scanId) async {
    final db = await database;
    final rows = await db.query(
      'benchmarks',
      where: 'scan_id = ?',
      whereArgs: [scanId],
    );
    if (rows.isEmpty) return null;
    return ScanBenchmark.fromMap(rows.first);
  }

  // ── Grocery list ────────────────────────────────────────────────────────

  Future<List<GroceryItem>> getGroceryItems() async {
    final db = await database;
    final rows = await db.query('grocery_list', orderBy: 'checked ASC, created_at DESC');
    return rows.map(GroceryItem.fromMap).toList();
  }

  Future<int> insertGroceryItem(GroceryItem item) async {
    final db = await database;
    return db.insert('grocery_list', item.toMap());
  }

  Future<void> updateGroceryItem(GroceryItem item) async {
    final db = await database;
    await db.update(
      'grocery_list',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteGroceryItem(int id) async {
    final db = await database;
    await db.delete('grocery_list', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearCheckedGroceryItems() async {
    final db = await database;
    await db.delete('grocery_list', where: 'checked = 1');
  }
}
