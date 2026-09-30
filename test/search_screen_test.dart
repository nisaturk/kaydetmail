import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/folder_sync_status.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_custom_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/remote_search_result.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/search_screen.dart';

class _Call {
  _Call({
    required this.query,
    required this.accountId,
    required this.folder,
    required this.customFolderId,
    required this.isRead,
    required this.labelId,
    this.flagged,
    this.hasAttachment,
  });

  final String query;
  final String? accountId;
  final MailFolder? folder;
  final String? customFolderId;
  final bool? isRead;
  final String? labelId;
  final bool? flagged;
  final bool? hasAttachment;
}

class _FakeRepo extends MailRepository {
  _FakeRepo(this._accounts);

  final List<MailAccount> _accounts;
  final List<_Call> calls = [];
  List<Email> nextResult = const [];
  List<FolderSyncStatus> syncStatusForFirstAccount = const [];
  int remoteCalls = 0;
  String? remoteAccountId;
  List<RemoteSearchResult> remoteRounds = const [];

  @override
  List<Email> getAllEmails() => nextResult;

  @override
  List<Email> getThreadEmails(String threadId) =>
      nextResult.where((mail) => mail.threadId == threadId).toList();

  @override
  Future<RemoteSearchResult> searchRemote({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
  }) async {
    remoteCalls++;
    remoteAccountId = accountId;
    nextResult = [
      Email(
        id: 'remote-1',
        senderName: 'Sender',
        senderEmail: 'sender@example.com',
        recipients: const ['me@example.com'],
        subject: 'Sunucudan gelen',
        bodyText: '',
        timestamp: DateTime(2026),
        isRead: false,
        accountId: accountId ?? _accounts.first.id,
      ),
    ];
    if (remoteCalls <= remoteRounds.length) {
      return remoteRounds[remoteCalls - 1];
    }
    return const RemoteSearchResult(
      matched: 1,
      imported: 1,
      remaining: 0,
      complete: true,
    );
  }

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
    String? customFolderId,
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
        customFolderId: customFolderId,
        folder: folder,
        isRead: isRead,
        labelId: labelId,
        flagged: flagged,
        hasAttachment: hasAttachment,
      ),
    );
    return nextResult;
  }

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) => const [
    MailCustomFolder(
      accountId: 'a1',
      folderId: 'custom-1',
      name: 'Projeler',
      fullName: 'Projeler',
      isSyncEnabled: false,
    ),
  ];
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

  test(
    'cached search returns separate matching messages from the same thread',
    () {
      Email message(String id, String subject, List<String> labels, int day) =>
          Email(
            id: id,
            senderName: 'Sender',
            senderEmail: 'sender@example.com',
            recipients: const ['me@example.com'],
            subject: subject,
            bodyText: '',
            timestamp: DateTime(2026, 9, day),
            threadId: 'same-thread',
            labelIds: labels,
            isRead: true,
          );
      final repo = _FakeRepo(const [])
        ..nextResult = [
          message('older', 'Proje ilk ileti', ['project'], 20),
          message('newer', 'Proje yanıtı', ['project'], 21),
          message('unlabeled', 'Proje etiketsiz', [], 22),
          message('other-subject', 'Başka konu', ['project'], 23),
        ];

      expect(
        repo
            .searchEmails(query: 'Proje', labelId: 'project')
            .map((mail) => mail.id),
        ['newer', 'older'],
      );
    },
  );

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

  testWidgets('custom folder search sends its raw folderId', (tester) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);

    await tester.tap(find.byTooltip('Filtreler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projeler'));
    await tester.ensureVisible(find.text('Uygula'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();

    expect(repo.calls.single.accountId, 'a1');
    expect(repo.calls.single.customFolderId, 'custom-1');
    expect(repo.calls.single.folder, isNull);
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

  testWidgets('attachment filter stays local-only', (tester) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);
    await tester.enterText(find.byType(TextField).first, 'rapor');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filtreler'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ek var'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ek var'));
    await tester.ensureVisible(find.text('Uygula'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();

    expect(repo.calls.last.hasAttachment, isTrue);
    expect(repo.calls.last.query, 'rapor');
    expect(find.byKey(const Key('search-remote')), findsNothing);
    expect(repo.remoteCalls, 0);
  });

  testWidgets('remote search imports results then reruns cached search', (
    tester,
  ) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);
    await tester.enterText(find.byType(TextField).first, 'sunucu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(1));

    await tester.tap(find.byKey(const Key('search-remote')));
    await tester.pumpAndSettle();

    expect(repo.remoteCalls, 1);
    expect(repo.calls, hasLength(2));
    expect(find.text('Sunucudan gelen'), findsOneWidget);
    expect(find.textContaining('1 yeni e-posta eklendi'), findsOneWidget);
  });

  testWidgets(
    'partial remote scan continues automatically and stops when it stalls',
    (tester) async {
      final repo =
          _FakeRepo(const [MailAccount(id: 'a1', email: 'a@example.com')])
            ..remoteRounds = const [
              RemoteSearchResult(
                matched: 30,
                imported: 10,
                remaining: 20,
                complete: false,
              ),
              RemoteSearchResult(
                matched: 30,
                imported: 10,
                remaining: 10,
                complete: false,
              ),
              RemoteSearchResult(
                matched: 30,
                imported: 0,
                remaining: 10,
                complete: false,
              ),
            ];
      await _pumpSearch(tester, repo);
      await tester.enterText(find.byType(TextField).first, 'sunucu');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-remote')));
      await tester.pumpAndSettle();

      expect(repo.remoteCalls, 3);
      expect(
        find.textContaining('20 yeni e-posta eklendi; 10 eşleşme alınamadı'),
        findsOneWidget,
      );
    },
  );

  testWidgets('partial remote scan continues until complete', (tester) async {
    final repo =
        _FakeRepo(const [MailAccount(id: 'a1', email: 'a@example.com')])
          ..remoteRounds = const [
            RemoteSearchResult(
              matched: 15,
              imported: 10,
              remaining: 5,
              complete: false,
            ),
            RemoteSearchResult(
              matched: 15,
              imported: 5,
              remaining: 0,
              complete: true,
            ),
          ];
    await _pumpSearch(tester, repo);
    await tester.enterText(find.byType(TextField).first, 'sunucu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-remote')));
    await tester.pumpAndSettle();

    expect(repo.remoteCalls, 2);
    expect(
      find.text('Sunucu taraması tamamlandı. 15 yeni e-posta eklendi.'),
      findsOneWidget,
    );
  });

  testWidgets('label-only search cannot trigger remote import', (tester) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
    ]);
    await _pumpSearch(tester, repo);
    await tester.tap(find.text('Fatura'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-remote')), findsNothing);
  });

  testWidgets('remote search keeps the selected account scope', (tester) async {
    final repo = _FakeRepo(const [
      MailAccount(id: 'a1', email: 'a@example.com'),
      MailAccount(id: 'a2', email: 'b@example.com'),
    ]);
    await _pumpSearch(tester, repo);
    await tester.enterText(find.byType(TextField).first, 'sunucu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtreler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b@example.com'));
    await tester.ensureVisible(find.text('Uygula'));
    await tester.tap(find.text('Uygula'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-remote')));
    await tester.pumpAndSettle();
    expect(repo.remoteAccountId, 'a2');
  });
}
