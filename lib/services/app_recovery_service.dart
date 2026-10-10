import 'dart:async';

import 'package:flutter/material.dart';

import 'debug_log.dart';

class AppRecoveryService {
  AppRecoveryService._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static final homeRecoverySignal = ValueNotifier<int>(0);

  static bool _recovering = false;
  static Timer? _recoveryResetTimer;

  static void recover(
    Object error,
    StackTrace? stack, {
    String source = 'App',
  }) {
    DebugLog.instance.log(
      source,
      'Recovering from error:\n$error\n${stack ?? "(no stack trace)"}',
    );

    if (_recovering) return;
    _recovering = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        final navigator = navigatorKey.currentState;
        if (navigator != null) {
          navigator.popUntil((route) => route.isFirst);
        }

        homeRecoverySignal.value = homeRecoverySignal.value + 1;
        _showRecoveryMessage();

        _recoveryResetTimer?.cancel();
        _recoveryResetTimer = Timer(const Duration(milliseconds: 750), () {
          _recovering = false;
        });
      });
    });
  }

  static Widget buildErrorWidget(FlutterErrorDetails details) {
    recover(details.exception, details.stack, source: 'Widget');
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
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Try again, or try again later.',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => recover(
                    details.exception,
                    details.stack,
                    source: 'Widget retry',
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showRecoveryMessage() {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Something went wrong. Try again later.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
