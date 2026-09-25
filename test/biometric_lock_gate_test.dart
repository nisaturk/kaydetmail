import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/widgets/biometric_lock_gate.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';

/// Fake platform implementation driving [BiometricLockGate] without a real
/// device — mirrors how `local_auth`'s own test suite stubs
/// [LocalAuthPlatform.instance].
class _FakeLocalAuthPlatform extends LocalAuthPlatform {
  bool deviceSupported = true;
  bool authenticateResult = true;
  Object? authenticateError;
  int authenticateCalls = 0;

  @override
  Future<bool> deviceSupportsBiometrics() async => deviceSupported;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    authenticateCalls++;
    if (authenticateError != null) throw authenticateError!;
    return authenticateResult;
  }
}

void main() {
  late _FakeLocalAuthPlatform fake;

  setUp(() {
    fake = _FakeLocalAuthPlatform();
    LocalAuthPlatform.instance = fake;
    AppSettingsController.resetForTest();
  });

  Widget harness() => MaterialApp(
    home: const BiometricLockGate(child: Text('Gizli Posta Kutusu')),
  );

  testWidgets('passthrough renders child directly when the lock is off', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
    expect(fake.authenticateCalls, 0);
  });

  testWidgets('locks on start and unlocks after a successful authenticate', (
    tester,
  ) async {
    AppSettingsController.instance.biometricLockEnabled = true;
    fake.authenticateResult = true;

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
    expect(fake.authenticateCalls, 1);
  });

  testWidgets('stays locked and offers a retry when authenticate fails', (
    tester,
  ) async {
    AppSettingsController.instance.biometricLockEnabled = true;
    fake.authenticateResult = false;

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsNothing);
    expect(find.text('Kilidi Aç'), findsOneWidget);

    fake.authenticateResult = true;
    await tester.tap(find.text('Kilidi Aç'));
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
  });

  testWidgets('degrades gracefully when the device has no credentials set', (
    tester,
  ) async {
    AppSettingsController.instance.biometricLockEnabled = true;
    fake.deviceSupported = false;

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsNothing);
    expect(find.text('Yine de devam et'), findsOneWidget);
    // No credentials at all to try against — never calls into the plugin.
    expect(fake.authenticateCalls, 0);

    await tester.tap(find.text('Yine de devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
  });

  testWidgets('re-locks on resume after being backgrounded', (tester) async {
    AppSettingsController.instance.biometricLockEnabled = true;
    fake.authenticateResult = true;

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
    expect(fake.authenticateCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Gizli Posta Kutusu'), findsOneWidget);
    expect(fake.authenticateCalls, 2);
  });

  testWidgets(
    're-locks on resume even when only inactive (no paused) was seen',
    (tester) async {
      AppSettingsController.instance.biometricLockEnabled = true;
      fake.authenticateResult = true;

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(fake.authenticateCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // `inactive` alone (without ever reaching `paused`) still counts as
      // having left the foreground, per the re-lock contract.
      expect(fake.authenticateCalls, 2);
    },
  );
}
