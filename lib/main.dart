import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/app_recovery_service.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/debug_log.dart';

void main() {
  runZonedGuarded<void>(() {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      AppRecoveryService.recover(
        details.exception,
        details.stack,
        source: 'Flutter',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      AppRecoveryService.recover(error, stack, source: 'Platform');
      return true;
    };

    ErrorWidget.builder = AppRecoveryService.buildErrorWidget;

    DebugLog.instance.log('App', 'Starting Pixels to Macros');

    // Initialize Supabase (no-op if .env not configured yet).
    unawaited(
      initSupabase()
          .then((_) => DebugLog.instance.log('App', 'Supabase initialized'))
          .catchError((e) => DebugLog.instance.log('App', 'Supabase init skipped: $e')),
    );

    unawaited(
      DatabaseService.instance.database
          .timeout(const Duration(seconds: 10))
          .then((_) => DebugLog.instance.log('App', 'Database initialized'))
          .catchError((e, st) {
        DebugLog.instance
            .log('App', 'Database init failed (will retry later): $e\n$st');
      }),
    );

    runApp(
      const ProviderScope(
        child: PixelsToMacrosApp(),
      ),
    );
  }, (error, stack) {
    AppRecoveryService.recover(error, stack, source: 'Zone');
  });
}
