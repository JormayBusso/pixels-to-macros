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
  ///
  /// [brightness] only affects PREMIUM seeds: premium themes ship as deep,
  /// dark palettes (the default) but can also render a bright light variant
  /// when [brightness] is [Brightness.light]. Free seeds are always light and
  /// ignore this parameter.
  static ThemeData fromSeed(
    AppColorSeed seed, {
    Brightness brightness = Brightness.dark,
  }) {
    final premium = seed.isPremium;
    final visual = AppVisualTheme.fromSeed(seed, brightness: brightness);
    // Premium light mode uses the theme's readable accent — a premium theme's
    // deep-mode accent can be too pale for a white surface — so primary buttons
    // stay legible. Premium dark and free seeds keep the seed's own colour.
    final primary = (premium && brightness == Brightness.light)
        ? visual.primaryAccent
        : seed.color;
    final surface = premium ? visual.background : seed.surfaceColor;

    // Compute lighter variants from the seed for borders/fills
    final light100 =
        Color.alphaBlend(primary.withValues(alpha: 0.08), Colors.white);
    final light200 =
        Color.alphaBlend(primary.withValues(alpha: 0.16), Colors.white);
    final light400 =
        Color.alphaBlend(primary.withValues(alpha: 0.35), Colors.white);
    final dark700 =
        Color.alphaBlend(Colors.black.withValues(alpha: 0.20), primary);
    final cardColor = visual.cardColor;
    final appBarColor = visual.appBarColor;
    final appBarForeground = premium ? visual.onDark : gray900;
    final bodyColor = premium ? visual.onSurface : gray900;
    final accentForeground =
        premium ? _foregroundFor(visual.primaryAccent) : Colors.white;

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
        foregroundColor: premium ? visual.primaryAccent : appBarForeground,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: premium ? visual.primaryAccent : gray900,
        ),
        actionsIconTheme: IconThemeData(
          color: premium ? visual.primaryAccent : gray900,
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: premium ? visual.primaryAccent : dark700,
        ),
      ),

      // Tabs (e.g. Settings) — keep unselected labels readable on premium dark
      tabBarTheme: TabBarThemeData(
        labelColor: premium ? visual.primaryAccent : primary,
        unselectedLabelColor: premium ? visual.onMuted : gray500,
        indicatorColor: premium ? visual.primaryAccent : primary,
      ),

      // Cards
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: premium ? 1 : 0,
        shadowColor: premium ? visual.glowColor.withValues(alpha: 0.22) : null,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(premium ? 18 : 16),
          side: BorderSide(
            color: premium ? visual.borderColor : light100,
            width: premium ? 1.8 : 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: visual.inputFillColor,
        selectedColor:
            premium ? visual.primaryAccent.withValues(alpha: 0.20) : light100,
        disabledColor:
            premium ? visual.inputFillColor.withValues(alpha: 0.48) : gray100,
        checkmarkColor: premium ? visual.primaryAccent : dark700,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: bodyColor,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: premium ? visual.primaryAccent : dark700,
        ),
        side: BorderSide(color: premium ? visual.borderColor : light200),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            if (selected) {
              return premium
                  ? visual.primaryAccent.withValues(alpha: 0.22)
                  : light100;
            }
            return visual.inputFillColor;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            if (selected) return premium ? visual.primaryAccent : dark700;
            return premium ? visual.onMuted : gray700;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return BorderSide(
              color: selected
                  ? (premium ? visual.primaryAccent : light400)
                  : (premium ? visual.borderColor : light200),
              width: selected ? 1.8 : 1,
            );
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: premium ? visual.navBarColor : Colors.white,
        indicatorColor: Colors.transparent,
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
          backgroundColor: premium ? visual.primaryAccent : primary,
          foregroundColor: accentForeground,
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
          backgroundColor: premium ? visual.inputFillColor : null,
          foregroundColor: premium ? visual.primaryAccent : dark700,
          side: BorderSide(color: premium ? visual.borderColor : light200),
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
        fillColor: visual.inputFillColor,
        labelStyle: GoogleFonts.inter(
          color: premium ? visual.onMuted : gray600,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: premium ? visual.primaryAccent : primary,
        ),
        hintStyle: GoogleFonts.inter(
          color: premium ? visual.onMuted : gray500,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: premium ? visual.borderColor : light200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: premium ? visual.borderColor : light200,
              width: premium ? 2.0 : 1),
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

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: premium ? visual.cardColor : primary,
        foregroundColor: premium ? visual.primaryAccent : Colors.white,
        elevation: premium ? 1 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: cardColor,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: bodyColor,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: premium ? visual.onMuted : gray600,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: premium ? visual.borderColor.withValues(alpha: 0.58) : light100,
      ),

      listTileTheme: ListTileThemeData(
        textColor: bodyColor,
        iconColor: premium ? visual.primaryAccent : dark700,
        subtitleTextStyle: GoogleFonts.inter(
          fontSize: 12,
          color: premium ? visual.onMuted : gray500,
        ),
      ),

      // Embed the vivid seed color so ThemeColors can retrieve it
      extensions: [
        AppColorTheme(seedColor: primary, visual: visual),
      ],
    );
  }

  static Color _foregroundFor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.light
        ? gray900
        : Colors.white;
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
    this.brightness = Brightness.dark,
  });

  factory AppVisualTheme.fromSeed(
    AppColorSeed seed, {
    Brightness brightness = Brightness.dark,
  }) {
    if (!seed.isPremium) {
      final card = Color.alphaBlend(
        seed.color.withValues(alpha: 0.045),
        Colors.white,
      );
      final input = Color.alphaBlend(
        seed.color.withValues(alpha: 0.035),
        Colors.white,
      );
      return AppVisualTheme(
        seed: seed,
        premium: false,
        background: seed.surfaceColor,
        surface: Colors.white,
        // Free themes use PURE-WHITE cards on the seed's pale tinted scaffold
        // (seed.surfaceColor) so container edges stay clearly visible — a
        // near-white tinted card blended into the near-white background and the
        // edges disappeared.
        cardColor: Colors.white,
        appBarColor: seed.surfaceColor,
        navBarColor: card,
        inputFillColor: input,
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

    final dark = _premiumDark(seed);
    return brightness == Brightness.light ? _premiumLight(dark) : dark;
  }

  /// The deep, dark rendering of each premium theme (the original palettes).
  static AppVisualTheme _premiumDark(AppColorSeed seed) {
    switch (seed) {
      case AppColorSeed.aiAurora:
        return const AppVisualTheme(
          seed: AppColorSeed.aiAurora,
          premium: true,
          background: Color(0xFF0B0A1A),
          surface: Color(0xFF13122A),
          cardColor: Color(0xFF181733),
          appBarColor: Color(0xFF0B0A1A),
          navBarColor: Color(0xF2131228),
          inputFillColor: Color(0xFF15142E),
          borderColor: Color(0xAA8B7BFF),
          primaryAccent: Color(0xFF8B7BFF),
          secondaryAccent: Color(0xFFFF5FA2),
          glowColor: Color(0xCC8B7BFF),
          onSurface: Color(0xFFF8FAFC),
          onDark: Color(0xFFF8FAFC),
          onMuted: Color(0xFFD2DCEC),
          gradient: [
            Color(0xFF7C5CFF),
            Color(0xFFB152FF),
            Color(0xFFFF5FA2),
            Color(0xFFFF8A5B),
            Color(0xFF38E0D0),
            Color(0xFF4FA8FF),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 16),
        );
      case AppColorSeed.liquidGlass:
        return const AppVisualTheme(
          seed: AppColorSeed.liquidGlass,
          premium: true,
          background: Color(0xFF0D0F12),
          surface: Color(0xFF14171C),
          cardColor: Color(0xFF181B20),
          appBarColor: Color(0xFF0D0F12),
          navBarColor: Color(0xF014171C),
          inputFillColor: Color(0xFF15181D),
          borderColor: Color(0x99CDD5DF),
          primaryAccent: Color(0xFFE5E7EB),
          secondaryAccent: Color(0xFF9CA3AF),
          glowColor: Color(0x77CDD5DF),
          onSurface: Color(0xFFF8FAFC),
          onDark: Color(0xFFFFFFFF),
          onMuted: Color(0xFFDCDFE6),
          gradient: [
            Color(0xFFEEF2F7),
            Color(0xFFB8C0CC),
            Color(0xFF6B7280),
            Color(0xFFFFFFFF),
          ],
          motionStyle: AppPremiumMotionStyle.glass,
          motionDuration: Duration(seconds: 8),
        );
      case AppColorSeed.geminiAI:
        return const AppVisualTheme(
          seed: AppColorSeed.geminiAI,
          premium: true,
          background: Color(0xFF0A1020),
          surface: Color(0xFF0D172B),
          cardColor: Color(0xFF101A2F),
          appBarColor: Color(0xFF0A1020),
          navBarColor: Color(0xF20D172B),
          inputFillColor: Color(0xFF0F1B31),
          borderColor: Color(0x884F8CFF),
          primaryAccent: Color(0xFF4F8CFF),
          secondaryAccent: Color(0xFF22D3EE),
          glowColor: Color(0x774F8CFF),
          onSurface: Color(0xFFF8FAFC),
          onDark: Color(0xFFF8FAFC),
          onMuted: Color(0xFFD0DCF0),
          gradient: [
            Color(0xFF4F8CFF),
            Color(0xFF38BDF8),
            Color(0xFF22D3EE),
            Color(0xFF60A5FA),
            Color(0xFF7C3AED),
            Color(0xFFB8C7FF),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 20),
        );
      case AppColorSeed.midnightNeon:
        return const AppVisualTheme(
          seed: AppColorSeed.midnightNeon,
          premium: true,
          background: Color(0xFF020617),
          surface: Color(0xFF050C1B),
          cardColor: Color(0xFF071126),
          appBarColor: Color(0xFF020617),
          navBarColor: Color(0xF2050C1B),
          inputFillColor: Color(0xFF061025),
          borderColor: Color(0x9900E5FF),
          primaryAccent: Color(0xFF00E5FF),
          secondaryAccent: Color(0xFFFF2BD6),
          glowColor: Color(0x8800E5FF),
          onSurface: Color(0xFFF2FBFF),
          onDark: Color(0xFFF2FBFF),
          onMuted: Color(0xFFC2D6E8),
          gradient: [
            Color(0xFF00E5FF),
            Color(0xFF2563EB),
            Color(0xFFFF2BD6),
            Color(0xFF7C3AED),
          ],
          motionStyle: AppPremiumMotionStyle.pulse,
          motionDuration: Duration(seconds: 6),
        );
      case AppColorSeed.solarFlare:
        return const AppVisualTheme(
          seed: AppColorSeed.solarFlare,
          premium: true,
          background: Color(0xFF171008),
          surface: Color(0xFF1D1209),
          cardColor: Color(0xFF24170C),
          appBarColor: Color(0xFF171008),
          navBarColor: Color(0xF01F1308),
          inputFillColor: Color(0xFF211409),
          borderColor: Color(0x99FF7A45),
          primaryAccent: Color(0xFFFF7A45),
          secondaryAccent: Color(0xFFFACC15),
          glowColor: Color(0x88FF7A45),
          onSurface: Color(0xFFFFFAF0),
          onDark: Color(0xFFFFFAF0),
          onMuted: Color(0xFFF2DEC8),
          gradient: [
            Color(0xFFFF7A45),
            Color(0xFFFACC15),
            Color(0xFFFF4F8B),
            Color(0xFF7C3AED),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 7),
        );
      case AppColorSeed.emeraldMirage:
        return const AppVisualTheme(
          seed: AppColorSeed.emeraldMirage,
          premium: true,
          background: Color(0xFF04140F),
          surface: Color(0xFF071A14),
          cardColor: Color(0xFF0A2018),
          appBarColor: Color(0xFF04140F),
          navBarColor: Color(0xF2071A14),
          inputFillColor: Color(0xFF081D16),
          borderColor: Color(0x9934D399),
          primaryAccent: Color(0xFF34D399),
          secondaryAccent: Color(0xFF2DD4BF),
          glowColor: Color(0x8834D399),
          onSurface: Color(0xFFECFDF5),
          onDark: Color(0xFFECFDF5),
          onMuted: Color(0xFFC8E8DC),
          gradient: [
            Color(0xFF34D399),
            Color(0xFF2DD4BF),
            Color(0xFF22D3EE),
            Color(0xFFA3E635),
            Color(0xFF6EE7B7),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 14),
        );
      case AppColorSeed.royalAmethyst:
        return const AppVisualTheme(
          seed: AppColorSeed.royalAmethyst,
          premium: true,
          background: Color(0xFF0E0A1F),
          surface: Color(0xFF140E2B),
          cardColor: Color(0xFF181030),
          appBarColor: Color(0xFF0E0A1F),
          navBarColor: Color(0xF2140E2B),
          inputFillColor: Color(0xFF150F2D),
          borderColor: Color(0x99A78BFA),
          primaryAccent: Color(0xFFA78BFA),
          secondaryAccent: Color(0xFFE879F9),
          glowColor: Color(0x88A78BFA),
          onSurface: Color(0xFFF5F3FF),
          onDark: Color(0xFFF5F3FF),
          onMuted: Color(0xFFDED7F2),
          gradient: [
            Color(0xFFA78BFA),
            Color(0xFF818CF8),
            Color(0xFFC084FC),
            Color(0xFFE879F9),
            Color(0xFF60A5FA),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 18),
        );
      case AppColorSeed.rainbow:
        return const AppVisualTheme(
          seed: AppColorSeed.rainbow,
          premium: true,
          background: Color(0xFF0A0A12),
          surface: Color(0xFF101019),
          cardColor: Color(0xFF14141F),
          appBarColor: Color(0xFF0A0A12),
          navBarColor: Color(0xF2101019),
          inputFillColor: Color(0xFF13131D),
          borderColor: Color(0x9938BDF8),
          primaryAccent: Color(0xFF38BDF8),
          secondaryAccent: Color(0xFFFF9500),
          glowColor: Color(0x8838BDF8),
          onSurface: Color(0xFFF6F7FB),
          onDark: Color(0xFFF6F7FB),
          onMuted: Color(0xFFD2D6E2),
          gradient: [
            Color(0xFFFF3B30),
            Color(0xFFFF9500),
            Color(0xFFFFCC00),
            Color(0xFF34C759),
            Color(0xFF007AFF),
            Color(0xFF5856D6),
            Color(0xFFAF52DE),
          ],
          motionStyle: AppPremiumMotionStyle.aurora,
          motionDuration: Duration(seconds: 6),
        );
      default:
        return AppVisualTheme.fromSeed(AppColorSeed.green);
    }
  }

  /// Bright rendering of a premium theme. Keeps the theme's signature accent
  /// and gradient — so each premium theme stays instantly recognisable — but
  /// swaps the deep backgrounds for light, lightly-tinted surfaces with dark
  /// text. Accents that are too pale to read on white (e.g. the glass theme's
  /// near-white accent) are darkened while preserving their hue.
  static AppVisualTheme _premiumLight(AppVisualTheme dark) {
    Color readable(Color c) {
      if (c.computeLuminance() <= 0.55) return c;
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withLightness((hsl.lightness * 0.55).clamp(0.30, 0.52))
          .withSaturation(hsl.saturation.clamp(0.35, 1.0))
          .toColor();
    }

    final accent = readable(dark.primaryAccent);
    final secondary = readable(dark.secondaryAccent);
    Color tint(double a) =>
        Color.alphaBlend(accent.withValues(alpha: a), Colors.white);

    return AppVisualTheme(
      seed: dark.seed,
      premium: true,
      brightness: Brightness.light,
      background: tint(0.05),
      surface: Colors.white,
      cardColor: tint(0.06),
      appBarColor: tint(0.05),
      navBarColor: tint(0.045),
      inputFillColor: tint(0.05),
      borderColor: accent.withValues(alpha: 0.32),
      primaryAccent: accent,
      secondaryAccent: secondary,
      glowColor: accent.withValues(alpha: 0.28),
      onSurface: AppTheme.gray900,
      onDark: AppTheme.gray900,
      onMuted: AppTheme.gray500,
      gradient: dark.gradient.map(readable).toList(),
      motionStyle: dark.motionStyle,
      motionDuration: dark.motionDuration,
    );
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

  /// Whether this is the light or dark rendering of the theme. Only premium
  /// themes vary; free themes are always [Brightness.light].
  final Brightness brightness;

  /// True when this is the bright rendering of a premium theme. Consumers use
  /// it to darken "prominent" shades (which are lightened in dark mode) so text
  /// and icons keep contrast on the light surfaces.
  bool get isLight => brightness == Brightness.light;
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

  bool get isPremiumTheme => visualTheme.premium;

  Color get appSurfaceColor => visualTheme.cardColor;

  Color get appPanelColor =>
      visualTheme.premium ? visualTheme.surface : visualTheme.background;

  Color get appSubtleFillColor => visualTheme.inputFillColor;

  Color get appBorderColor =>
      visualTheme.premium ? visualTheme.borderColor : primary100;

  Color get appTextColor =>
      visualTheme.premium ? visualTheme.onSurface : AppTheme.gray900;

  Color get appMutedTextColor =>
      visualTheme.premium ? visualTheme.onMuted : AppTheme.gray500;

  /// Lightest tint — backgrounds, subtle fills.
  Color get primary50 => visualTheme.premium
      ? Color.alphaBlend(_seed.withValues(alpha: 0.08), visualTheme.surface)
      : Color.alphaBlend(_seed.withValues(alpha: 0.04), Colors.white);
  Color get primary100 => visualTheme.premium
      ? Color.alphaBlend(_seed.withValues(alpha: 0.14), visualTheme.surface)
      : Color.alphaBlend(_seed.withValues(alpha: 0.10), Colors.white);
  Color get primary200 => visualTheme.premium
      ? Color.alphaBlend(_seed.withValues(alpha: 0.22), visualTheme.surface)
      : Color.alphaBlend(_seed.withValues(alpha: 0.20), Colors.white);
  Color get primary300 => visualTheme.premium
      ? Color.alphaBlend(_seed.withValues(alpha: 0.32), visualTheme.surface)
      : Color.alphaBlend(_seed.withValues(alpha: 0.35), Colors.white);

  /// Medium shades — icons, badges, active states.
  Color get primary400 => (visualTheme.premium && !visualTheme.isLight)
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.16), _seed)
      : Color.alphaBlend(_seed.withValues(alpha: 0.55), Colors.white);

  /// The vivid seed color itself — matches ElevatedButton and Save Changes.
  Color get primary500 => _seed;

  /// Darker shades — text, prominent UI.
  Color get primary600 => (visualTheme.premium && !visualTheme.isLight)
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.10), _seed)
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.18), _seed);
  Color get primary700 => (visualTheme.premium && !visualTheme.isLight)
      ? Color.alphaBlend(Colors.white.withValues(alpha: 0.22), _seed)
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.35), _seed);
}
