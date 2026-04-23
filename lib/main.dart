import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/database_service.dart';
import 'services/debug_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
