import 'dart:convert';
import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Result from a native barcode scan + OpenFoodFacts lookup.
class BarcodeFood {
  final String barcode;
  final String name;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double? servingGrams;
  // Extended nutrients
  final double fiberPer100g;
  final double sugarsPer100g;
  final double saturatedFatPer100g;
  final double sodiumMgPer100g;
  final double cholesterolMgPer100g;
  // Vitamins
  final double vitaminAUgPer100g;
  final double vitaminCMgPer100g;
  final double vitaminDUgPer100g;
  final double vitaminEMgPer100g;
  final double vitaminKUgPer100g;
  final double vitaminB12UgPer100g;
  final double folateUgPer100g;
  // Minerals
  final double calciumMgPer100g;
  final double ironMgPer100g;
  final double magnesiumMgPer100g;
  final double potassiumMgPer100g;
  final double zincMgPer100g;

  const BarcodeFood({
    required this.barcode,
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.servingGrams,
    this.fiberPer100g = 0,
    this.sugarsPer100g = 0,
    this.saturatedFatPer100g = 0,
    this.sodiumMgPer100g = 0,
    this.cholesterolMgPer100g = 0,
    this.vitaminAUgPer100g = 0,
    this.vitaminCMgPer100g = 0,
    this.vitaminDUgPer100g = 0,
    this.vitaminEMgPer100g = 0,
    this.vitaminKUgPer100g = 0,
    this.vitaminB12UgPer100g = 0,
    this.folateUgPer100g = 0,
    this.calciumMgPer100g = 0,
    this.ironMgPer100g = 0,
    this.magnesiumMgPer100g = 0,
    this.potassiumMgPer100g = 0,
    this.zincMgPer100g = 0,
  });

  factory BarcodeFood.fromMap(Map<String, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0.0;
    return BarcodeFood(
      barcode:        m['barcode']       as String,
      name:           m['name']          as String,
      kcalPer100g:    (m['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (m['protein']       as num).toDouble(),
      carbsPer100g:   (m['carbs']         as num).toDouble(),
      fatPer100g:     (m['fat']           as num).toDouble(),
      servingGrams:   (m['serving_grams'] as num?)?.toDouble(),
      fiberPer100g:   d('fiber'),
      sugarsPer100g:  d('sugars'),
      saturatedFatPer100g: d('saturated_fat'),
      sodiumMgPer100g:     d('sodium_mg'),
      cholesterolMgPer100g: d('cholesterol_mg'),
      vitaminAUgPer100g:   d('vitamin_a_ug'),
      vitaminCMgPer100g:   d('vitamin_c_mg'),
      vitaminDUgPer100g:   d('vitamin_d_ug'),
      vitaminEMgPer100g:   d('vitamin_e_mg'),
      vitaminKUgPer100g:   d('vitamin_k_ug'),
      vitaminB12UgPer100g: d('vitamin_b12_ug'),
      folateUgPer100g:     d('folate_ug'),
      calciumMgPer100g:    d('calcium_mg'),
      ironMgPer100g:       d('iron_mg'),
      magnesiumMgPer100g:  d('magnesium_mg'),
      potassiumMgPer100g:  d('potassium_mg'),
      zincMgPer100g:       d('zinc_mg'),
    );
  }
}

/// Delegates barcode scanning + OpenFoodFacts lookup to the native Swift side.
/// Uses AVFoundation (built-in iOS) — no third-party packages required.
class BarcodeLookupService {
  BarcodeLookupService._();
  static final BarcodeLookupService instance = BarcodeLookupService._();

  static const _channel =
      MethodChannel(AppConstants.methodChannelName);

  /// Present the native barcode scanner, scan, and return nutrition data.
  /// Returns null if the user cancels or the product has no nutrition data.
  Future<BarcodeFood?> scanAndLookup() async {
    try {
      final raw = await _channel.invokeMethod<String>('scanBarcode');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return BarcodeFood.fromMap(map);
    } on PlatformException catch (e) {
      // Log but don't rethrow — null means "nothing found".
      // ignore: avoid_print
      print('[BarcodeLookupService] $e');
      return null;
    }
  }
}

