import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Solid single-color title box shown inside a card at the top. The fill is a
/// slightly darker tint of the theme color than the page background; the text
/// color is picked from the fill brightness so it stays readable on every
/// default and premium theme.
class CardTitleBox extends StatelessWidget {
  const CardTitleBox({
    required this.title,
    this.icon,
    this.leading,
    this.trailing,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;

  /// Solid fill for the box on the current theme.
  static Color fillOf(BuildContext context) => context.primary200;

  /// Readable foreground for [fillOf].
  static Color foregroundOf(BuildContext context) {
    final fill = fillOf(context);
    return ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : AppTheme.gray900;
  }

  @override
  Widget build(BuildContext context) {
    final fg = foregroundOf(context);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: fillOf(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          if (leading == null && icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}
