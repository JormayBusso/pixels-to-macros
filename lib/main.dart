import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/database_service.dart';
import 'services/debug_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DebugLog.instance.log('App', 'Starting Pixels to Macros');

  // Initialize SQLite and seed default food data
  await DatabaseService.instance.database;
  DebugLog.instance.log('App', 'Database initialized');

  runApp(
    const ProviderScope(
      child: PixelsToMacrosApp(),
    ),
  );
}
