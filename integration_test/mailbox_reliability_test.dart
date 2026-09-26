import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/main.dart' as app;
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/token_store.dart';

const _email = String.fromEnvironment('KAYDET_IT_EMAIL');
const _password = String.fromEnvironment('KAYDET_IT_PASSWORD');
const _email2 = String.fromEnvironment('KAYDET_IT_EMAIL_2');
const _password2 = String.fromEnvironment('KAYDET_IT_PASSWORD_2');

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(minutes: 2),
  Future<void> Function()? between,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout');
    }
    await between?.call();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Future<void> _sendFromSecondAccount(String subject) async {
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  final client = ApiClient(tokenStore: tokenStore);
  final auth = ApiAuthService(
    client: client,
    tokenStore: tokenStore,
    deviceIdentifierProvider: const MemoryDeviceIdentifierProvider(
      'integration-sender',
    ),
  );
  final discovery = await auth.discover(_email2);
  await auth.connect(discoveryId: discovery.discoveryId, password: _password2);
  await ApiMailService(client).sendMail(
    to: const [_email],
    subject: subject,
    bodyText: 'KaydetMail background reliability check',
    idempotencyKey: 'it-${DateTime.now().microsecondsSinceEpoch}',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final configured = _email.isNotEmpty && _password.isNotEmpty;
  final twoAccounts = configured && _email2.isNotEmpty && _password2.isNotEmpty;

  testWidgets(
    'foreground login, background catch-up and a second account',
    (tester) async {
      app.main();
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('email-field')).evaluate().isNotEmpty,
      );

      await tester.enterText(find.byKey(const Key('email-field')), _email);
      await tester.tap(find.byKey(const Key('continue-button')));
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('password-field')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('password-field')),
        _password,
      );
      await tester.tap(find.byKey(const Key('signin-button')));
      final repo = AppConfig.mailRepository;
      await _pumpUntil(
        tester,
        () =>
            repo.isLoggedIn &&
            repo.accounts.isNotEmpty &&
            find.text('Gelen Kutusu').evaluate().isNotEmpty,
      );

      if (!twoAccounts) return;

      final subject =
          'KaydetMail IT ${DateTime.now().toUtc().toIso8601String()}';
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _sendFromSecondAccount(subject);
      await tester.pump(const Duration(seconds: 5));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await _pumpUntil(
        tester,
        () => repo
            .getEmailsInFolder(MailFolder.inbox)
            .any((mail) => mail.subject == subject),
        timeout: const Duration(minutes: 3),
        between: () async {
          try {
            await repo.syncFolder(MailFolder.inbox);
            await repo.refreshEmails(MailFolder.inbox);
          } catch (_) {}
          await Future<void>.delayed(const Duration(seconds: 5));
        },
      );

      await repo.connectAccount(email: _email2, password: _password2);
      await tester.pumpAndSettle();
      expect(repo.accounts.map((a) => a.email.toLowerCase()), [
        _email.toLowerCase(),
        _email2.toLowerCase(),
      ]);
      expect(repo.activeAccountId, isNull);
    },
    skip: !configured,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
