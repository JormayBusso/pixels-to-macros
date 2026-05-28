import 'package:flutter/material.dart';

import '../widgets/scan_3d_viewer.dart';

/// Full-screen Stage 3 viewer. Hosts the native SceneKit scene plus a
/// side panel of detected food objects, mode toggles (combined / isolated),
/// and debug overlays (wireframe + floating volume labels).
///
/// Acceptance criteria mapping (Stage 3):
///   • rotate 3D food model       → native `SCNCameraController` orbit gestures
///   • tap individual food object → native tap hit-test → `onSelectionChanged`
///   • selected object isolates   → mode toggle drives native `setViewMode`
///   • per-object volume metadata → object list rows + floating native labels
///   • Flutter list ↔ SCN nodes   → both keyed by stable cluster `id`
class Scan3DViewerScreen extends StatefulWidget {
  const Scan3DViewerScreen({
    super.key,
    required this.modelPath,
    this.objects = const [],
  });

  final String? modelPath;
  final List<Scan3DObject> objects;

  @override
  State<Scan3DViewerScreen> createState() => _Scan3DViewerScreenState();
}

class _Scan3DViewerScreenState extends State<Scan3DViewerScreen> {
  Scan3DViewerController? _controller;
  String? _selectedId;
  Scan3DViewMode _mode = Scan3DViewMode.combined;
  bool _wireframe = false;
  bool _labels = false;
  bool _debugPanelOpen = false;
  Map<String, dynamic>? _viewerError;

  @override
  Widget build(BuildContext context) {
    final hasModel = widget.modelPath != null && widget.modelPath!.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '3D Scan',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset camera',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: hasModel ? () => _controller?.resetCamera() : null,
          ),
          IconButton(
            tooltip: 'Debug overlays',
            icon: Icon(
              _debugPanelOpen ? Icons.bug_report : Icons.bug_report_outlined,
            ),
            onPressed: hasModel
                ? () => setState(() => _debugPanelOpen = !_debugPanelOpen)
                : null,
          ),
        ],
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
                      onControllerReady: (c) => _controller = c,
                      onSelectionChanged: (id) {
                        if (!mounted) return;
                        setState(() => _selectedId = id);
                      },
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
                  if (hasModel)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 12,
                      child: _ModeToggle(
                        mode: _mode,
                        onChanged: (m) {
                          setState(() => _mode = m);
                          _controller?.setViewMode(m);
                          // If entering isolated mode triggers auto-select
                          // on the native side, it will push onSelectionChanged
                          // — no local mutation needed here.
                        },
                      ),
                    ),
                  if (_debugPanelOpen && hasModel)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _DebugPanel(
                        wireframe: _wireframe,
                        labels: _labels,
                        onWireframe: (v) {
                          setState(() => _wireframe = v);
                          _controller?.setDebugOverlay(wireframe: v);
                        },
                        onLabels: (v) {
                          setState(() => _labels = v);
                          _controller?.setDebugOverlay(labels: v);
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (hasModel && widget.objects.isNotEmpty)
              _ObjectList(
                objects: widget.objects,
                selectedId: _selectedId,
                onTap: (o) {
                  // Route through native — Flutter will reflect state via
                  // onSelectionChanged callback (single source of truth).
                  if (_selectedId == o.id) {
                    _controller?.clearSelection();
                  } else {
                    _controller?.select(o.id);
                  }
                },
                onFocus: (o) {
                  _controller?.focus(o.id);
                },
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
    return const ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
              SizedBox(height: 12),
              Text(
                '3D scan failed. Please rescan.',
                textAlign: TextAlign.center,
                style: TextStyle(
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

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final Scan3DViewMode mode;
  final ValueChanged<Scan3DViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segment('Combined', Scan3DViewMode.combined),
            _segment('Isolated', Scan3DViewMode.isolated),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, Scan3DViewMode value) {
    final selected = value == mode;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.wireframe,
    required this.labels,
    required this.onWireframe,
    required this.onLabels,
  });

  final bool wireframe;
  final bool labels;
  final ValueChanged<bool> onWireframe;
  final ValueChanged<bool> onLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Wireframe',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            value: wireframe,
            onChanged: onWireframe,
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Volume labels',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            value: labels,
            onChanged: onLabels,
          ),
        ],
      ),
    );
  }
}

class _ObjectList extends StatelessWidget {
  const _ObjectList({
    required this.objects,
    required this.selectedId,
    required this.onTap,
    required this.onFocus,
  });

  final List<Scan3DObject> objects;
  final String? selectedId;
  final ValueChanged<Scan3DObject> onTap;
  final ValueChanged<Scan3DObject> onFocus;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: objects.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Colors.white10),
        itemBuilder: (_, i) {
          final o = objects[i];
          final selected = o.id == selectedId;
          return ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: Colors.white.withValues(alpha: 0.06),
            leading: CircleAvatar(
              backgroundColor: selected ? Colors.white : Colors.white24,
              radius: 14,
              child: Text(
                o.label.isNotEmpty ? o.label[0].toUpperCase() : '?',
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text(
              o.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              '${o.volumeCm3.toStringAsFixed(1)} cm³ · ${o.voxelCount} vx · id ${o.id}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
            trailing: IconButton(
              tooltip: 'Focus camera',
              icon: const Icon(Icons.center_focus_weak, color: Colors.white70),
              onPressed: () => onFocus(o),
            ),
            onTap: () => onTap(o),
          );
        },
      ),
    );
  }
}
