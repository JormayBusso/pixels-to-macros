import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/database_service.dart';
import 'services/debug_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global last-resort error handlers ───────────────────────────────────
  // These ensure the app NEVER force-quits on an uncaught exception.
  // All errors are logged so they can be reviewed in the Debug Log screen.
  FlutterError.onError = (FlutterErrorDetails details) {
    DebugLog.instance.log(
      'Flutter',
      'Uncaught Flutter error:\n'
      '${details.exception}\n'
      '${details.stack ?? "(no stack trace)"}',
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    DebugLog.instance.log(
      'Platform',
      'Uncaught async error:\n$error\n$stack',
    );
    // Returning true tells Flutter we handled the error — do NOT terminate.
    return true;
  };

  // ── Replace red crash screen with a friendly "go back" widget ───────────
  // If any widget's build() throws, Flutter shows this instead of crashing.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    DebugLog.instance.log(
      'Widget',
      'Build error: ${details.exception}\n${details.stack ?? ""}',
    );
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Colors.orange,
                ),
                const SizedBox(height: 20),
                const Text(
                  'This screen ran into an error.',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Please press Back to return to the home screen.',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  DebugLog.instance.log('App', 'Starting Pixels to Macros');

  try {
    await DatabaseService.instance.database
        .timeout(const Duration(seconds: 10));
    DebugLog.instance.log('App', 'Database initialized');
  } catch (e) {
    DebugLog.instance.log('App', 'Database init failed (will retry later): $e');
  }

  runApp(
    const ProviderScope(
      child: PixelsToMacrosApp(),
    ),
  );
}
