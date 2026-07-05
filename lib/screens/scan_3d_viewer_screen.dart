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
  final GlobalKey<_IngredientPanelState> _ingredientPanelKey =
      GlobalKey<_IngredientPanelState>();

  Map<String, dynamic>? _viewerError;
  Scan3DViewerController? _viewerController;
  String? _selectedObjectId;

  Scan3DObject? get _selectedObject {
    final id = _selectedObjectId;
    if (id == null) return null;
    for (final object in widget.objects) {
      if (object.id == id) return object;
    }
    return null;
  }

  void _handleObjectSelection(String? id) {
    if (!mounted) return;
    setState(() => _selectedObjectId = id);
  }

  Future<void> _editSelectedObject() async {
    final object = _selectedObject;
    if (object == null) return;
    final edited = await _ingredientPanelKey.currentState?.editObject(object);
    if (!mounted || edited == true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected ${object.label}; no saved ingredient row matched it yet.')),
    );
  }

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
                      onControllerReady: (controller) {
                        _viewerController = controller;
                      },
                      onSelectionChanged: _handleObjectSelection,
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
                  _DepthDebugButton(objects: widget.objects),
                  if (_selectedObject != null)
                    _SelectedObjectBanner(
                      object: _selectedObject!,
                      onEdit: _editSelectedObject,
                      onClear: () async {
                        await _viewerController?.clearSelection();
                        if (mounted) setState(() => _selectedObjectId = null);
                      },
                    ),
                ],
              ),
            ),
            if (widget.scanId != null)
              _IngredientPanel(
                key: _ingredientPanelKey,
                scanId: widget.scanId!,
                objects: widget.objects,
                selectedObjectId: _selectedObjectId,
                onFocusObject: (id) => _viewerController?.focus(id),
              ),
            // Explicit "log" confirmation. The scan is already saved to today's
            // diary on capture, but users expect a clear button to finish and
            // log it — this confirms and returns home.
            Container(
              width: double.infinity,
              color: const Color(0xFF141414),
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
              child: FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Logged to today\u2019s diary'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Log to today\u2019s diary'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Depth/scale diagnostics entry point. The full readout opens in a draggable,
/// scrollable sheet so ingredients can never cover it.
class _DepthDebugButton extends StatelessWidget {
  const _DepthDebugButton({required this.objects});

  final List<Scan3DObject> objects;

  @override
  Widget build(BuildContext context) {
    final rows = objects.where((o) => o.debug != null).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 8,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showDepthDebugSheet(context, rows),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.55)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bug_report, color: Colors.tealAccent, size: 15),
                SizedBox(width: 6),
                Text(
                  'Depth debug',
                  style: TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDepthDebugSheet(BuildContext context, List<Scan3DObject> rows) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0B0F10),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.bug_report, color: Colors.tealAccent, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Depth debug',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final object in rows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          object.label,
                          style: const TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          object.debug ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            height: 1.35,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SelectedObjectBanner extends StatelessWidget {
  const _SelectedObjectBanner({
    required this.object,
    required this.onEdit,
    required this.onClear,
  });

  final Scan3DObject object;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            const Icon(Icons.touch_app, color: Colors.tealAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Selected ${object.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton(
              onPressed: onEdit,
              child: const Text('Edit'),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(Icons.close, color: Colors.white60, size: 18),
            ),
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
  const _IngredientPanel({
    super.key,
    required this.scanId,
    required this.objects,
    required this.selectedObjectId,
    required this.onFocusObject,
  });

  final int scanId;
  final List<Scan3DObject> objects;
  final String? selectedObjectId;
  final ValueChanged<String> onFocusObject;

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
    if (food.label.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Editing ${food.label}'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditFoodScreen(scanId: widget.scanId, food: food),
      ),
    );
    await ref.read(dailyIntakeProvider.notifier).load();
    await _reload();
  }

  Future<bool> editObject(Scan3DObject object) async {
    final row = _rowForObject(object);
    if (row == null) return false;
    await _edit(row.food);
    return true;
  }

  _FoodRow? _rowForObject(Scan3DObject object) {
    final objectLabel = _normaliseIngredientName(object.label);
    for (final row in _rows) {
      if (_normaliseIngredientName(row.food.label) == objectLabel) return row;
    }
    return null;
  }

  Scan3DObject? _objectForFood(DetectedFood food) {
    final foodLabel = _normaliseIngredientName(food.label);
    for (final object in widget.objects) {
      if (_normaliseIngredientName(object.label) == foodLabel) return object;
    }
    return null;
  }

  bool _isSelected(DetectedFood food) {
    final selected = widget.selectedObjectId;
    if (selected == null) return false;
    return _objectForFood(food)?.id == selected;
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
                  final selected = _isSelected(r.food);
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.tealAccent.withValues(alpha: 0.10)
                            : Colors.transparent,
                        border: selected
                            ? const Border(
                                left: BorderSide(
                                  color: Colors.tealAccent,
                                  width: 3,
                                ),
                              )
                            : null,
                      ),
                      child: ListTile(
                        title: Text(
                          r.food.label.isEmpty ? '—' : r.food.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          selected
                              ? '$gramsText g · $kcal kcal · selected in 3D'
                              : '$gramsText g · $kcal kcal · tap to edit',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white38),
                        onTap: () {
                          final object = _objectForFood(r.food);
                          if (object != null) widget.onFocusObject(object.id);
                          _edit(r.food);
                        },
                      ),
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

String _normaliseIngredientName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();
