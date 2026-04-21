import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../providers/history_provider.dart';
import '../services/data_export_service.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';
import '../widgets/confidence_badge.dart';
import 'edit_food_screen.dart';
import 'ground_truth_screen.dart';

/// Detail view for a single scan result.
class ScanDetailScreen extends ConsumerStatefulWidget {
  const ScanDetailScreen({super.key, required this.scan});
  final ScanResult scan;

  @override
  ConsumerState<ScanDetailScreen> createState() => _ScanDetailScreenState();
}

class _ScanDetailScreenState extends ConsumerState<ScanDetailScreen> {
  late ScanResult _scan;

  @override
  void initState() {
    super.initState();
    _scan = widget.scan;
  }

  Future<void> _refresh() async {
    await ref.read(historyProvider.notifier).load();
    final history = ref.read(historyProvider);
    final updated = history.scans.where((s) => s.id == _scan.id).firstOrNull;
    if (updated != null) {
      setState(() => _scan = updated);
    }
  }

  void _editFood(DetectedFood food) async {
    if (_scan.id == null) return;
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditFoodScreen(scanId: _scan.id!, food: food),
      ),
    );
    if (edited == true) {
      await _refresh();
    }
  }

  void _recordGroundTruth(DetectedFood food) async {
    if (_scan.id == null || food.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroundTruthScreen(
          scanId: _scan.id!,
          food: food,
        ),
      ),
    );
  }

  Future<void> _exportPLY() async {
    final ply = await NativeBridge.instance.exportPointCloud();
    if (ply == null || ply.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No depth data available for point cloud')),
        );
      }
      return;
    }
    final path = await DataExportService.instance.saveToFile(
      ply,
      'scan_${_scan.id}_${DateTime.now().millisecondsSinceEpoch}.ply',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PLY saved to $path')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgTotal = (_scan.totalCaloriesMin + _scan.totalCaloriesMax) / 2;
    final margin = (_scan.totalCaloriesMax - _scan.totalCaloriesMin) / 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            tooltip: 'Export 3D point cloud',
            onPressed: _exportPLY,
          ),
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
                        label: _scan.depthMode,
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.restaurant,
                        label:
                            '${_scan.foods.length} item${_scan.foods.length == 1 ? '' : 's'}',
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.access_time,
                        label: _formatTime(_scan.timestamp),
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
                    _formatFullDate(_scan.timestamp),
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

          // ── Confidence score ─────────────────────────────────────────
          ConfidenceRingCard(
            caloriesMin: _scan.totalCaloriesMin,
            caloriesMax: _scan.totalCaloriesMax,
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
          ..._scan.foods.map((f) => _FoodDetailRow(
                food: f,
                onEdit: () => _editFood(f),
                onGroundTruth: () => _recordGroundTruth(f),
              )),

          // Tap hint
          if (_scan.foods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Tap to edit  •  Long-press for ground truth',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppTheme.gray400),
              ),
            ),

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
                    value: '${_scan.totalCaloriesMin.round()} kcal',
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
                    value: '${_scan.totalCaloriesMax.round()} kcal',
                    color: AppTheme.amber700,
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: _scan.totalCaloriesMin.round(),
                          child: Container(
                            height: 8,
                            color: AppTheme.green400,
                          ),
                        ),
                        Expanded(
                          flex: (avgTotal - _scan.totalCaloriesMin).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: AppTheme.green200,
                          ),
                        ),
                        Expanded(
                          flex: (_scan.totalCaloriesMax - avgTotal).round().clamp(1, 9999),
                          child: Container(
                            height: 8,
                            color: AppTheme.amber500.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Camera pose data (Part 9) ──────────────────────────────────
          if (_scan.topCameraPosition != null ||
              _scan.sideCameraPosition != null) ...[
            const SizedBox(height: 16),
            Text(
              'Camera Pose',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_scan.topCameraPosition != null)
                      _InfoRow(
                        label: 'Top position',
                        value: _scan.topCameraPosition!,
                      ),
                    if (_scan.sideCameraPosition != null)
                      _InfoRow(
                        label: 'Side position',
                        value: _scan.sideCameraPosition!,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Full 4×4 transform stored for geometry reconstruction',
                      style: TextStyle(fontSize: 11, color: AppTheme.gray400),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    if (confirmed == true && _scan.id != null) {
      await ref.read(historyProvider.notifier).deleteScan(_scan.id!);
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppTheme.gray400)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
                color: AppTheme.gray700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodDetailRow extends StatelessWidget {
  const _FoodDetailRow({
    required this.food,
    required this.onEdit,
    required this.onGroundTruth,
  });
  final DetectedFood food;
  final VoidCallback onEdit;
  final VoidCallback onGroundTruth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onGroundTruth();
      },
      child: _FoodDetailCard(food: food),
    );
  }
}

class _FoodDetailCard extends StatelessWidget {
  const _FoodDetailCard({required this.food});
  final DetectedFood food;

  /// Returns a color indicating uncertainty: green=low, amber=med, red=high.
  Color _uncertaintyColor(double margin, double avg) {
    if (avg == 0) return AppTheme.gray200;
    final pct = margin / avg; // relative uncertainty
    if (pct < 0.15) return AppTheme.green400;
    if (pct < 0.30) return AppTheme.amber500;
    return AppTheme.red500;
  }

  @override
  Widget build(BuildContext context) {
    final avg = (food.caloriesMin + food.caloriesMax) / 2;
    final margin = (food.caloriesMax - food.caloriesMin) / 2;
    final uColor = _uncertaintyColor(margin, avg);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
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
                  const SizedBox(width: 4),
                  Icon(Icons.edit, size: 14, color: AppTheme.gray300),
                ],
              ),
              // ── Uncertainty bar ────────────────────────────────────────
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${food.caloriesMin.round()}',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background track
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.gray100,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Uncertainty range
                        FractionallySizedBox(
                          widthFactor: avg > 0
                              ? ((food.caloriesMax - food.caloriesMin) /
                                      (food.caloriesMax * 1.2))
                                  .clamp(0.05, 1.0)
                              : 0.05,
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: uColor.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        // Center dot (average)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: uColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${food.caloriesMax.round()}',
                    style: TextStyle(fontSize: 10, color: AppTheme.gray400),
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
