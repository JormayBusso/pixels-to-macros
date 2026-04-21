import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';

/// Displays past scan results from SQLite (Part 13 — result history).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(historyProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan History')),
      body: history.loading
          ? const Center(child: CircularProgressIndicator())
          : history.scans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 64, color: AppTheme.gray200),
                      const SizedBox(height: 16),
                      Text(
                        'No scans yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gray400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan some food to see results here',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.gray400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: history.scans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _ScanCard(scan: history.scans[index]),
                ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan});
  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    final avgTotal =
        (scan.totalCaloriesMin + scan.totalCaloriesMax) / 2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.green100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scan.depthMode,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.green700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(scan.timestamp),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.gray400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Food items
            ...scan.foods.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant,
                          size: 14, color: AppTheme.green500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${f.volumeCm3.toStringAsFixed(1)} cm³',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.gray400,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        f.displayCalories.split(': ').last,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )),

            const Divider(height: 20),

            // Total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${avgTotal.round()} kcal',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.green700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
