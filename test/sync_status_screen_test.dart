import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/folder_sync_status.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/sync_status_screen.dart';

class _FakeRepo extends MailRepository {
  _FakeRepo(this.accounts);

  @override
  final List<MailAccount> accounts;

  final Map<String, List<FolderSyncStatus>> syncStatusByAccount = {};
  final Map<String, Object> syncStatusErrorByAccount = {};
  final Map<String, int> queuedMutationsByAccount = {};

  @override
  Future<List<FolderSyncStatus>> getSyncStatus(String accountId) async {
    final error = syncStatusErrorByAccount[accountId];
    if (error != null) throw error;
    return syncStatusByAccount[accountId] ?? const [];
  }

  @override
  Future<int> queuedOfflineMutationCount(String accountId) async =>
      queuedMutationsByAccount[accountId] ?? 0;

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

const _account = MailAccount(id: 'acc-1', email: 'a@example.com');

Future<void> _pumpScreen(WidgetTester tester, _FakeRepo repo) async {
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(const MaterialApp(home: SyncStatusScreen()));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets(
    'shows folder rows with backfill-complete and backfill-incomplete states distinguishable',
    (tester) async {
      final repo = _FakeRepo([_account]);
      repo.syncStatusByAccount['acc-1'] = [
        FolderSyncStatus(
          folderId: 'f-inbox',
          folderName: 'INBOX',
          folderType: 'Inbox',
          backfillComplete: true,
          lastSuccessfulSyncAt: DateTime(2026, 1, 1, 10, 30),
          consecutiveFailures: 0,
        ),
        FolderSyncStatus(
          folderId: 'f-archive',
          folderName: 'Archive',
          folderType: 'Archive',
          backfillComplete: false,
          lastSuccessfulSyncAt: DateTime(2026, 1, 1, 9),
          consecutiveFailures: 0,
        ),
      ];
      await _pumpScreen(tester, repo);

      expect(find.text('Gelen Kutusu'), findsOneWidget);
      expect(find.text('Arşiv'), findsOneWidget);
      expect(
        find.text('Geçmiş mailler hâlâ içeri aktarılıyor'),
        findsOneWidget,
      );

      final inboxIcon = tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(
            of: find.text('Gelen Kutusu'),
            matching: find.byType(Row),
          ),
          matching: find.byType(Icon),
        ),
      );
      final archiveIcon = tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(of: find.text('Arşiv'), matching: find.byType(Row)),
          matching: find.byType(Icon),
        ),
      );
      expect(inboxIcon.icon, isNot(equals(archiveIcon.icon)));
    },
  );

  testWidgets(
    'a per-account fetch failure shows a retry affordance without crashing',
    (tester) async {
      final repo = _FakeRepo([_account]);
      repo.syncStatusErrorByAccount['acc-1'] = Exception('boom');
      await _pumpScreen(tester, repo);

      expect(find.text('Tekrar dene'), findsOneWidget);
      expect(tester.takeException(), isNull);

      repo.syncStatusErrorByAccount.remove('acc-1');
      repo.syncStatusByAccount['acc-1'] = [
        FolderSyncStatus(
          folderId: 'f-inbox',
          folderName: 'INBOX',
          folderType: 'Inbox',
          backfillComplete: true,
          lastSuccessfulSyncAt: DateTime(2026, 1, 1),
          consecutiveFailures: 0,
        ),
      ];
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();

      expect(find.text('Gelen Kutusu'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsNothing);
    },
  );

  testWidgets('renders the queued offline mutation count when non-zero', (
    tester,
  ) async {
    final repo = _FakeRepo([_account]);
    repo.syncStatusByAccount['acc-1'] = [
      FolderSyncStatus(
        folderId: 'f-inbox',
        folderName: 'INBOX',
        folderType: 'Inbox',
        backfillComplete: true,
        lastSuccessfulSyncAt: DateTime(2026, 1, 1),
        consecutiveFailures: 0,
      ),
    ];
    repo.queuedMutationsByAccount['acc-1'] = 3;
    await _pumpScreen(tester, repo);

    expect(find.text('3 işlem bağlantı bekliyor'), findsOneWidget);
    expect(find.text('Hepsi senkronize'), findsNothing);
  });
}
