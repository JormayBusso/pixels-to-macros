import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';

/// Singleton service wrapping the local SQLite database.
///
/// Tables:
///   • food_data    – reference densities & kcal (seeded on first run)
///   • scan_results – historical scan metadata
///   • detected_foods – per-scan detected items
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
      version: 1,
      onCreate: _onCreate,
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
  }

  // ── Seed data (Step 1 — Apple, Rice, Chicken) ────────────────────────────

  Future<void> _seed(Database db) async {
    const seeds = [
      FoodData(
        label: 'Apple',
        densityMin: 0.75,
        densityMax: 0.85,
        kcalPer100g: 52,
        category: 'fruit',
      ),
      FoodData(
        label: 'Rice',
        densityMin: 0.75,
        densityMax: 0.90,
        kcalPer100g: 130,
        category: 'grain',
      ),
      FoodData(
        label: 'Chicken',
        densityMin: 1.00,
        densityMax: 1.10,
        kcalPer100g: 165,
        category: 'protein',
      ),
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
}
