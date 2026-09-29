import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/settings_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends MailRepository {
  @override
  Future<List<MailSession>> getSessions() async => const [];

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _channel = MethodChannel('kaydetmail/screen_protection');
const _prefKey = 'kaydet.security.screenProtectionEnabled';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Object?> nativeCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
    nativeCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          nativeCalls.add((call.method, (call.arguments as Map)['enabled']));
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    AppConfig.resetForTest();
  });

  test('is off by default', () {
    expect(AppSettingsController.instance.screenProtectionEnabled, isFalse);
  });

  test('toggling applies it natively and persists the choice', () async {
    AppSettingsController.instance.screenProtectionEnabled = true;
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls.last, ('setEnabled', true));
    expect((await SharedPreferences.getInstance()).getBool(_prefKey), isTrue);

    AppSettingsController.instance.screenProtectionEnabled = false;
    await Future<void>.delayed(Duration.zero);

    expect(nativeCalls.last, ('setEnabled', false));
    expect((await SharedPreferences.getInstance()).getBool(_prefKey), isFalse);
  });

  test('startup load restores the saved choice and re-applies it', () async {
    SharedPreferences.setMockInitialValues({_prefKey: true});

    await AppSettingsController.instance.loadScreenProtection();

    expect(AppSettingsController.instance.screenProtectionEnabled, isTrue);
    expect(nativeCalls.last, ('setEnabled', true));
  });

  test('a missing native side is ignored', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);

    await expectLater(
      AppSettingsController.instance.loadScreenProtection(),
      completes,
    );
    AppSettingsController.instance.screenProtectionEnabled = true;
    await Future<void>.delayed(Duration.zero);
    expect(AppSettingsController.instance.screenProtectionEnabled, isTrue);
  });

  testWidgets('privacy settings expose the switch and it flips the setting', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppConfig.mailRepositoryForTest = _FakeRepo();

    await tester.pumpWidget(const MaterialApp(home: GeneralSettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gizlilik'));
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const ValueKey('screen-protection-switch'));
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(AppSettingsController.instance.screenProtectionEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    expect(nativeCalls.last, ('setEnabled', true));
  });
}
