import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/mascot_type.dart';

/// Replicates the green-centric NutriLens design language from the
/// original React + Tailwind UI in a Flutter ThemeData.
class AppTheme {
  AppTheme._();

  // ── Palette (from tailwind.config.js / index.css) ────────────────────────
  static const Color green50 = Color(0xFFF0FDF4);
  static const Color green100 = Color(0xFFDCFCE7);
  static const Color green200 = Color(0xFFBBF7D0);
  static const Color green300 = Color(0xFF86EFAC);
  static const Color green400 = Color(0xFF4ADE80);
  static const Color green500 = Color(0xFF22C55E);
  static const Color green600 = Color(0xFF16A34A);
  static const Color green700 = Color(0xFF15803D);

  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  static const Color amber100 = Color(0xFFFEF3C7);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);

  static const Color red100 = Color(0xFFFEE2E2);
  static const Color red500 = Color(0xFFEF4444);
  static const Color red700 = Color(0xFFB91C1C);

  // ── Theme ────────────────────────────────────────────────────────────────

  /// Default light theme (green seed).
  static ThemeData get light => fromSeed(AppColorSeed.green);

  /// Build a light theme from any [AppColorSeed].
  static ThemeData fromSeed(AppColorSeed seed) {
    final primary = seed.color;
    final surface = seed.surfaceColor;
    final premium = seed.isPremium;
    final visual = AppVisualTheme.fromSeed(seed);

    // Compute lighter variants from the seed for borders/fills
    final light100 =
        Color.alphaBlend(primary.withValues(alpha: 0.08), Colors.white);
    final light200 =
        Color.alphaBlend(primary.withValues(alpha: 0.16), Colors.white);
    final light400 =
        Color.alphaBlend(primary.withValues(alpha: 0.35), Colors.white);
    final dark700 =
        Color.alphaBlend(Colors.black.withValues(alpha: 0.20), primary);
    final cardColor = premium ? visual.cardColor : Colors.white;
    final appBarColor = premium ? visual.appBarColor : Colors.white;
    final appBarForeground = premium ? visual.onDark : gray900;
    final bodyColor = premium ? visual.onSurface : gray900;

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: primary,
      scaffoldBackgroundColor: surface,
    );

    return base.copyWith(
      scaffoldBackgroundColor: surface,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: bodyColor,
        displayColor: bodyColor,
      ),

      colorScheme: base.colorScheme.copyWith(
        primary: primary,
        secondary: visual.secondaryAccent,
        surface: cardColor,
        onSurface: bodyColor,
      ),

      // App bar
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor,
        foregroundColor: appBarForeground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: premium ? appBarForeground : dark700,
        ),
      ),

      // Cards
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: premium ? 1 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(premium ? 18 : 16),
          side: BorderSide(
            color: premium ? visual.borderColor : light100,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: premium ? visual.navBarColor : Colors.white,
        indicatorColor:
            premium ? visual.primaryAccent.withValues(alpha: 0.18) : light100,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? (premium ? visual.primaryAccent : dark700)
                : (premium ? visual.onMuted : gray500),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 9.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected
                ? (premium ? visual.primaryAccent : dark700)
                : (premium ? visual.onMuted : gray500),
          );
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: premium ? visual.primaryAccent : primary,
        linearTrackColor:
            premium ? visual.primaryAccent.withValues(alpha: 0.14) : light100,
        circularTrackColor:
            premium ? visual.primaryAccent.withValues(alpha: 0.14) : light100,
      ),

      // Elevated buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined buttons
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark700,
          side: BorderSide(color: light200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: premium ? visual.inputFillColor : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: premium ? visual.borderColor : light200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: premium ? visual.borderColor : light200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: premium
                ? visual.primaryAccent.withValues(alpha: 0.65)
                : light400,
            width: 2,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),

      // Embed the vivid seed color so ThemeColors can retrieve it
      extensions: [
        AppColorTheme(seedColor: primary, visual: visual),
      ],
    );
  }
}

