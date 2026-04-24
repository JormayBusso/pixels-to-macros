/// Represents one item on the user's grocery list.
class GroceryItem {
  final int? id;
  final String name;
  final String? category;
  final int quantity;
  final bool checked;
  final DateTime createdAt;

  const GroceryItem({
    this.id,
    required this.name,
    this.category,
    this.quantity = 1,
    this.checked = false,
    required this.createdAt,
  });

  factory GroceryItem.fromMap(Map<String, dynamic> map) {
    return GroceryItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String?,
      quantity: (map['quantity'] as int?) ?? 1,
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
      'checked': checked ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  GroceryItem copyWith({
    String? name,
    String? category,
    int? quantity,
    bool? checked,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      checked: checked ?? this.checked,
      createdAt: createdAt,
    );
  }
}
