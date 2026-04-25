import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../theme/app_theme.dart';
import 'scan_detail_screen.dart';

/// Displays past scan results from SQLite (Part 13 — result history).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    ref.read(historyProvider.notifier).load();
  }

  List<ScanResult> get _filteredScans {
    final scans = ref.read(historyProvider).scans;
    if (_searchQuery.isEmpty) return scans;
    final q = _searchQuery.toLowerCase();
    return scans.where((s) {
      return s.foods.any((f) => f.label.toLowerCase().contains(q)) ||
          s.depthMode.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final filtered = _filteredScans;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan History')),
      body: history.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (q) => setState(() => _searchQuery = q),
                    decoration: const InputDecoration(
                      hintText: 'Search by food name...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                if (history.scans.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          '${filtered.length} of ${history.scans.length} scans',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.gray400,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),

                // ── List ───────────────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _searchQuery.isEmpty ? Icons.history : Icons.search_off,
                        size: 64,
                        color: AppTheme.gray200,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'No scans yet'
                            : 'No matching scans',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.gray400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Scan some food to see results here'
                            : 'Try a different search term',
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
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final scan = filtered[index];
                    return Dismissible(
                      key: ValueKey(scan.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.red500,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete scan?'),
                            content: const Text(
                                'This will permanently remove this scan entry.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Delete',
                                    style: TextStyle(color: AppTheme.red500)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) {
                        if (scan.id != null) {
                          ref.read(historyProvider.notifier).deleteScan(scan.id!);
                          ref.read(dailyIntakeProvider.notifier).load();
                        }
                      },
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ScanDetailScreen(scan: scan),
                          ),
                        ),
                        child: _ScanCard(scan: scan),
                      ),
                    );
                  },
                ),
              ),
            ],
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
                    color: context.primary100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    scan.depthMode,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.primary700,
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
                      Icon(Icons.restaurant,
                          size: 14, color: context.primary500),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.primary700,
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
