import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';

/// Detail view for a single scan result.
class ScanDetailScreen extends ConsumerWidget {
  const ScanDetailScreen({super.key, required this.scan});
  final ScanResult scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avgTotal = (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;
    final margin = (scan.totalCaloriesMax - scan.totalCaloriesMin) / 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppTheme.red500),
            tooltip: 'Delete scan',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header card ──────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.check_circle,
                      size: 48, color: AppTheme.green500),
                  const SizedBox(height: 12),
                  Text(
                    '${avgTotal.round()} kcal',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                  Text(
                    '± ${margin.round()} kcal',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.gray400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _InfoChip(
                        icon: Icons.visibility,
                        label: scan.depthMode,
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.restaurant,
                        label:
                            '${scan.foods.length} item${scan.foods.length == 1 ? '' : 's'}',
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.access_time,
                        label: _formatTime(scan.timestamp),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Date info ────────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      size: 18, color: AppTheme.green500),
                  const SizedBox(width: 12),
                  Text(
                    _formatFullDate(scan.timestamp),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Food items ───────────────────────────────────────────────
          Text(
            'Detected Foods',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 8),
          ...scan.foods.map((f) => _FoodDetailCard(food: f)),

          // ── Calorie range breakdown ──────────────────────────────────
          const SizedBox(height: 16),
          Text(
            'Calorie Range',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.gray700,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _RangeRow(
                    label: 'Minimum',
                    value: '${scan.totalCaloriesMin.round()} kcal',
                    color: AppTheme.green600,
                  ),
                  const SizedBox(height: 8),
                  _RangeRow(
                    label: 'Average',
                    value: '${avgTotal.round()} kcal',
                    color: AppTheme.gray900,
                  ),
                  const SizedBox(height: 8),
                  _RangeRow(
                    label: 'Maximum',
                    value: '${scan.totalCaloriesMax.round()} kcal',
                    color: AppTheme.amber700,
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: scan.totalCaloriesMin.round(),
                          child: Container(
                            height: 8,
                            color: AppTheme.green400,
                          ),
                        ),
                        Expanded(
                          flex: (avgTotal - scan.totalCaloriesMin).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: AppTheme.green200,
                          ),
                        ),
                        Expanded(
                          flex: (scan.totalCaloriesMax - avgTotal).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: AppTheme.amber500.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete scan?'),
        content:
            const Text('This will permanently remove this scan entry.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppTheme.red500)),
          ),
        ],
      ),
    );
    if (confirmed == true && scan.id != null) {
      await ref.read(historyProvider.notifier).deleteScan(scan.id!);
      await ref.read(dailyIntakeProvider.notifier).load();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFullDate(DateTime dt) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at ${_formatTime(dt)}';
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.green50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.green200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.green600),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.green700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodDetailCard extends StatelessWidget {
  const _FoodDetailCard({required this.food});
  final DetectedFood food;

  @override
  Widget build(BuildContext context) {
    final avg = (food.caloriesMin + food.caloriesMax) / 2;
    final margin = (food.caloriesMax - food.caloriesMin) / 2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.green100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.restaurant,
                    color: AppTheme.green600, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${food.volumeCm3.toStringAsFixed(1)} cm³',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.gray400,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${avg.round()} kcal',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.green700,
                    ),
                  ),
                  Text(
                    '± ${margin.round()}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.gray400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppTheme.gray400)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
