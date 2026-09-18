import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/server_address_store.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });

  group('ServerAddressStore', () {
    test('default is the local development address', () {
      expect(ServerAddressStore.defaultBaseUrl, 'http://localhost:8080');
    });

    test('load returns the default when nothing is saved', () async {
      expect(
        await ServerAddressStore.load(),
        ServerAddressStore.defaultBaseUrl,
      );
    });

    test('save then load round-trips', () async {
      await ServerAddressStore.save('http://mail.example.com');
      expect(await ServerAddressStore.load(), 'http://mail.example.com');
    });

    test('normalize trims and strips trailing slashes', () {
      expect(
        ServerAddressStore.normalize('  https://mail.example.com///  '),
        'https://mail.example.com',
      );
    });

    test('empty addresses are rejected', () {
      expect(() => ServerAddressStore.normalize(''), throwsArgumentError);
      expect(() => ServerAddressStore.normalize('   '), throwsArgumentError);
    });

    test('non-http(s) and relative addresses are rejected', () {
      expect(
        () => ServerAddressStore.normalize('ftp://mail.example.com'),
        throwsArgumentError,
      );
      expect(
        () => ServerAddressStore.normalize('mail.example.com'),
        throwsArgumentError,
      );
      expect(
        () => ServerAddressStore.normalize('/just/a/path'),
        throwsArgumentError,
      );
    });
  });

  group('AppSettingsController', () {
    test('defaults: notifications on, manual sync, swipe on', () {
      final settings = AppSettingsController.instance;
      expect(settings.notificationsEnabled, isTrue);
      expect(settings.syncInterval, SyncInterval.manual);
      expect(settings.swipeDeleteEnabled, isTrue);
      expect(settings.serverBaseUrl, ServerAddressStore.defaultBaseUrl);
    });

    test('setServerAddress persists the normalized value', () async {
      final settings = AppSettingsController.instance;
      final result = await settings.setServerAddress(
        'https://mail.example.com/',
      );
      expect(result, 'https://mail.example.com');
      expect(settings.serverBaseUrl, 'https://mail.example.com');
      // Persisted: a fresh controller read goes through the store.
      expect(await ServerAddressStore.load(), 'https://mail.example.com');
    });

    test('loadServerAddress picks up a previously saved value', () async {
      await ServerAddressStore.save('http://10.0.0.5:9000');
      AppSettingsController.resetForTest(); // back to default
      expect(
        AppSettingsController.instance.serverBaseUrl,
        ServerAddressStore.defaultBaseUrl,
      );
      await AppSettingsController.instance.loadServerAddress();
      expect(
        AppSettingsController.instance.serverBaseUrl,
        'http://10.0.0.5:9000',
      );
    });

    test('swipe toggle notifies listeners', () {
      final settings = AppSettingsController.instance;
      var notified = 0;
      settings.addListener(() => notified++);
      settings.swipeDeleteEnabled = false;
      settings.swipeDeleteEnabled = false; // no-op, same value
      expect(notified, 1);
      expect(settings.swipeDeleteEnabled, isFalse);
    });
  });
}
