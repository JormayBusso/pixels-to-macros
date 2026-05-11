import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Paste your raw SVG here if you want to hardcode it inline.
///
/// Example:
/// const kBodyMapRawSvg = r'''
/// <svg viewBox="0 0 474 711" xmlns="http://www.w3.org/2000/svg">
///   ... your base anatomy + organ paths with ids like liver/brain/stomach ...
/// </svg>
/// ''';
const String kBodyMapRawSvg = '';

/// Inline SVG renderer that targets organ paths by id and applies
/// fill + opacity based on score (0-100).
class InteractiveBodyMapSvg extends StatelessWidget {
  const InteractiveBodyMapSvg({
    super.key,
    required this.rawSvg,
    required this.organScores,
    this.fit = BoxFit.contain,
  });

  static const double _overlayOpacity = 0.60;

  /// Raw SVG xml text.
  final String rawSvg;

  /// Map of organ id -> score (0..100), e.g. {'liver': 82, 'brain': 43}
  final Map<String, int> organScores;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final highlighted = _buildHighlightedSvg(rawSvg, organScores);
    return SvgPicture.string(
      highlighted,
      fit: fit,
      allowDrawingOutsideViewBox: true,
    );
  }

  /// Explicit API requested by spec:
  /// takes one organ id + score and returns updated svg text
  /// with fill color + transparent overlay opacity applied to that path id.
  static String highlightOrganByScore({
    required String svg,
    required String organId,
    required int score,
  }) {
    return _applyHighlight(svg, organId, _scoreColor(score));
  }

  static String _buildHighlightedSvg(String svg, Map<String, int> scores) {
    var out = svg;
    for (final entry in scores.entries) {
      out = _applyHighlight(out, entry.key, _scoreColor(entry.value));
    }
    return out;
  }

  static String _applyHighlight(String svg, String organId, Color color) {
    final opacityValue = _overlayOpacity.toStringAsFixed(2);
    final tagPattern = RegExp(
      '(<[^>]*\\bid="${RegExp.escape(organId)}"[^>]*>)',
      caseSensitive: false,
    );

    return svg.replaceFirstMapped(tagPattern, (m) {
      var tag = m.group(1)!;
      // Some SVGs store paint in style="fill:...;opacity:..." rather than
      // dedicated attributes, so update both forms for reliability.
      tag = _replaceStyleProperty(tag, 'fill', _toHex(color));
      tag = _replaceStyleProperty(tag, 'opacity', opacityValue);
      tag = _replaceStyleProperty(tag, 'fill-opacity', opacityValue);
      tag = _replaceOrAddAttribute(tag, 'fill', _toHex(color));
      tag = _replaceOrAddAttribute(tag, 'opacity', opacityValue);
      tag = _replaceOrAddAttribute(tag, 'fill-opacity', opacityValue);
      return tag;
    });
  }

  static String _replaceStyleProperty(String tag, String name, String value) {
    final styleRegex = RegExp('\\bstyle\\s*=\\s*"([^"]*)"', caseSensitive: false);
    final match = styleRegex.firstMatch(tag);
    if (match == null) {
      return tag;
    }

    final style = match.group(1) ?? '';
    final propRegex = RegExp('(^|;)\\s*$name\\s*:[^;]*', caseSensitive: false);
    final hasProp = propRegex.hasMatch(style);
    final nextStyle = hasProp
        ? style.replaceFirstMapped(propRegex, (m) => '${m.group(1)}$name:$value')
        : style.trim().isEmpty
            ? '$name:$value'
            : '${style.trim()};$name:$value';

    return tag.replaceFirst(styleRegex, 'style="$nextStyle"');
  }

  static String _replaceOrAddAttribute(
    String tag,
    String name,
    String value,
  ) {
    final attrRegex = RegExp('\\b$name\\s*=\\s*"[^"]*"', caseSensitive: false);
    if (attrRegex.hasMatch(tag)) {
      return tag.replaceFirst(attrRegex, '$name="$value"');
    }
    // Handle self-closing tags (e.g. <path .../>) — must insert before '/>' not '>'
    if (tag.endsWith('/>')) {
      return '${tag.substring(0, tag.length - 2)} $name="$value"/>';
    }
    final close = tag.lastIndexOf('>');
    if (close < 0) return tag;
    return '${tag.substring(0, close)} $name="$value"${tag.substring(close)}';
  }

  static String _toHex(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${(r + g + b).toUpperCase()}';
  }

  /// Strict threshold mapping required by spec.
  static Color _scoreColor(int rawScore) {
    final score = rawScore.clamp(0, 100);
    if (score >= 75) return const Color(0xFF4CAF50); // Green
    if (score >= 50) return const Color(0xFFFFEB3B); // Yellow
    if (score >= 25) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }
}
