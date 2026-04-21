import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Exportable in-memory debug log buffer (Part 14).
///
/// Keeps the last [maxEntries] log entries in a ring buffer.
/// Entries can be exported as plain text for sharing / bug reports.
class DebugLog {
  DebugLog._();
  static final DebugLog instance = DebugLog._();

  static const int maxEntries = 500;

  final _entries = Queue<LogEntry>();

  /// Add a timestamped log entry.
  void log(String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
    );

    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }

    // Also print in debug mode
    debugPrint('[${entry.tag}] ${entry.message}');
  }

  /// All entries oldest-first.
  List<LogEntry> get entries => _entries.toList();

  /// Export the log as a plain-text string for sharing.
  String export() {
    final buf = StringBuffer();
    buf.writeln('=== Pixels to Macros — Debug Log ===');
    buf.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buf.writeln('Entries: ${_entries.length}');
    buf.writeln('');
    for (final e in _entries) {
      buf.writeln(e.toString());
    }
    return buf.toString();
  }

  void clear() => _entries.clear();
}

class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
  });

  @override
  String toString() {
    final ts = timestamp.toIso8601String().substring(11, 23); // HH:mm:ss.SSS
    return '$ts [$tag] $message';
  }
}
