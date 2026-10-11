import 'dart:math' as math;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../models/pantry_item.dart';

class PantryPhotoCandidate {
  const PantryPhotoCandidate(this.name, {this.quantity = 1, this.unit});

  final String name;
  final double quantity;
  final String? unit;
}

/// Photos are observations of stock, not separate purchases.
List<PantryPhotoCandidate> mergePantryCandidates(
    Iterable<PantryPhotoCandidate> candidates) {
  final merged = <String, PantryPhotoCandidate>{};
  for (final candidate in candidates) {
    if (candidate.name.trim().isEmpty ||
        !candidate.quantity.isFinite ||
        candidate.quantity <= 0) {
      continue;
    }
    final key = PantryItem.normalizeKey(candidate.name);
    final previous = merged[key];
    // Different units cannot safely be combined; leave the first for review.
    if (previous == null ||
        (previous.quantity == 1 &&
            previous.unit == null &&
            candidate.unit != null) ||
        ((previous.unit ?? '') == (candidate.unit ?? '') &&
            candidate.quantity > previous.quantity)) {
      merged[key] = candidate;
    }
  }
  return merged.values.toList();
}

class PantryPhotoService {
  PantryPhotoService({
    required this.aliases,
    ImagePicker? picker,
    Future<List<XFile>> Function(ImageSource)? photoPicker,
    Future<List<PantryPhotoCandidate>> Function(XFile)? analyzer,
  })  : _picker = picker ?? ImagePicker(),
        _photoPicker = photoPicker,
        _analyzer = analyzer;

  final Map<String, String> aliases;
  final ImagePicker _picker;
  final Future<List<XFile>> Function(ImageSource)? _photoPicker;
  final Future<List<PantryPhotoCandidate>> Function(XFile)? _analyzer;

  Future<List<XFile>> pick(ImageSource source) async {
    if (_photoPicker != null) return _photoPicker(source);
    if (source == ImageSource.gallery) {
      return _picker.pickMultiImage(
          maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    }
    final photo = await _picker.pickImage(
        source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    return photo == null ? [] : [photo];
  }

  static List<String> matchProducts(String raw, Map<String, String> aliases) {
    var text = raw.toLowerCase();
    final entries = aliases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    final found = <String>{};
    for (final entry in entries) {
      final pattern = RegExp(
          '(?<![a-zà-ž])${RegExp.escape(entry.key)}(?![a-zà-ž])',
          caseSensitive: false);
      if (pattern.hasMatch(text)) {
        found.add(entry.value);
        // Consume longer phrases so almond milk is never also almond + milk.
        text = text.replaceAll(pattern, ' ');
      }
    }
    return found.toList();
  }

  Future<List<PantryPhotoCandidate>> analyzeAll(Iterable<XFile> photos) async {
    final seen = <String>{};
    final candidates = <PantryPhotoCandidate>[];
    for (final photo in photos) {
      if (!seen.add(photo.path)) continue;
      candidates.addAll(await (_analyzer?.call(photo) ?? analyze(photo)));
    }
    return mergePantryCandidates(candidates);
  }

  static List<PantryPhotoCandidate> textCandidates(
      String text, Map<String, String> aliases) {
    final candidates = <PantryPhotoCandidate>[];
    for (final line in text.split('\n')) {
      final products = matchProducts(line, aliases);
      final prefix = RegExp(
              r'^\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|pcs|x|×)?\s+(.+)$',
              caseSensitive: false)
          .firstMatch(line);
      final suffix = RegExp(r'^(.+?)\s*[x×]\s*(\d+)\s*$', caseSensitive: false)
          .firstMatch(line);
      double quantity = 1;
      String? unit;
      if (products.length == 1 &&
          prefix != null &&
          matchProducts(prefix.group(3)!, aliases).contains(products.single)) {
        quantity = double.tryParse(prefix.group(1)!.replaceAll(',', '.')) ?? 1;
        unit = prefix.group(2)?.toLowerCase();
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

  Future<List<PantryPhotoCandidate>> analyze(XFile photo) async {
    final image = InputImage.fromFilePath(photo.path);
    final labeler =
        ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final candidates = <PantryPhotoCandidate>[];
    try {
      var nativeAvailable = false;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final result =
              await const MethodChannel(AppConstants.methodChannelName)
                  .invokeMethod<List<dynamic>>('recognizePantryPhoto', {
            'image_path': photo.path
          }).timeout(const Duration(seconds: 45));
          nativeAvailable = true;
          for (final object in result ?? []) {
            if (object is! Map) continue;
            final label = object['label'];
            final confidence = object['confidence'];
            if (label is! String ||
                label.trim().isEmpty ||
                confidence is! num ||
                confidence < 0.5 ||
                {
                  'food',
                  'produce',
                  'fruit',
                  'vegetable',
                  'other',
                  'others',
                  'unknown'
                }.contains(label.trim().toLowerCase())) {
              continue;
            }
            final matched = matchProducts(label, aliases);
            final count = object['count'];
            candidates.add(PantryPhotoCandidate(
                matched.length == 1 ? matched.single : label.trim(),
                quantity: count is int && count > 0 ? count.toDouble() : 1));
          }
        } on MissingPluginException {
          // Older installs keep OCR/specific base labels, never invented foods.
        }
      }
      if (!nativeAvailable) {
        final labels = await labeler.processImage(image);
        for (final label in labels) {
          for (final product in matchProducts(label.label, aliases)) {
            candidates.add(PantryPhotoCandidate(product));
          }
        }
      }
      final text = await recognizer.processImage(image);
      candidates.addAll(textCandidates(text.text, aliases));
      return mergePantryCandidates(candidates);
    } finally {
      await labeler.close();
      await recognizer.close();
    }
  }
}
