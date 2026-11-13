import 'dart:math' as math;

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../models/pantry_item.dart';
import 'grocery_text_parser.dart';

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

/// OCR rows (+ optional on-device language-model products) for one photo.
class GroceryTextReading {
  const GroceryTextReading(this.lines, {this.items, this.engine = 'mlkit'});

  final List<String> lines;
  final List<GroceryModelItem>? items;
  final String engine;
}

class PantryPhotoService {
  PantryPhotoService({
    required this.aliases,
    ImagePicker? picker,
    Future<List<XFile>> Function(ImageSource)? photoPicker,
    Future<List<PantryPhotoCandidate>> Function(XFile)? analyzer,
    Future<List<PantryPhotoCandidate>> Function(XFile)? receiptAnalyzer,
  })  : _picker = picker ?? ImagePicker(),
        _photoPicker = photoPicker,
        _analyzer = analyzer,
        _receiptAnalyzer = receiptAnalyzer;

  final Map<String, String> aliases;
  final ImagePicker _picker;
  final Future<List<XFile>> Function(ImageSource)? _photoPicker;
  final Future<List<PantryPhotoCandidate>> Function(XFile)? _analyzer;
  final Future<List<PantryPhotoCandidate>> Function(XFile)? _receiptAnalyzer;

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

  /// Packaging / label OCR text -> products (multilingual; ingredient lists
  /// and nutrition tables are ignored).
  static List<PantryPhotoCandidate> textCandidates(
          String text, Map<String, String> aliases) =>
      GroceryTextParser.parsePackaging(text, aliases);

  /// On-device text reading: Apple Vision OCR (every script, automatic
  /// language detection) plus, when Apple Intelligence is available, the
  /// on-device language model's food/drink extraction. Null when the native
  /// reader is unavailable (older build, non-iOS, decode failure).
  static Future<GroceryTextReading?> readTextNative(
      XFile photo, String kind) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final result = await const MethodChannel(AppConstants.methodChannelName)
          .invokeMethod<Map<dynamic, dynamic>>('readGroceryText', {
        'image_path': photo.path,
        'kind': kind,
      }).timeout(const Duration(seconds: 60));
      if (result == null) return null;
      final lines = [
        for (final line in (result['lines'] as List? ?? const []))
          if (line is String) line,
      ];
      final rawItems = result['items'];
      List<GroceryModelItem>? items;
      if (rawItems is List) {
        items = [
          for (final item in rawItems)
            if (item is Map && item['line'] is int && item['name'] is String)
              GroceryModelItem(
                  line: item['line'] as int, name: item['name'] as String),
        ];
      }
      final engine = result['engine'] as String? ?? 'vision';
      debugPrint('[GROCERY_TEXT] kind=$kind engine=$engine '
          'lines=${lines.length} modelItems=${items?.length ?? 'none'}');
      return GroceryTextReading(lines, items: items, engine: engine);
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[GROCERY_TEXT] native reader failed: $e');
      return null;
    }
  }

  /// Rebuild receipt rows from ML Kit lines: a product name and its price
  /// are separate text blocks, so lines are regrouped by vertical position.
  static List<String> textRows(RecognizedText text) {
    final lines = [
      for (final block in text.blocks)
        for (final line in block.lines) line,
    ]..sort(
        (a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));
    final rows = <List<TextLine>>[];
    for (final line in lines) {
      final box = line.boundingBox;
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final ref = row.first.boundingBox;
        final tolerance = math.min(ref.height, box.height) * 0.5;
        if ((box.center.dy - ref.center.dy).abs() <= tolerance) {
          row.add(line);
          continue;
        }
      }
      rows.add([line]);
    }
    return [
      for (final row in rows)
        (row..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)))
            .map((l) => l.text)
            .join('  '),
    ];
  }

  /// Read a shopping receipt and return only its foods and drinks.
  Future<List<PantryPhotoCandidate>> analyzeReceipt(XFile photo) async {
    if (_receiptAnalyzer != null) return _receiptAnalyzer(photo);
    final native = await readTextNative(photo, 'receipt');
    if (native != null && native.lines.isNotEmpty) {
      final items = GroceryTextParser.parseReceipt(native.lines,
          modelItems: native.items);
      debugPrint(
          '[RECEIPT] engine=${native.engine} rows=${native.lines.length} '
          'foods=${items.length} names=${items.map((i) => i.name).join('|')}');
      return items;
    }
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text =
          await recognizer.processImage(InputImage.fromFilePath(photo.path));
      final rows = textRows(text);
      final items = GroceryTextParser.parseReceipt(rows);
      debugPrint('[RECEIPT] engine=mlkit rows=${rows.length} '
          'foods=${items.length} names=${items.map((i) => i.name).join('|')}');
      return items;
    } finally {
      await recognizer.close();
    }
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
      final native = await readTextNative(photo, 'packaging');
      if (native != null) {
        if (native.items != null) {
          candidates.addAll(GroceryTextParser.parsePackagingModel(
              native.items!, native.lines));
        }
        candidates.addAll(textCandidates(native.lines.join('\n'), aliases));
      } else {
        final text = await recognizer.processImage(image);
        // Blank lines separate OCR blocks so an ingredient list stays local.
        candidates.addAll(textCandidates(
            text.blocks.map((b) => b.text).join('\n\n'), aliases));
      }
      return mergePantryCandidates(candidates);
    } finally {
      await labeler.close();
      await recognizer.close();
    }
  }
}
