import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// Best-effort monitoring, independent of the push notification setting.
class FirebaseMonitoring {
  FirebaseMonitoring._();

  static bool _ready = false;

  static Future<void> initialize() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final crashlytics = FirebaseCrashlytics.instance;
      final previousFlutterHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        previousFlutterHandler?.call(details);
        unawaited(
          crashlytics
              .recordFlutterFatalError(details)
              .catchError((Object _) {}),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          crashlytics
              .recordError(error, stack, fatal: true)
              .catchError((Object _) {}),
        );
        return true;
      };
      _ready = true;
    } catch (_) {
      debugPrint('FirebaseMonitoring: monitoring unavailable.');
    }
  }

  /// Aggregate request duration without exporting URLs, headers or mail data.
  static Future<T> traceApiRequest<T>(Future<T> Function() request) async {
    if (!_ready) return request();

    late final Trace trace;
    try {
      trace = FirebasePerformance.instance.newTrace('api_http');
      await trace.start();
    } catch (_) {
      return request();
    }

    try {
      return await request();
    } finally {
      try {
        await trace.stop();
      } catch (_) {
        // Telemetry failures must not replace API responses or exceptions.
      }
    }
  }
}
