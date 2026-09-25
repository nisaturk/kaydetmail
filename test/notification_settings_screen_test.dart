import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/account_notification_settings.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/notification_settings_screen.dart';
import 'package:kaydetmail/services/api_exception.dart';

class _FakeRepo extends MailRepository {
  _FakeRepo(this.accounts, this.stored);

  @override
  final List<MailAccount> accounts;

  final Map<String, AccountNotificationSettings> stored;
  final updates = <(String, AccountNotificationSettings)>[];
  bool failUpdates = false;

  @override
  Future<AccountNotificationSettings> getNotificationSettings(
    String accountId,
  ) async => stored[accountId]!;

  @override
  Future<AccountNotificationSettings> updateNotificationSettings(
    String accountId,
    AccountNotificationSettings settings,
  ) async {
    updates.add((accountId, settings));
    if (failUpdates) throw const ApiException(status: 503);
    return stored[accountId] = settings;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _first = MailAccount(id: 'acc-1', email: 'first@example.com');
const _second = MailAccount(id: 'acc-2', email: 'second@example.com');
const _limited = AccountNotificationSettings(
  enabled: true,
  inboxOnly: true,
  privacy: NotificationPrivacy.limited,
);

Future<void> _pump(WidgetTester tester, _FakeRepo repo) async {
  tester.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(
    const MaterialApp(home: NotificationSettingsScreen()),
  );
  await tester.pumpAndSettle();
}

bool _checked(WidgetTester tester, String accountId, String privacy) =>
    tester
        .widget<ListTile>(
          find.byKey(Key('notification-privacy-$accountId-$privacy')),
        )
        .trailing !=
    null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets('each account keeps its own privacy and folder settings', (
    tester,
  ) async {
    final repo = _FakeRepo(
      [_first, _second],
      {'acc-1': _limited, 'acc-2': _limited},
    );
    await _pump(tester, repo);

    await tester.tap(
      find.byKey(const Key('notification-privacy-acc-2-Private')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('notification-inbox-only-acc-1')),
    );
    await tester.tap(find.byKey(const Key('notification-inbox-only-acc-1')));
    await tester.pumpAndSettle();

    expect(repo.stored['acc-1']!.privacy, NotificationPrivacy.limited);
    expect(repo.stored['acc-1']!.inboxOnly, isFalse);
    expect(repo.stored['acc-2']!.privacy, NotificationPrivacy.private);
    expect(repo.stored['acc-2']!.inboxOnly, isTrue);
    expect(_checked(tester, 'acc-2', 'Private'), isTrue);
    expect(_checked(tester, 'acc-2', 'Limited'), isFalse);
  });

  testWidgets('a failed save keeps the previous choice and reports it', (
    tester,
  ) async {
    final repo = _FakeRepo([_first], {'acc-1': _limited})..failUpdates = true;
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('notification-privacy-acc-1-Full')));
    await tester.pumpAndSettle();

    expect(repo.updates.single.$2.privacy, NotificationPrivacy.full);
    expect(_checked(tester, 'acc-1', 'Limited'), isTrue);
    expect(_checked(tester, 'acc-1', 'Full'), isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'disabled account notifications lock the dependent options, and a server preview ban is explained',
    (tester) async {
      final repo = _FakeRepo(
        [_first],
        {
          'acc-1': const AccountNotificationSettings(
            enabled: false,
            inboxOnly: true,
            privacy: NotificationPrivacy.full,
            previewsAllowedByServer: false,
          ),
        },
      );
      await _pump(tester, repo);

      await tester.tap(
        find.byKey(const Key('notification-privacy-acc-1-Private')),
      );
      await tester.pumpAndSettle();

      expect(repo.updates, isEmpty);
      expect(
        find.textContaining('Sunucu önizlemeleri kapattığı'),
        findsOneWidget,
      );
    },
  );
}
