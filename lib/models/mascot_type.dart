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
  midnightPulse,
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
        return 'AI Aurora';
      case AppColorSeed.liquidGlass:
        return 'Liquid Glass';
      case AppColorSeed.midnightPulse:
        return 'Midnight Pulse';
    }
  }

  String get shortDescription {
    switch (this) {
      case AppColorSeed.aiAurora:
        return 'Intelligent and futuristic';
      case AppColorSeed.liquidGlass:
        return 'Clean and luxurious';
      case AppColorSeed.midnightPulse:
        return 'Powerful and precise';
      default:
        return 'Classic ${label.replaceAll(' (default)', '').toLowerCase()} accent';
    }
  }

  bool get isPremium {
    switch (this) {
      case AppColorSeed.aiAurora:
      case AppColorSeed.liquidGlass:
      case AppColorSeed.midnightPulse:
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
        return const Color(0xFF22D3EE); // aurora cyan
      case AppColorSeed.liquidGlass:
        return const Color(0xFFEAF2FF); // glass highlight
      case AppColorSeed.midnightPulse:
        return const Color(0xFF2563EB); // precise electric blue
    }
  }

  List<Color> get accentColors {
    switch (this) {
      case AppColorSeed.aiAurora:
        return const [
          Color(0xFF22D3EE),
          Color(0xFF45F2D1),
          Color(0xFFA78BFA),
          Color(0xFFF0ABFC),
        ];
      case AppColorSeed.liquidGlass:
        return const [
          Color(0xFFFFFFFF),
          Color(0xFFDDE7F3),
          Color(0xFFB7D8FF),
          Color(0xFFF8FAFC),
        ];
      case AppColorSeed.midnightPulse:
        return const [
          Color(0xFF1D4ED8),
          Color(0xFF4F46E5),
          Color(0xFF7C3AED),
          Color(0xFF38BDF8),
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
        return const Color(0xFF0B0F17);
      case AppColorSeed.liquidGlass:
        return const Color(0xFF101114);
      case AppColorSeed.midnightPulse:
        return const Color(0xFF030712);
    }
  }

  Color get premiumSurfaceColor {
    switch (this) {
      case AppColorSeed.aiAurora:
        return const Color(0xFF111821);
      case AppColorSeed.liquidGlass:
        return const Color(0xFF1A1D22);
      case AppColorSeed.midnightPulse:
        return const Color(0xFF080D1A);
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
        return AppColorSeed.midnightPulse;
      default:
        return AppColorSeed.green;
    }
  }
}
