import 'package:flutter/material.dart';

/// Which mascot the user wants to see on the home screen.
///
/// [auto] — use the mascot that fits the user's nutrition goal.
/// All other values override the goal-based default.
enum MascotType { auto, gorilla, plant, flame, sugar }

extension MascotTypeX on MascotType {
  String get dbValue => name; // 'auto', 'gorilla', …

  String get label {
    switch (this) {
      case MascotType.auto:
        return 'Auto (matches goal)';
      case MascotType.gorilla:
        return 'Gorilla 🦍';
      case MascotType.plant:
        return 'Plant 🌱';
      case MascotType.flame:
        return 'Flame 🔥';
      case MascotType.sugar:
        return 'Sugar Cube 🍬';
    }
  }

  String get emoji {
    switch (this) {
      case MascotType.auto:
        return '🎯';
      case MascotType.gorilla:
        return '🦍';
      case MascotType.plant:
        return '🌱';
      case MascotType.flame:
        return '🔥';
      case MascotType.sugar:
        return '🍬';
    }
  }

  static MascotType fromDbValue(String? v) {
    switch (v) {
      case 'gorilla':
        return MascotType.gorilla;
      case 'plant':
        return MascotType.plant;
      case 'flame':
        return MascotType.flame;
      case 'sugar':
        return MascotType.sugar;
      case 'glass':
        return MascotType.auto; // glass removed, fall back to auto
      default:
        return MascotType.auto;
    }
  }
}

// ── App theme color seeds ────────────────────────────────────────────────────

/// Predefined accent color seeds the user can choose in settings.
enum AppColorSeed {
  green,
  blue,
  purple,
  orange,
  rose,
  pink,
  yellow,
  aiAurora,
  liquidGlass,
  geminiAI,
  midnightNeon,
  solarFlare,
  emeraldMirage,
  royalAmethyst,
}

extension AppColorSeedX on AppColorSeed {
  String get dbValue => name;

  String get label {
    switch (this) {
      case AppColorSeed.green:
        return 'Green (default)';
      case AppColorSeed.blue:
        return 'Blue';
      case AppColorSeed.purple:
        return 'Purple';
      case AppColorSeed.orange:
        return 'Orange';
      case AppColorSeed.rose:
        return 'Rose';
      case AppColorSeed.pink:
        return 'Pink';
      case AppColorSeed.yellow:
        return 'Yellow';
      case AppColorSeed.aiAurora:
        return 'Premium Nebula';
      case AppColorSeed.liquidGlass:
        return 'Premium Glass';
      case AppColorSeed.geminiAI:
        return 'Premium Gemini';
      case AppColorSeed.midnightNeon:
        return 'Premium Midnight';
      case AppColorSeed.solarFlare:
        return 'Premium Solar';
      case AppColorSeed.emeraldMirage:
        return 'Premium Emerald';
      case AppColorSeed.royalAmethyst:
        return 'Premium Amethyst';
    }
  }

  String get shortDescription {
    switch (this) {
      case AppColorSeed.aiAurora:
        return 'Vivid nebula spectrum';
      case AppColorSeed.liquidGlass:
        return 'Graphite and silver glass';
      case AppColorSeed.geminiAI:
        return 'Clean and professional';
      case AppColorSeed.midnightNeon:
        return 'Deep and electric';
      case AppColorSeed.solarFlare:
        return 'Warm and cinematic';
      case AppColorSeed.emeraldMirage:
        return 'Lush emerald and teal';
      case AppColorSeed.royalAmethyst:
        return 'Regal violet and indigo';
      default:
        return 'Classic ${label.replaceAll(' (default)', '').toLowerCase()} accent';
    }
  }

  bool get isPremium {
    switch (this) {
      case AppColorSeed.aiAurora:
      case AppColorSeed.liquidGlass:
      case AppColorSeed.geminiAI:
      case AppColorSeed.midnightNeon:
      case AppColorSeed.solarFlare:
      case AppColorSeed.emeraldMirage:
      case AppColorSeed.royalAmethyst:
        return true;
      default:
        return false;
    }
  }

  Color get color {
    switch (this) {
      case AppColorSeed.green:
        return const Color(0xFF16A34A); // green-600
      case AppColorSeed.blue:
        return const Color(0xFF2563EB); // blue-600
      case AppColorSeed.purple:
        return const Color(0xFF7C3AED); // violet-600
      case AppColorSeed.orange:
        return const Color(0xFFEA580C); // orange-600
      case AppColorSeed.rose:
        return const Color(0xFFE11D48); // rose-600
      case AppColorSeed.pink:
        return const Color(0xFFEC4899); // pink-500
      case AppColorSeed.yellow:
        return const Color(0xFFEAB308); // yellow-500
      case AppColorSeed.aiAurora:
        return const Color(0xFF8B7BFF); // premium nebula violet
      case AppColorSeed.liquidGlass:
        return const Color(0xFFCDD5DF); // premium graphite glass
      case AppColorSeed.geminiAI:
        return const Color(0xFF4F8CFF); // Gemini blue
      case AppColorSeed.midnightNeon:
        return const Color(0xFF00E5FF); // midnight neon cyan
      case AppColorSeed.solarFlare:
        return const Color(0xFFFF7A45); // premium solar orange
      case AppColorSeed.emeraldMirage:
        return const Color(0xFF34D399); // premium emerald
      case AppColorSeed.royalAmethyst:
        return const Color(0xFFA78BFA); // premium amethyst violet
    }
  }

