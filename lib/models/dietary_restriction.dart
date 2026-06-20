enum DietaryRestriction {
  glutenFree,
  dairyFree,
  nutFree,
}

extension DietaryRestrictionX on DietaryRestriction {
  String get dbValue => name;

  String get label {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Gluten-Free';
      case DietaryRestriction.dairyFree:
        return 'Lactose-Free / Dairy-Free';
      case DietaryRestriction.nutFree:
        return 'Nut-Free';
    }
  }

  String get shortLabel {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Gluten-Free';
      case DietaryRestriction.dairyFree:
        return 'Dairy-Free';
      case DietaryRestriction.nutFree:
        return 'Nut-Free';
    }
  }

  String get description {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return 'Filters wheat, rye, barley, malt, seitan, flour, pasta, bread, and similar gluten sources.';
      case DietaryRestriction.dairyFree:
        return 'Filters milk, lactose, cheese, yogurt, cream, butter, whey, casein, and similar dairy sources.';
      case DietaryRestriction.nutFree:
        return 'Filters tree nuts and peanut ingredients, including nut butters, nut flours, and common nut oils.';
    }
  }

  List<String> get triggerTerms {
    switch (this) {
      case DietaryRestriction.glutenFree:
        return const [
          'wheat',
          'barley',
          'rye',
          'malt',
          'spelt',
          'farro',
          'bulgur',
          'couscous',
          'seitan',
          'gluten',
          'flour',
          'pasta',
          'noodle',
          'bread',
          'breadcrumbs',
          'cracker',
          'tortilla',
          'wrap',
        ];
      case DietaryRestriction.dairyFree:
        return const [
          'milk',
          'lactose',
          'cheese',
          'yogurt',
          'yoghurt',
          'cream',
          'butter',
          'whey',
          'casein',
          'curd',
          'paneer',
          'ghee',
          'mozzarella',
          'parmesan',
          'feta',
          'ricotta',
          'cottage cheese',
        ];
      case DietaryRestriction.nutFree:
        return const [
          'nut',
          'almond',
          'walnut',
          'cashew',
          'peanut',
          'hazelnut',
          'pecan',
          'pistachio',
          'macadamia',
          'brazil nut',
          'pine nut',
          'nut butter',
          'almond flour',
          'peanut butter',
          'tahini',
        ];
    }
  }

  bool matchesText(String text) {
    final lower = text.toLowerCase();
    for (final term in triggerTerms) {
      final pattern = RegExp(
        r'(^|[^a-z])' + RegExp.escape(term.toLowerCase()) + r'([^a-z]|$)',
      );
      if (pattern.hasMatch(lower)) return true;
    }
    return false;
  }

  String alertFor(String itemName) =>
      '$itemName may not fit your $shortLabel setting. Check ingredients and labels before logging it.';

  static DietaryRestriction? fromDbValue(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final restriction in DietaryRestriction.values) {
      if (restriction.dbValue == normalized) return restriction;
    }
    return null;
  }
}

abstract final class DietaryRestrictionCodec {
  static String encode(Set<DietaryRestriction> restrictions) {
    final values = restrictions
        .map((restriction) => restriction.dbValue)
        .toList(growable: false);
    final sorted = values.toList()..sort();
    return sorted.join(',');
  }

  static Set<DietaryRestriction> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <DietaryRestriction>{};
    return raw
        .split(',')
        .map(DietaryRestrictionX.fromDbValue)
        .whereType<DietaryRestriction>()
        .toSet();
  }
}
