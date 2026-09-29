import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/demo_mail_repository.dart';

class _Repo extends DemoMailRepository {
  final contactAdds = <String?>[];
  final sessionQueries = <String?>[];
  final revokes = <(String, String?)>[];
  final signedOut = <String>[];
  final removed = <String>[];

  @override
  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
    String? accountId,
  }) async {
    contactAdds.add(accountId);
    return ManualContact(
      id: 'c',
      accountId: accountId ?? 'acc-1',
      email: email,
      displayName: displayName,
    );
  }

  @override
  Future<List<MailSession>> getSessions({String? accountId}) {
    sessionQueries.add(accountId);
    return super.getSessions(accountId: accountId);
  }

  @override
  Future<void> revokeSession(String sessionId, {String? accountId}) async =>
      revokes.add((sessionId, accountId));

  @override
  Future<void> signOutAccount(String accountId) async =>
      signedOut.add(accountId);

  @override
  Future<void> removeAccount(String accountId) async => removed.add(accountId);
}

Future<_Repo> _pump(WidgetTester tester, Widget home) async {
  tester.view
    ..physicalSize = const Size(800, 3000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
  });

  testWidgets('the index lists general settings and one entry per account', (
    tester,
  ) async {
    await _pump(tester, const SettingsScreen());

    expect(find.text('Genel ayarlar'), findsOneWidget);
    for (final id in ['acc-1', 'acc-2', 'acc-3']) {
      expect(find.byKey(ValueKey('settings-account-$id')), findsOneWidget);
    }
    expect(
      find.text('Bağlantısı kesildi — şifreyi güncelleyin'),
      findsOneWidget,
    );
    expect(find.text('Hesap ekle'), findsOneWidget);
  });

  testWidgets('general settings hold no account-owned items', (tester) async {
    await _pump(tester, const GeneralSettingsScreen());

    for (final accountOwned in [
      'Kişiler',
      'Bağlı cihazlar',
      'Klasörler',
      'İmzalar',
    ]) {
      expect(find.text(accountOwned), findsNothing);
    }
    // Their old entry points inside the general pages are gone too.
    await tester.tap(find.text('Bildirimler'));
    await tester.pumpAndSettle();
    expect(find.text('Hesap bildirimleri'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ağ'));
    // The server health probe keeps a spinner running, so never settle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Senkronizasyon durumu'), findsNothing);
  });

  testWidgets('the account page groups every mailbox-owned setting', (
    tester,
  ) async {
    await _pump(tester, const AccountSettingsScreen(accountId: 'acc-2'));

    for (final entry in [
      'İmzalar',
      'Hazır metinler',
      'Etiketler',
      'Kişiler',
      'Klasörler',
      'Eşitleme',
      'Bildirimler',
      'Kayıtlı görsel tercihleri',
      'Bağlı cihazlar',
    ]) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
    expect(find.byKey(const Key('reconnect-account')), findsNothing);
  });

  testWidgets('a disconnected account offers the password update', (
    tester,
  ) async {
    await _pump(tester, const AccountSettingsScreen(accountId: 'acc-3'));

    expect(find.byKey(const Key('account-status')), findsOneWidget);
    expect(find.byKey(const Key('reconnect-account')), findsOneWidget);
  });

  testWidgets('a contact added from an account page goes to that account', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      const AccountSettingsScreen(accountId: 'acc-2'),
    );

    await tester.tap(find.text('Kişiler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni Kişi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'friend@example.com');
    await tester.tap(find.text('Ekle'));
    await tester.pumpAndSettle();

    expect(repo.contactAdds, ['acc-2']);
  });

  testWidgets('signed-in devices are loaded and revoked per account', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      const AccountSettingsScreen(accountId: 'acc-2'),
    );

    await tester.tap(find.text('Bağlı cihazlar'));
    await tester.pumpAndSettle();
    expect(repo.sessionQueries, ['acc-2']);

    await tester.tap(find.text('Kapat').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kapat').last);
    await tester.pumpAndSettle();
    expect(repo.revokes.single.$2, 'acc-2');
  });

  testWidgets('sign out and removal ask first and target only this account', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      const AccountSettingsScreen(accountId: 'acc-2'),
    );

    await tester.ensureVisible(find.byKey(const Key('sign-out-account')));
    await tester.tap(find.byKey(const Key('sign-out-account')));
    await tester.pumpAndSettle();
    expect(repo.signedOut, isEmpty);
    await tester.tap(find.text('Çıkış yap').last);
    await tester.pumpAndSettle();
    expect(repo.signedOut, ['acc-2']);

    await tester.ensureVisible(find.byKey(const Key('remove-account')));
    await tester.tap(find.byKey(const Key('remove-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaldır').last);
    await tester.pumpAndSettle();
    expect(repo.removed, ['acc-2']);
  });
}
