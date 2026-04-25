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

  const BarcodeFood({
    required this.barcode,
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.servingGrams,
  });

  factory BarcodeFood.fromMap(Map<String, dynamic> m) {
    return BarcodeFood(
      barcode:        m['barcode']       as String,
      name:           m['name']          as String,
      kcalPer100g:    (m['kcal_per_100g'] as num).toDouble(),
      proteinPer100g: (m['protein']       as num).toDouble(),
      carbsPer100g:   (m['carbs']         as num).toDouble(),
      fatPer100g:     (m['fat']           as num).toDouble(),
      servingGrams:   (m['serving_grams'] as num?)?.toDouble(),
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

