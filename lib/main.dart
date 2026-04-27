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

  DebugLog.instance.log('App', 'Starting Pixels to Macros');

  try {
    await DatabaseService.instance.database;
    DebugLog.instance.log('App', 'Database initialized');
  } catch (e) {
    DebugLog.instance.log('App', 'Database init failed: $e');
  }

  runApp(
    const ProviderScope(
      child: PixelsToMacrosApp(),
    ),
  );
}
