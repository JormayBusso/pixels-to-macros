import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DrinkSheet extends StatefulWidget {
  const DrinkSheet({super.key, required this.onLog});

  final void Function(String label, double ml) onLog;

  @override
  State<DrinkSheet> createState() => _DrinkSheetState();
}

class _DrinkSheetState extends State<DrinkSheet> {
  final _customCtrl = TextEditingController();
  String _selectedDrink = 'water';

  static const _presets = [
    ('water', 'Water'),
    ('coffee', 'Coffee'),
    ('tea', 'Tea'),
    ('milk', 'Milk'),
    ('juice', 'Juice'),
    ('soda', 'Soda'),
  ];

  static const _sizes = [
    (150.0, 'Small\n150 ml', Icons.local_drink_outlined),
    (250.0, 'Medium\n250 ml', Icons.local_drink),
    (400.0, 'Large\n400 ml', Icons.coffee_outlined),
    (500.0, 'Bottle\n500 ml', Icons.water_drop_outlined),
  ];

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.local_drink_outlined, color: Color(0xFF1976D2)),
              SizedBox(width: 8),
              Text(
                'Quick Drink',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((preset) {
                final selected = _selectedDrink == preset.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(preset.$2),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _selectedDrink = preset.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: _sizes.map((size) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onLog(_selectedDrink, size.$1),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.gray100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.gray200),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(size.$3, size: 28, color: const Color(0xFF1976D2)),
                      const SizedBox(height: 4),
                      Text(
                        size.$2,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const Text(
            'Or enter amount:',
            style: TextStyle(fontSize: 12, color: AppTheme.gray600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'ml',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () {
                  final ml = double.tryParse(_customCtrl.text);
                  if (ml != null && ml > 0) widget.onLog(_selectedDrink, ml);
                },
                child: const Text('Log'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