enum AppPremiumMotionStyle { standard, aurora, glass, pulse }

/// Premium visual tokens layered on top of the existing seed architecture.
/// They let feature surfaces opt into richer styling while standard screens
/// continue using Material ThemeData and `context.primary*`.
class AppVisualTheme {
  const AppVisualTheme({
    required this.seed,
    required this.premium,
    required this.background,
    required this.surface,
    required this.cardColor,
    required this.appBarColor,
    required this.navBarColor,
    required this.inputFillColor,
    required this.borderColor,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.glowColor,
    required this.onSurface,
    required this.onDark,
    required this.onMuted,
    required this.gradient,
    required this.motionStyle,
    required this.motionDuration,
  });

  factory AppVisualTheme.fromSeed(AppColorSeed seed) {
    if (!seed.isPremium) {
      return AppVisualTheme(
        seed: seed,
        premium: false,
        background: seed.surfaceColor,
        surface: Colors.white,
        cardColor: Colors.white,
        appBarColor: Colors.white,
        navBarColor: Colors.white,
        inputFillColor: Colors.white,
        borderColor:
            Color.alphaBlend(seed.color.withValues(alpha: 0.08), Colors.white),
        primaryAccent: seed.color,
        secondaryAccent: seed.color,
        glowColor: seed.color.withValues(alpha: 0.22),
        onSurface: AppTheme.gray900,
        onDark: Colors.white,
        onMuted: AppTheme.gray500,
        gradient: [seed.color, seed.color.withValues(alpha: 0.70)],
        motionStyle: AppPremiumMotionStyle.standard,
        motionDuration: const Duration(seconds: 1),
      );
    }

    switch (seed) {
      case AppColorSeed.aiAurora:
        return const AppVisualTheme(
          seed: AppColorSeed.aiAurora,
          premium: true,
          background: Color(0xFF0B0F17),
          surface: Color(0xFF111821),
          cardColor: Color(0xFFF8FAFC),
          appBarColor: Color(0xFF0B0F17),
          navBarColor: Color(0xF20E1520),
          inputFillColor: Color(0xFFFFFFFF),
          borderColor: Color(0x3322D3EE),
          primaryAccent: Color(0xFF67E8F9),
          secondaryAccent: Color(0xFFF0ABFC),
          glowColor: Color(0x6645F2D1),
          onSurface: AppTheme.gray900,
          onDark: Color(0xFFF8FAFC),
          onMuted: Color(0xFFAAB6C7),
          gradient: [
            Color(0xFF22D3EE),
            Color(0xFF45F2D1),
            Color(0xFFA78BFA),
            Color(0xFFF0ABFC),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 18),
        );
      case AppColorSeed.liquidGlass:
        return const AppVisualTheme(
          seed: AppColorSeed.liquidGlass,
          premium: true,
          background: Color(0xFF101114),
          surface: Color(0xFF1A1D22),
          cardColor: Color(0xF7FFFFFF),
          appBarColor: Color(0xFF101114),
          navBarColor: Color(0xF0181B20),
          inputFillColor: Color(0xFFFFFFFF),
          borderColor: Color(0x55F8FAFC),
          primaryAccent: Color(0xFFEAF2FF),
          secondaryAccent: Color(0xFFB7D8FF),
          glowColor: Color(0x55F8FAFC),
          onSurface: AppTheme.gray900,
          onDark: Color(0xFFFFFFFF),
          onMuted: Color(0xFFC5CEDA),
          gradient: [
            Color(0xFFFFFFFF),
            Color(0xFFDDE7F3),
            Color(0xFFB7D8FF),
            Color(0xFFF8FAFC),
          ],
          motionStyle: AppPremiumMotionStyle.glass,
          motionDuration: Duration(seconds: 14),
        );
      case AppColorSeed.midnightPulse:
        return const AppVisualTheme(
          seed: AppColorSeed.midnightPulse,
          premium: true,
          background: Color(0xFF030712),
          surface: Color(0xFF080D1A),
          cardColor: Color(0xFFF8FAFC),
          appBarColor: Color(0xFF030712),
          navBarColor: Color(0xFF060B17),
          inputFillColor: Color(0xFFFFFFFF),
          borderColor: Color(0x334F46E5),
          primaryAccent: Color(0xFF2563EB),
          secondaryAccent: Color(0xFF7C3AED),
          glowColor: Color(0x662563EB),
          onSurface: AppTheme.gray900,
          onDark: Color(0xFFF8FAFC),
          onMuted: Color(0xFF9FB1D1),
          gradient: [
            Color(0xFF1D4ED8),
            Color(0xFF4F46E5),
            Color(0xFF7C3AED),
            Color(0xFF38BDF8),
          ],
          motionStyle: AppPremiumMotionStyle.pulse,
          motionDuration: Duration(seconds: 11),
        );
      default:
        return AppVisualTheme.fromSeed(AppColorSeed.green);
    }
  }

