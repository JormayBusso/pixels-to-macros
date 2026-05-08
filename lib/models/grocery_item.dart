/// Represents one item on the user's grocery list.
class GroceryItem {
  final int? id;
  final String name;
  final String? category;
  final int quantity;
  final String? unit; // 'g', 'ml', 'kg', 'L', 'pack', 'box', 'bunch', etc.
  final bool checked;
  final DateTime createdAt;

  const GroceryItem({
    this.id,
    required this.name,
    this.category,
    this.quantity = 1,
    this.unit,
    this.checked = false,
    required this.createdAt,
  });

  factory GroceryItem.fromMap(Map<String, dynamic> map) {
    return GroceryItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String?,
      quantity: (map['quantity'] as int?) ?? 1,
      unit: map['unit'] as String?,
      checked: (map['checked'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'quantity': quantity,
      if (unit != null) 'unit': unit,
      'checked': checked ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  GroceryItem copyWith({
    String? name,
    String? category,
    int? quantity,
    String? unit,
    bool? checked,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      checked: checked ?? this.checked,
      createdAt: createdAt,
    );
  }
}
