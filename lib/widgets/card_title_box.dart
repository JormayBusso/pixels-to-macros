import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Solid single-color title box shown inside a card at the top. Use a zero
/// [borderRadius] in a clipped full-width card header. The fill is a
/// slightly darker tint of the theme color than the page background; the text
/// color is picked from the fill contrast so it stays readable on every
/// default and premium theme.
class CardTitleBox extends StatelessWidget {
  const CardTitleBox({
    required this.title,
    this.icon,
    this.leading,
    this.trailing,
    this.margin = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.key,
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final BorderRadiusGeometry borderRadius;

  /// Solid fill for the box on the current theme.
  static Color fillOf(BuildContext context) => context.primary300;

  /// Readable foreground for [fillOf].
  static Color foregroundOf(BuildContext context) {
    final fill = fillOf(context);
    final luminance = fill.computeLuminance();
    final darkContrast =
        (luminance + 0.05) / (AppTheme.gray900.computeLuminance() + 0.05);
    if (darkContrast >= 4.5) return AppTheme.gray900;
    if (1.05 / (luminance + 0.05) >= 4.5) return Colors.white;
    return Colors.black;
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
        borderRadius: borderRadius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = trailing != null &&
              constraints.maxWidth <
                  240 * MediaQuery.textScalerOf(context).scale(15) / 15;
          final titleRow = Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              if (leading == null && icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
              if (trailing != null && !stackActions) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          );
          if (!stackActions) return titleRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleRow,
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
            ],
          );
        },
      ),
    );
  }
}
