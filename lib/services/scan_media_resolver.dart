import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves stored scan-media paths (top/side captures and the exported 3-D
/// model) to a path that exists in the CURRENT app container.
///
/// iOS rewrites the Documents container UUID on every app (re)install, so an
/// absolute path saved by an earlier install no longer resolves even though the
/// file still lives in the new container. Scan media is written to
/// `Documents/` (3-D models) and `Documents/scan_captures/` (top/side JPGs),
/// so we re-anchor by file name when the stored absolute path is stale.
class ScanMediaResolver {
  ScanMediaResolver._();

  static String? _docsPath;

  /// Cache the current Documents directory once. Safe to call repeatedly.
  static Future<void> ensureInitialized() async {
    if (_docsPath != null) return;
    try {
      _docsPath = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      // Leave null; resolve() will simply check the raw path.
    }
  }

  /// Returns an existing absolute file path for [stored], re-anchoring to the
  /// current container by file name if the stored path is stale. Returns null
  /// when no matching file exists.
  static String? resolve(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (File(stored).existsSync()) return stored;

    final docs = _docsPath;
    if (docs == null) return null;

    final name = stored.split('/').last;
    if (name.isEmpty) return null;

    final candidates = <String>[
      '$docs/$name',
      '$docs/scan_captures/$name',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  /// Whether a usable file exists for [stored] in the current container.
  static bool exists(String? stored) => resolve(stored) != null;
}