  final AppColorSeed seed;
  final bool premium;
  final Color background;
  final Color surface;
  final Color cardColor;
  final Color appBarColor;
  final Color navBarColor;
  final Color inputFillColor;
  final Color borderColor;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color glowColor;
  final Color onSurface;
  final Color onDark;
  final Color onMuted;
  final List<Color> gradient;
  final AppPremiumMotionStyle motionStyle;
  final Duration motionDuration;
}

/// Stores the vivid seed color in the theme so it can be retrieved anywhere
/// via BuildContext, bypassing Material 3's tonal derivation of colorScheme.primary.
class AppColorTheme extends ThemeExtension<AppColorTheme> {
  const AppColorTheme({required this.seedColor, required this.visual});
  final Color seedColor;
  final AppVisualTheme visual;

  @override
  AppColorTheme copyWith({Color? seedColor, AppVisualTheme? visual}) =>
      AppColorTheme(
        seedColor: seedColor ?? this.seedColor,
        visual: visual ?? this.visual,
      );

  @override
  AppColorTheme lerp(ThemeExtension<AppColorTheme>? other, double t) {
    if (other is! AppColorTheme) return this;
    return AppColorTheme(
      seedColor: Color.lerp(seedColor, other.seedColor, t)!,
      visual: t < 0.5 ? visual : other.visual,
    );
  }
}

/// Extension providing theme-aware color shades that follow the user's chosen
/// color seed instead of hard-coded green.
extension ThemeColors on BuildContext {
  /// The vivid seed color set by the user — matches what ElevatedButton uses.
  Color get _seed =>
      Theme.of(this).extension<AppColorTheme>()?.seedColor ??
      Theme.of(this).colorScheme.primary;

  AppVisualTheme get visualTheme =>
      Theme.of(this).extension<AppColorTheme>()?.visual ??
      AppVisualTheme.fromSeed(AppColorSeed.green);

  /// Lightest tint — backgrounds, subtle fills.
  Color get primary50 =>
      Color.alphaBlend(_seed.withValues(alpha: 0.04), Colors.white);
  Color get primary100 =>
      Color.alphaBlend(_seed.withValues(alpha: 0.10), Colors.white);
  Color get primary200 =>
      Color.alphaBlend(_seed.withValues(alpha: 0.20), Colors.white);
  Color get primary300 =>
      Color.alphaBlend(_seed.withValues(alpha: 0.35), Colors.white);

  /// Medium shades — icons, badges, active states.
  Color get primary400 =>
      Color.alphaBlend(_seed.withValues(alpha: 0.55), Colors.white);

  /// The vivid seed color itself — matches ElevatedButton and Save Changes.
  Color get primary500 => _seed;

  /// Darker shades — text, prominent UI.
  Color get primary600 =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.18), _seed);
  Color get primary700 =>
      Color.alphaBlend(Colors.black.withValues(alpha: 0.35), _seed);
}