  List<Color> get accentColors {
    switch (this) {
      case AppColorSeed.aiAurora:
        return const [
          Color(0xFF7C5CFF),
          Color(0xFFB152FF),
          Color(0xFFFF5FA2),
          Color(0xFFFF8A5B),
          Color(0xFF38E0D0),
          Color(0xFF4FA8FF),
        ];
      case AppColorSeed.liquidGlass:
        return const [
          Color(0xFFEEF2F7),
          Color(0xFFB8C0CC),
          Color(0xFF6B7280),
          Color(0xFFFFFFFF),
        ];
      case AppColorSeed.geminiAI:
        return const [
          Color(0xFF4F8CFF),
          Color(0xFF38BDF8),
          Color(0xFF22D3EE),
          Color(0xFF60A5FA),
          Color(0xFF7C3AED),
          Color(0xFFB8C7FF),
        ];
      case AppColorSeed.midnightNeon:
        return const [
          Color(0xFF00E5FF),
          Color(0xFF2563EB),
          Color(0xFFFF2BD6),
          Color(0xFF7C3AED),
        ];
      case AppColorSeed.solarFlare:
        return const [
          Color(0xFFFF7A45),
          Color(0xFFFACC15),
          Color(0xFFFF4F8B),
          Color(0xFF7C3AED),
        ];
      case AppColorSeed.emeraldMirage:
        return const [
          Color(0xFF34D399),
          Color(0xFF2DD4BF),
          Color(0xFF22D3EE),
          Color(0xFFA3E635),
          Color(0xFF6EE7B7),
        ];
      case AppColorSeed.royalAmethyst:
        return const [
          Color(0xFFA78BFA),
          Color(0xFF818CF8),
          Color(0xFFC084FC),
          Color(0xFFE879F9),
          Color(0xFF60A5FA),
        ];
      default:
        return [color, color.withValues(alpha: 0.72)];
    }
  }

  /// Very light tint used for scaffold backgrounds and card fills.
  Color get surfaceColor {
    switch (this) {
      case AppColorSeed.green:
        return const Color(0xFFF0FDF4);
      case AppColorSeed.blue:
        return const Color(0xFFEFF6FF);
      case AppColorSeed.purple:
        return const Color(0xFFF5F3FF);
      case AppColorSeed.orange:
        return const Color(0xFFFFF7ED);
      case AppColorSeed.rose:
        return const Color(0xFFFFF1F2);
      case AppColorSeed.pink:
        return const Color(0xFFFDF2F8);
      case AppColorSeed.yellow:
        return const Color(0xFFFEFCE8);
      case AppColorSeed.aiAurora:
        return const Color(0xFF0C111D);
      case AppColorSeed.liquidGlass:
        return const Color(0xFF0D0F12);
      case AppColorSeed.geminiAI:
        return const Color(0xFF0A1020);
      case AppColorSeed.midnightNeon:
        return const Color(0xFF020617);
      case AppColorSeed.solarFlare:
        return const Color(0xFF171008);
      case AppColorSeed.emeraldMirage:
        return const Color(0xFF04140F);
      case AppColorSeed.royalAmethyst:
        return const Color(0xFF0E0A1F);
    }
  }

  Color get premiumSurfaceColor {
    switch (this) {
      case AppColorSeed.aiAurora:
        return const Color(0xFF151B2A);
      case AppColorSeed.liquidGlass:
        return const Color(0xFF181B20);
      case AppColorSeed.geminiAI:
        return const Color(0xFF101A2F);
      case AppColorSeed.midnightNeon:
        return const Color(0xFF071126);
      case AppColorSeed.solarFlare:
        return const Color(0xFF24170C);
      case AppColorSeed.emeraldMirage:
        return const Color(0xFF0A2018);
      case AppColorSeed.royalAmethyst:
        return const Color(0xFF181030);
      default:
        return Colors.white;
    }
  }

  static AppColorSeed fromDbValue(String? v) {
    switch (v) {
      case 'blue':
        return AppColorSeed.blue;
      case 'purple':
        return AppColorSeed.purple;
      case 'orange':
        return AppColorSeed.orange;
      case 'rose':
        return AppColorSeed.rose;
      case 'pink':
        return AppColorSeed.pink;
      case 'yellow':
        return AppColorSeed.yellow;
      case 'aiAurora':
      case 'ai_aurora':
        return AppColorSeed.aiAurora;
      case 'liquidGlass':
      case 'liquid_glass':
        return AppColorSeed.liquidGlass;
      case 'midnightPulse':
      case 'midnight_pulse':
        return AppColorSeed.midnightNeon;
      case 'geminiAI':
      case 'gemini_ai':
        return AppColorSeed.geminiAI;
      case 'cosmicPlasma':
      case 'cosmic_plasma':
        return AppColorSeed.aiAurora;
      case 'neuralLime':
      case 'neural_lime':
      case 'emeraldAI':
      case 'emerald_ai':
        return AppColorSeed.aiAurora;
      case 'titaniumGlass':
      case 'titanium_glass':
        return AppColorSeed.liquidGlass;
      case 'midnightNeon':
      case 'midnight_neon':
        return AppColorSeed.midnightNeon;
      case 'solarFlare':
      case 'solar_flare':
      case 'sunsetIntelligence':
      case 'sunset_intelligence':
        return AppColorSeed.solarFlare;
      case 'emeraldMirage':
      case 'emerald_mirage':
        return AppColorSeed.emeraldMirage;
      case 'royalAmethyst':
      case 'royal_amethyst':
        return AppColorSeed.royalAmethyst;
      case 'crimsonEmber':
      case 'crimson_ember':
        return AppColorSeed.solarFlare;
      default:
        return AppColorSeed.green;
    }
  }
}
