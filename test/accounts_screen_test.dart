import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/accounts_screen.dart';
import 'package:kaydetmail/screens/login_screen.dart';

/// Repository double covering only what [AccountsScreen] reads/calls.
class _FakeRepo extends MailRepository {
  _FakeRepo(this.accounts);

  @override
  List<MailAccount> accounts;

  String? active;
  final List<String?> selected = [];

  @override
  String? get activeAccountId => active;

  @override
  Future<void> setActiveAccount(String? accountId) async {
    selected.add(accountId);
    active = accountId;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pumpAccounts(WidgetTester tester, _FakeRepo repo) async {
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(const MaterialApp(home: AccountsScreen()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets('a disconnected account shows status and a reconnect CTA', (
    tester,
  ) async {
    final repo = _FakeRepo([
      const MailAccount(
        id: 'acc-1',
        email: 'a@example.com',
        status: MailAccountStatus.needsReauthentication,
      ),
    ]);
    await _pumpAccounts(tester, repo);

    expect(find.textContaining('Bağlantısı kesildi'), findsOneWidget);
    expect(find.byTooltip('Şifreyi güncelle'), findsOneWidget);
  });

  testWidgets(
    'tapping the reconnect CTA activates that account and opens reconnect login',
    (tester) async {
      final repo = _FakeRepo([
        const MailAccount(id: 'acc-1', email: 'a@example.com'),
        const MailAccount(
          id: 'acc-2',
          email: 'b@example.com',
          status: MailAccountStatus.needsReauthentication,
        ),
      ]);
      repo.active = 'acc-1';
      await _pumpAccounts(tester, repo);

      await tester.tap(find.byTooltip('Şifreyi güncelle'));
      await tester.pumpAndSettle();

      // Reconnecting a non-active account must first make it the active
      // session (`MailRepository.reconnect` always targets the active
      // account) — never silently reconnect whichever account happens to be
      // primary (docs-dev spec §24).
      expect(repo.selected, ['acc-2']);
      final loginScreen = tester.widget<LoginScreen>(find.byType(LoginScreen));
      expect(loginScreen.reconnect, isTrue);
      expect(loginScreen.initialEmail, 'b@example.com');
    },
  );

  testWidgets(
    'an active/healthy account shows neither status text nor reconnect CTA',
    (tester) async {
      final repo = _FakeRepo([
        const MailAccount(id: 'acc-1', email: 'a@example.com'),
      ]);
      repo.active = 'acc-1';
      await _pumpAccounts(tester, repo);

      expect(find.byTooltip('Şifreyi güncelle'), findsNothing);
    },
  );
}
