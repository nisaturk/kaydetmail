import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/main.dart' as app;
import 'package:kaydetmail/screens/login_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _firebaseInitializationChannel =
    'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore';
const _screenProtectionChannel = MethodChannel('kaydetmail/screen_protection');

void main() {
  testWidgets(
    'renders saved appearance and returns from background while Firebase waits',
    (tester) async {
      final firebaseReply = Completer<void>();
      final messenger = tester.binding.defaultBinaryMessenger;
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      AppSettingsController.resetForTest();
      AppConfig.resetForTest();
      SharedPreferences.setMockInitialValues({
        'kaydet.theme.mode': 'dark',
        'kaydet.language': 'en',
      });
      messenger.setMockMessageHandler(_firebaseInitializationChannel, (
        _,
      ) async {
        await firebaseReply.future;
        return const StandardMessageCodec().encodeMessage([
          'unavailable',
          'Firebase is unavailable in this startup scenario',
          null,
        ]);
      });
      messenger.setMockMethodCallHandler(
        _screenProtectionChannel,
        (_) async => null,
      );

      try {
        await tester.runAsync(() async {
          await SharedPreferences.getInstance();
          app.main();
          // Let pre-frame preference reads and runApp's root attachment finish
          // on the real event loop, without waiting for the held Firebase reply.
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();

        final login = find.byType(LoginScreen).hitTestable();
        expect(login, findsOneWidget);
        final context = tester.element(login);
        expect(Theme.of(context).brightness, Brightness.dark);
        expect(Localizations.localeOf(context).languageCode, 'en');

        expect(firebaseReply.isCompleted, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(login, findsOneWidget);
        expect(
          find.byKey(const Key('continue-button')).hitTestable(),
          findsOneWidget,
        );
      } finally {
        // Dispose the UI before draining optional initialization so a failing
        // assertion is not replaced by the auth gate spinner never settling.
        await tester.pumpWidget(const SizedBox.shrink());
        firebaseReply.complete();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        messenger.setMockMessageHandler(_firebaseInitializationChannel, null);
        messenger.setMockMethodCallHandler(_screenProtectionChannel, null);
        debugDefaultTargetPlatformOverride = previousPlatform;
        AppSettingsController.resetForTest();
        AppConfig.resetForTest();
      }
    },
  );
}
