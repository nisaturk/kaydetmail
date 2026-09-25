import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/folder_sync_status.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/search_screen.dart';

class _Call {
  _Call({
    required this.query,
    required this.accountId,
    required this.folder,
    required this.isRead,
    required this.labelId,
  });

  final String query;
  final String? accountId;
  final MailFolder? folder;
  final bool? isRead;
  final String? labelId;
}

class _FakeRepo extends MailRepository {
  _FakeRepo(this._accounts);

  final List<MailAccount> _accounts;
  final List<_Call> calls = [];
  List<Email> nextResult = const [];
  List<FolderSyncStatus> syncStatusForFirstAccount = const [];

  @override
  List<MailAccount> get accounts => _accounts;

  @override
  List<MailLabel> getLabels() => const [
    MailLabel(id: 'lbl-1', name: 'Fatura', color: Colors.blue),
  ];

  @override
  List<MailLabel> getLabelsForAccount(String accountId) => const [];

  @override
  Future<List<Email>> searchEmailsOnServer({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    int page = 1,
    int pageSize = 20,
  }) async {
    calls.add(
      _Call(
        query: query,
        accountId: accountId,
        folder: folder,
        isRead: isRead,
        labelId: labelId,
      ),
    );
    return nextResult;
  }

  @override
  Future<List<FolderSyncStatus>> getSyncStatus(String accountId) async =>
      accountId == _accounts.first.id ? syncStatusForFirstAccount : const [];

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pumpSearch(WidgetTester tester, _FakeRepo repo) async {
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppConfig.resetForTest();
  });

  testWidgets('typing a query triggers a debounced server search', (
    tester,
  ) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'fatura');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.query, 'fatura');
  });

  testWidgets('selecting a label runs a server search with labelId', (
    tester,
  ) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);

    await tester.tap(find.text('Fatura'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.labelId, 'lbl-1');
    expect(repo.calls.single.query, '');
  });

  testWidgets(
    'advanced filter sheet applies isRead and shows a removable chip',
    (tester) async {
      final repo = _FakeRepo(const [
        MailAccount(id: 'a1', email: 'a@example.com'),
      ]);
      await _pumpSearch(tester, repo);

      await tester.tap(find.byTooltip('Filtreler'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Okundu'));
      await tester.ensureVisible(find.text('Uygula'));
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.isRead, isTrue);
      expect(find.text('Okundu'), findsOneWidget);

      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'Okundu'))
          .onDeleted!();
      await tester.pumpAndSettle();

      expect(repo.calls, hasLength(1));
      expect(find.text('Okundu'), findsNothing);
      expect(find.text('Aramak için yazmaya başlayın.'), findsOneWidget);
    },
  );

  testWidgets('account filter narrows the search to one connected account', (
    tester,
  ) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
      MailAccount(id: 'a2', email: 'b@example.com'),
    ]);
    await _pumpSearch(tester, repo);

    await tester.tap(find.byTooltip('Filtreler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b@example.com'));
    await tester.ensureVisible(find.text('Uygula'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();

    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.accountId, 'a2');
    expect(find.textContaining('b@example.com'), findsWidgets);
  });

  testWidgets('an incomplete backfill shows the completeness banner', (
    tester,
  ) async {
    final repo =
        _FakeRepo(const [MailAccount(id: 'a1', email: 'a@example.com')])
          ..syncStatusForFirstAccount = const [
            FolderSyncStatus(
              folderId: 'f1',
              folderName: 'INBOX',
              folderType: 'Inbox',
              backfillComplete: false,
              consecutiveFailures: 0,
            ),
          ];
    await _pumpSearch(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'x');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Posta kutusu hâlâ senkronize ediliyor'),
      findsOneWidget,
    );
  });
}
