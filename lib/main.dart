import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite and seed default food data
  await DatabaseService.instance.database;

  runApp(
    const ProviderScope(
      child: PixelsToMacrosApp(),
    ),
  );
}
