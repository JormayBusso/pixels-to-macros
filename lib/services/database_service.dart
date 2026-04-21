import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/food_data.dart';
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
      version: 8,
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
        daily_fat_target_g       INTEGER NOT NULL DEFAULT 65
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

  // ── Seed data (42 items across 6 categories) ────────────────────────────

  Future<void> _seed(Database db) async {
    const seeds = [
      // ── Fruits ──────────────────────────────────────────────────────────
      FoodData(label: 'Apple',      densityMin: 0.75, densityMax: 0.85, kcalPer100g:  52, category: 'fruit',     proteinPer100g: 0.3, carbsPer100g: 14.0, fatPer100g: 0.2),
      FoodData(label: 'Banana',     densityMin: 0.80, densityMax: 0.95, kcalPer100g:  89, category: 'fruit',     proteinPer100g: 1.1, carbsPer100g: 23.0, fatPer100g: 0.3),
      FoodData(label: 'Orange',     densityMin: 0.75, densityMax: 0.85, kcalPer100g:  47, category: 'fruit',     proteinPer100g: 0.9, carbsPer100g: 12.0, fatPer100g: 0.1),
      FoodData(label: 'Strawberry', densityMin: 0.55, densityMax: 0.65, kcalPer100g:  32, category: 'fruit',     proteinPer100g: 0.7, carbsPer100g:  7.7, fatPer100g: 0.3),
      FoodData(label: 'Grapes',     densityMin: 0.80, densityMax: 0.90, kcalPer100g:  69, category: 'fruit',     proteinPer100g: 0.7, carbsPer100g: 18.0, fatPer100g: 0.2),
      FoodData(label: 'Watermelon', densityMin: 0.60, densityMax: 0.70, kcalPer100g:  30, category: 'fruit',     proteinPer100g: 0.6, carbsPer100g:  7.6, fatPer100g: 0.2),
      FoodData(label: 'Mango',      densityMin: 0.75, densityMax: 0.85, kcalPer100g:  60, category: 'fruit',     proteinPer100g: 0.8, carbsPer100g: 15.0, fatPer100g: 0.4),
      FoodData(label: 'Pineapple',  densityMin: 0.70, densityMax: 0.80, kcalPer100g:  50, category: 'fruit',     proteinPer100g: 0.5, carbsPer100g: 13.0, fatPer100g: 0.1),

      // ── Vegetables ──────────────────────────────────────────────────────
      FoodData(label: 'Broccoli',     densityMin: 0.40, densityMax: 0.55, kcalPer100g:  34, category: 'vegetable', proteinPer100g: 2.8, carbsPer100g:  7.2, fatPer100g: 0.4),
      FoodData(label: 'Carrot',       densityMin: 0.85, densityMax: 0.95, kcalPer100g:  41, category: 'vegetable', proteinPer100g: 0.9, carbsPer100g: 10.0, fatPer100g: 0.2),
      FoodData(label: 'Tomato',       densityMin: 0.70, densityMax: 0.80, kcalPer100g:  18, category: 'vegetable', proteinPer100g: 0.9, carbsPer100g:  3.9, fatPer100g: 0.2),
      FoodData(label: 'Cucumber',     densityMin: 0.60, densityMax: 0.70, kcalPer100g:  15, category: 'vegetable', proteinPer100g: 0.7, carbsPer100g:  3.6, fatPer100g: 0.1),
      FoodData(label: 'Lettuce',      densityMin: 0.20, densityMax: 0.35, kcalPer100g:  15, category: 'vegetable', proteinPer100g: 1.4, carbsPer100g:  2.9, fatPer100g: 0.2),
      FoodData(label: 'Potato',       densityMin: 0.90, densityMax: 1.05, kcalPer100g:  77, category: 'vegetable', proteinPer100g: 2.0, carbsPer100g: 17.0, fatPer100g: 0.1),
      FoodData(label: 'Sweet Potato', densityMin: 0.85, densityMax: 1.00, kcalPer100g:  86, category: 'vegetable', proteinPer100g: 1.6, carbsPer100g: 20.0, fatPer100g: 0.1),
      FoodData(label: 'Spinach',      densityMin: 0.25, densityMax: 0.40, kcalPer100g:  23, category: 'vegetable', proteinPer100g: 2.9, carbsPer100g:  3.6, fatPer100g: 0.4),
      FoodData(label: 'Bell Pepper',  densityMin: 0.45, densityMax: 0.55, kcalPer100g:  31, category: 'vegetable', proteinPer100g: 1.0, carbsPer100g:  6.0, fatPer100g: 0.3),
      FoodData(label: 'Onion',        densityMin: 0.85, densityMax: 0.95, kcalPer100g:  40, category: 'vegetable', proteinPer100g: 1.1, carbsPer100g:  9.3, fatPer100g: 0.1),

      // ── Grains & Starches ───────────────────────────────────────────────
      FoodData(label: 'Rice',       densityMin: 0.75, densityMax: 0.90, kcalPer100g: 130, category: 'grain', proteinPer100g:  2.7, carbsPer100g: 28.0, fatPer100g: 0.3),
      FoodData(label: 'Pasta',      densityMin: 0.80, densityMax: 0.95, kcalPer100g: 131, category: 'grain', proteinPer100g:  5.1, carbsPer100g: 25.0, fatPer100g: 0.9),
      FoodData(label: 'Bread',      densityMin: 0.30, densityMax: 0.45, kcalPer100g: 265, category: 'grain', proteinPer100g:  9.0, carbsPer100g: 49.0, fatPer100g: 3.2),
      FoodData(label: 'Noodles',    densityMin: 0.70, densityMax: 0.85, kcalPer100g: 138, category: 'grain', proteinPer100g:  4.5, carbsPer100g: 25.0, fatPer100g: 1.0),
      FoodData(label: 'Oatmeal',    densityMin: 0.65, densityMax: 0.80, kcalPer100g:  71, category: 'grain', proteinPer100g:  2.5, carbsPer100g: 12.0, fatPer100g: 1.5),
      FoodData(label: 'Corn',       densityMin: 0.70, densityMax: 0.85, kcalPer100g:  86, category: 'grain', proteinPer100g:  3.3, carbsPer100g: 19.0, fatPer100g: 1.4),

      // ── Proteins ────────────────────────────────────────────────────────
      FoodData(label: 'Chicken', densityMin: 1.00, densityMax: 1.10, kcalPer100g: 165, category: 'protein', proteinPer100g: 31.0, carbsPer100g:  0.0, fatPer100g:  3.6),
      FoodData(label: 'Beef',    densityMin: 1.00, densityMax: 1.15, kcalPer100g: 250, category: 'protein', proteinPer100g: 26.0, carbsPer100g:  0.0, fatPer100g: 17.0),
      FoodData(label: 'Pork',    densityMin: 1.00, densityMax: 1.10, kcalPer100g: 242, category: 'protein', proteinPer100g: 25.0, carbsPer100g:  0.0, fatPer100g: 14.0),
      FoodData(label: 'Fish',    densityMin: 0.95, densityMax: 1.05, kcalPer100g: 206, category: 'protein', proteinPer100g: 22.0, carbsPer100g:  0.0, fatPer100g: 12.0),
      FoodData(label: 'Salmon',  densityMin: 0.95, densityMax: 1.05, kcalPer100g: 208, category: 'protein', proteinPer100g: 20.0, carbsPer100g:  0.0, fatPer100g: 13.0),
      FoodData(label: 'Shrimp',  densityMin: 0.90, densityMax: 1.00, kcalPer100g:  99, category: 'protein', proteinPer100g: 20.0, carbsPer100g:  0.9, fatPer100g:  1.7),
      FoodData(label: 'Egg',     densityMin: 0.95, densityMax: 1.05, kcalPer100g: 155, category: 'protein', proteinPer100g: 13.0, carbsPer100g:  1.1, fatPer100g: 11.0),
      FoodData(label: 'Tofu',    densityMin: 0.90, densityMax: 1.00, kcalPer100g:  76, category: 'protein', proteinPer100g:  8.1, carbsPer100g:  2.0, fatPer100g:  4.2),

      // ── Dairy ───────────────────────────────────────────────────────────
      FoodData(label: 'Cheese', densityMin: 1.00, densityMax: 1.15, kcalPer100g: 402, category: 'dairy', proteinPer100g: 25.0, carbsPer100g:  1.3, fatPer100g: 33.0),
      FoodData(label: 'Yogurt', densityMin: 1.00, densityMax: 1.10, kcalPer100g:  59, category: 'dairy', proteinPer100g: 10.0, carbsPer100g:  3.6, fatPer100g:  0.4),

      // ── Mixed / Prepared ────────────────────────────────────────────────
      FoodData(label: 'Salad', densityMin: 0.25, densityMax: 0.45, kcalPer100g:  20, category: 'mixed', proteinPer100g:  1.5, carbsPer100g:  3.0, fatPer100g:  0.5),
      FoodData(label: 'Soup',  densityMin: 0.95, densityMax: 1.05, kcalPer100g:  40, category: 'mixed', proteinPer100g:  2.0, carbsPer100g:  6.0, fatPer100g:  1.5),
      FoodData(label: 'Stew',  densityMin: 0.90, densityMax: 1.05, kcalPer100g:  90, category: 'mixed', proteinPer100g:  8.0, carbsPer100g: 10.0, fatPer100g:  4.0),
      FoodData(label: 'Curry', densityMin: 0.90, densityMax: 1.05, kcalPer100g: 110, category: 'mixed', proteinPer100g:  7.0, carbsPer100g: 12.0, fatPer100g:  5.0),
      FoodData(label: 'Pizza', densityMin: 0.60, densityMax: 0.80, kcalPer100g: 266, category: 'mixed', proteinPer100g: 11.0, carbsPer100g: 33.0, fatPer100g: 10.0),
      FoodData(label: 'Sushi', densityMin: 0.85, densityMax: 1.00, kcalPer100g: 143, category: 'mixed', proteinPer100g:  6.7, carbsPer100g: 19.0, fatPer100g:  5.0),
      FoodData(label: 'Fries', densityMin: 0.45, densityMax: 0.60, kcalPer100g: 312, category: 'mixed', proteinPer100g:  3.4, carbsPer100g: 41.0, fatPer100g: 15.0),
      FoodData(label: 'Cake',  densityMin: 0.55, densityMax: 0.70, kcalPer100g: 347, category: 'mixed', proteinPer100g:  4.5, carbsPer100g: 55.0, fatPer100g: 14.0),
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
      where: 'label = ?',
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
}
