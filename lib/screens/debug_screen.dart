import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log.dart';
import '../theme/app_theme.dart';

/// Screen that displays the debug log and allows export (Part 14).
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  List<LogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _entries = DebugLog.instance.entries;
    });
  }

  Future<void> _exportToClipboard() async {
    final text = DebugLog.instance.export();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debug log copied to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy to clipboard',
            onPressed: _exportToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () {
              DebugLog.instance.clear();
              _refresh();
            },
          ),
        ],
      ),
      body: _entries.isEmpty
          ? Center(
              child: Text(
                'No log entries',
                style: TextStyle(color: AppTheme.gray400, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _entries.length,
              reverse: true, // newest first
              itemBuilder: (context, index) {
                // Reverse index so newest is at top
                final entry = _entries[_entries.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    entry.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
