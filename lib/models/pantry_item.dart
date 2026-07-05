class PantryItem {
  const PantryItem({
    this.id,
    required this.name,
    this.category,
    this.quantity = 1,
    this.unit,
    this.available = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PantryItem.fromMap(Map<String, dynamic> map) => PantryItem(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        category: map['category'] as String?,
        quantity: (map['quantity'] as num?)?.toDouble() ?? 1,
        unit: map['unit'] as String?,
        available: (map['available'] as int?) != 0,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  final int? id;
  final String name;
  final String? category;
  final double quantity;
  final String? unit;
  final bool available;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category,
        'quantity': quantity,
        'unit': unit,
        'available': available ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  PantryItem copyWith({
    int? id,
    String? name,
    String? category,
    double? quantity,
    String? unit,
    bool? available,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PantryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      available: available ?? this.available,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Normalised key for matching a pantry item against a logged food label or
  /// another item name (case-insensitive, trimmed, plural-tolerant).
  static String normalizeKey(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.length > 3 && s.endsWith('s')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
