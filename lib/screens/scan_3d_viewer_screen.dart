import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_localizations.dart';
import '../models/food_data.dart';
import '../models/scan_result.dart';
import '../providers/daily_intake_provider.dart';
import '../services/database_service.dart';
import '../widgets/scan_3d_viewer.dart';
import 'edit_food_screen.dart';

/// Full-screen Stage 3 viewer. Hosts the native SceneKit scene with a clean,
/// always-visible ingredient overview panel underneath: every detected food
/// with its weight (g) and calories, plus tap-to-edit, swipe-to-delete and add.
class Scan3DViewerScreen extends StatefulWidget {
  const Scan3DViewerScreen({
    super.key,
    required this.modelPath,
    this.objects = const [],
    this.scanId,
  });

  final String? modelPath;
  final List<Scan3DObject> objects;

  /// Saved scan id. When non-null, the ingredient overview panel lets the user
  /// fix labels / weights and add or delete foods after the scan.
  final int? scanId;

  @override
  State<Scan3DViewerScreen> createState() => _Scan3DViewerScreenState();
}

class _Scan3DViewerScreenState extends State<Scan3DViewerScreen> {
  Map<String, dynamic>? _viewerError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        // Always provide an explicit exit. The screen is sometimes reached via
        // pushReplacement, where the automatic back button can be absent, which
        // left users with no way out. popUntil(isFirst) always returns home.
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
        title: const Text(
          '3D Scan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Scan3DViewer(
                      modelPath: widget.modelPath,
                      objects: widget.objects,
                      onError: (error) {
                        if (!mounted) return;
                        setState(() => _viewerError = error);
                      },
                    ),
                  ),
                  if (_viewerError != null)
                    const Positioned.fill(
                      child: _ViewerErrorOverlay(),
                    ),
                ],
              ),
            ),
            if (widget.scanId != null) _IngredientPanel(scanId: widget.scanId!),
          ],
        ),
      ),
    );
  }
}

class _ViewerErrorOverlay extends StatelessWidget {
  const _ViewerErrorOverlay();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 44),
              const SizedBox(height: 12),
              Text(
                l10n.scan3dFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-visible panel under the 3D model: the full ingredient overview with
/// each food's weight (g) and calories, plus tap-to-edit, swipe-to-delete and
/// add. Edits persist to the scan and refresh the daily totals.
class _IngredientPanel extends ConsumerStatefulWidget {
  const _IngredientPanel({required this.scanId});

  final int scanId;

  @override
  ConsumerState<_IngredientPanel> createState() => _IngredientPanelState();
}

class _FoodRow {
  const _FoodRow({required this.food, required this.grams});
  final DetectedFood food;
  final double grams;
}

class _IngredientPanelState extends ConsumerState<_IngredientPanel> {
  List<_FoodRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final foods =
        await DatabaseService.instance.getDetectedFoodsForScan(widget.scanId);
    final rows = <_FoodRow>[];
    for (final f in foods) {
      final FoodData? data =
          await DatabaseService.instance.getFoodByLabel(f.label);
      var density =
          data == null ? 0.9 : (data.densityMin + data.densityMax) / 2;
      if (density <= 0) density = 0.9;
      rows.add(_FoodRow(food: f, grams: f.volumeCm3 * density));
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _edit(DetectedFood food) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditFoodScreen(scanId: widget.scanId, food: food),
      ),
    );
    await ref.read(dailyIntakeProvider.notifier).load();
    await _reload();
  }

  Future<void> _delete(DetectedFood food) async {
    if (food.id == null) return;
    await DatabaseService.instance.deleteDetectedFood(food.id!);
    await ref.read(dailyIntakeProvider.notifier).load();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalKcal = _rows.fold<double>(
      0,
      (sum, r) => sum + (r.food.caloriesMin + r.food.caloriesMax) / 2,
    );
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.42,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.editIngredients,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!_loading && _rows.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      '≈ ${totalKcal.round()} kcal',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: l10n.addFood,
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () => _edit(
                    const DetectedFood(
                      label: '',
                      volumeCm3: 0,
                      caloriesMin: 0,
                      caloriesMax: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                l10n.noIngredients,
                style: const TextStyle(color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white10),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final kcal =
                      ((r.food.caloriesMin + r.food.caloriesMax) / 2).round();
                  final gramsText = r.grams >= 10
                      ? r.grams.toStringAsFixed(0)
                      : r.grams.toStringAsFixed(1);
                  return Dismissible(
                    key: ValueKey(r.food.id ?? 'row$i'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red.shade900,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => _delete(r.food),
                    child: ListTile(
                      title: Text(
                        r.food.label.isEmpty ? '—' : r.food.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '$gramsText g · $kcal kcal',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white38),
                      onTap: () => _edit(r.food),
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
