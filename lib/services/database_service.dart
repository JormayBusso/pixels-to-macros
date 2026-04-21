import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../models/user_preferences.dart';

/// Singleton service wrapping the local SQLite database.
///
/// Tables:
///   • food_data    – reference densities & kcal (seeded on first run)
///   • scan_results – historical scan metadata
///   • detected_foods – per-scan detected items
///   • user_preferences – name, calorie goal, onboarding flag
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
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // food_data — reference table
    await db.execute('''
      CREATE TABLE food_data (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        label         TEXT    NOT NULL UNIQUE,
        density_min   REAL    NOT NULL,
        density_max   REAL    NOT NULL,
        kcal_per_100g REAL    NOT NULL,
        category      TEXT    NOT NULL
      )
    ''');

    // scan_results — one row per scan session
    await db.execute('''
      CREATE TABLE scan_results (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp  TEXT    NOT NULL,
        depth_mode TEXT    NOT NULL
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
        has_seen_scan_tutorial   INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('user_preferences', const UserPreferences().toMap());
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
  }

  // ── Seed data (42 items across 6 categories) ────────────────────────────

  Future<void> _seed(Database db) async {
    const seeds = [
      // ── Fruits ──────────────────────────────────────────────────────────
      FoodData(label: 'Apple', densityMin: 0.75, densityMax: 0.85, kcalPer100g: 52, category: 'fruit'),
      FoodData(label: 'Banana', densityMin: 0.80, densityMax: 0.95, kcalPer100g: 89, category: 'fruit'),
      FoodData(label: 'Orange', densityMin: 0.75, densityMax: 0.85, kcalPer100g: 47, category: 'fruit'),
      FoodData(label: 'Strawberry', densityMin: 0.55, densityMax: 0.65, kcalPer100g: 32, category: 'fruit'),
      FoodData(label: 'Grapes', densityMin: 0.80, densityMax: 0.90, kcalPer100g: 69, category: 'fruit'),
      FoodData(label: 'Watermelon', densityMin: 0.60, densityMax: 0.70, kcalPer100g: 30, category: 'fruit'),
      FoodData(label: 'Mango', densityMin: 0.75, densityMax: 0.85, kcalPer100g: 60, category: 'fruit'),
      FoodData(label: 'Pineapple', densityMin: 0.70, densityMax: 0.80, kcalPer100g: 50, category: 'fruit'),

      // ── Vegetables ──────────────────────────────────────────────────────
      FoodData(label: 'Broccoli', densityMin: 0.40, densityMax: 0.55, kcalPer100g: 34, category: 'vegetable'),
      FoodData(label: 'Carrot', densityMin: 0.85, densityMax: 0.95, kcalPer100g: 41, category: 'vegetable'),
      FoodData(label: 'Tomato', densityMin: 0.70, densityMax: 0.80, kcalPer100g: 18, category: 'vegetable'),
      FoodData(label: 'Cucumber', densityMin: 0.60, densityMax: 0.70, kcalPer100g: 15, category: 'vegetable'),
      FoodData(label: 'Lettuce', densityMin: 0.20, densityMax: 0.35, kcalPer100g: 15, category: 'vegetable'),
      FoodData(label: 'Potato', densityMin: 0.90, densityMax: 1.05, kcalPer100g: 77, category: 'vegetable'),
      FoodData(label: 'Sweet Potato', densityMin: 0.85, densityMax: 1.00, kcalPer100g: 86, category: 'vegetable'),
      FoodData(label: 'Spinach', densityMin: 0.25, densityMax: 0.40, kcalPer100g: 23, category: 'vegetable'),
      FoodData(label: 'Bell Pepper', densityMin: 0.45, densityMax: 0.55, kcalPer100g: 31, category: 'vegetable'),
      FoodData(label: 'Onion', densityMin: 0.85, densityMax: 0.95, kcalPer100g: 40, category: 'vegetable'),

      // ── Grains & Starches ───────────────────────────────────────────────
      FoodData(label: 'Rice', densityMin: 0.75, densityMax: 0.90, kcalPer100g: 130, category: 'grain'),
      FoodData(label: 'Pasta', densityMin: 0.80, densityMax: 0.95, kcalPer100g: 131, category: 'grain'),
      FoodData(label: 'Bread', densityMin: 0.30, densityMax: 0.45, kcalPer100g: 265, category: 'grain'),
      FoodData(label: 'Noodles', densityMin: 0.70, densityMax: 0.85, kcalPer100g: 138, category: 'grain'),
      FoodData(label: 'Oatmeal', densityMin: 0.65, densityMax: 0.80, kcalPer100g: 71, category: 'grain'),
      FoodData(label: 'Corn', densityMin: 0.70, densityMax: 0.85, kcalPer100g: 86, category: 'grain'),

      // ── Proteins ────────────────────────────────────────────────────────
      FoodData(label: 'Chicken', densityMin: 1.00, densityMax: 1.10, kcalPer100g: 165, category: 'protein'),
      FoodData(label: 'Beef', densityMin: 1.00, densityMax: 1.15, kcalPer100g: 250, category: 'protein'),
      FoodData(label: 'Pork', densityMin: 1.00, densityMax: 1.10, kcalPer100g: 242, category: 'protein'),
      FoodData(label: 'Fish', densityMin: 0.95, densityMax: 1.05, kcalPer100g: 206, category: 'protein'),
      FoodData(label: 'Salmon', densityMin: 0.95, densityMax: 1.05, kcalPer100g: 208, category: 'protein'),
      FoodData(label: 'Shrimp', densityMin: 0.90, densityMax: 1.00, kcalPer100g: 99, category: 'protein'),
      FoodData(label: 'Egg', densityMin: 0.95, densityMax: 1.05, kcalPer100g: 155, category: 'protein'),
      FoodData(label: 'Tofu', densityMin: 0.90, densityMax: 1.00, kcalPer100g: 76, category: 'protein'),

      // ── Dairy ───────────────────────────────────────────────────────────
      FoodData(label: 'Cheese', densityMin: 1.00, densityMax: 1.15, kcalPer100g: 402, category: 'dairy'),
      FoodData(label: 'Yogurt', densityMin: 1.00, densityMax: 1.10, kcalPer100g: 59, category: 'dairy'),

      // ── Mixed / Prepared ────────────────────────────────────────────────
      FoodData(label: 'Salad', densityMin: 0.25, densityMax: 0.45, kcalPer100g: 20, category: 'mixed'),
      FoodData(label: 'Soup', densityMin: 0.95, densityMax: 1.05, kcalPer100g: 40, category: 'mixed'),
      FoodData(label: 'Stew', densityMin: 0.90, densityMax: 1.05, kcalPer100g: 90, category: 'mixed'),
      FoodData(label: 'Curry', densityMin: 0.90, densityMax: 1.05, kcalPer100g: 110, category: 'mixed'),
      FoodData(label: 'Pizza', densityMin: 0.60, densityMax: 0.80, kcalPer100g: 266, category: 'mixed'),
      FoodData(label: 'Sushi', densityMin: 0.85, densityMax: 1.00, kcalPer100g: 143, category: 'mixed'),
      FoodData(label: 'Fries', densityMin: 0.45, densityMax: 0.60, kcalPer100g: 312, category: 'mixed'),
      FoodData(label: 'Cake', densityMin: 0.55, densityMax: 0.70, kcalPer100g: 347, category: 'mixed'),
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
}
