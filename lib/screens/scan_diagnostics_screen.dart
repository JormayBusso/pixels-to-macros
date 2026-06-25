import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_diagnostics.dart';
import '../providers/scan_diagnostics_provider.dart';
import '../services/debug_log.dart';

/// Developer-facing scanner diagnostics viewer.
///
/// Surfaces the per-scan reconstruction telemetry (depth mode, timings, and the
/// per-food volume / scale / silhouette / guardrail data) that the native
/// pipeline already produces. Intended for the scanner validation phase: scan a
/// known-weight item repeatedly and compare the captured numbers here.
class ScanDiagnosticsScreen extends ConsumerWidget {
  const ScanDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scans = ref.watch(scanDiagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_all),
            onPressed: scans.isEmpty
                ? null
                : () {
                    final text = [
                      ...scans.map((s) => s.toReport()),
                      '',
                      '── Debug log ──',
                      DebugLog.instance.export(),
                    ].join('\n');
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Diagnostics copied to clipboard'),
                      ),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: scans.isEmpty
                ? null
                : () => ref.read(scanDiagnosticsProvider.notifier).clear(),
          ),
        ],
      ),
      body: scans.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: scans.length,
              itemBuilder: (context, i) => _ScanCard(
                diagnostics: scans[i],
                index: scans.length - i,
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_outlined,
                size: 56, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text(
              'No scans captured yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Run a scan, then return here to inspect the reconstruction '
              'telemetry (volume, scale source, silhouette usage, guardrails).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.diagnostics, required this.index});

  final ScanDiagnostics diagnostics;
  final int index;

  @override
  Widget build(BuildContext context) {
    final d = diagnostics;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text('Scan #$index · ${d.depthMode}'),
        subtitle: Text(
          '${d.foods.length} food(s) · '
          'inference ${d.inferenceMs}ms · total ${d.totalMs}ms',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (d.peakMemoryBytes > 0)
                  _chip(
                      'mem ${(d.peakMemoryBytes / 1048576).toStringAsFixed(0)}MB'),
                if (d.ambientLux != null)
                  _chip('lux ${d.ambientLux!.toStringAsFixed(0)}'),
                if (d.stability != null)
                  _chip('stable ${(d.stability! * 100).toStringAsFixed(0)}%'),
                _chip('record ${d.recordMs}ms'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...d.foods.map((f) => _FoodRow(food: f)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: d.toReport()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Scan diagnostics copied')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Chip(
        label: Text(text, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.food});

  final FoodDiagnostic food;

  @override
  Widget build(BuildContext context) {
    final f = food;
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                child: Text(k, style: TextStyle(fontSize: 12, color: muted)),
              ),
              Expanded(
                child: Text(v,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(f.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              _modeBadge(context, f),
            ],
          ),
          const SizedBox(height: 4),
          kv(
              'volume',
              '${f.volumeCm3.toStringAsFixed(1)} cm³'
                  '${f.rawVolumeCm3 != null ? '  (raw ${f.rawVolumeCm3!.toStringAsFixed(1)})' : ''}'),
          if (f.weightG != null)
            kv(
                'weight',
                '${f.weightG!.toStringAsFixed(0)} g'
                    '${f.densityGCm3 != null ? '  @ ${f.densityGCm3} g/cm³' : ''}'),
          if (f.footprintAreaCm2 != null || f.heightCm != null)
            kv(
                'geometry',
                'footprint ${f.footprintAreaCm2?.toStringAsFixed(1) ?? '-'} cm² · '
                    'height ${f.heightCm?.toStringAsFixed(1) ?? '-'} cm'),
          kv(
              'scale',
              '${f.scaleSource ?? '-'}'
                  '${f.pixelsPerCm != null ? '  (${f.pixelsPerCm} px/cm)' : ''}'
                  '${f.fallbackReason != null && f.fallbackReason != 'none' ? '  · fallback: ${f.fallbackReason}' : ''}'),
          if (f.confidence != null ||
              f.scaleConfidence != null ||
              f.segmentationConfidence != null ||
              f.silhouetteConfidence != null)
            kv(
                'confidence',
                'overall ${f.confidence?.toStringAsFixed(2) ?? '-'} · '
                    'scale ${f.scaleConfidence?.toStringAsFixed(2) ?? '-'} · '
                    'seg ${f.segmentationConfidence?.toStringAsFixed(2) ?? '-'} · '
                    'sil ${f.silhouetteConfidence?.toStringAsFixed(2) ?? '-'}'
                    '${f.lowConfidence == true ? '  ⚠ LOW' : ''}'),
          if (f.temporalSmoothingApplied == true)
            kv('temporal',
                'smoothed across ${f.temporalSamples ?? '-'} scans'),
          kv(
              'views',
              'side=${f.sideViewApplied ?? false} · '
                  'fallback=${f.fallbackUsed ?? false} · '
                  'both=${f.usedBothViews}'),
          if (f.guardrailApplied == true)
            kv('guardrail', 'softened (≤ ${f.guardrailUpperCm3 ?? '-'} cm³)'),
          if (f.debug != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(f.debug!,
                  style: TextStyle(
                      fontSize: 11, fontStyle: FontStyle.italic, color: muted)),
            ),
        ],
      ),
    );
  }

  Widget _modeBadge(BuildContext context, FoodDiagnostic f) {
    final bothViews = f.usedBothViews;
    final color = bothViews ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        f.scanMode,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
