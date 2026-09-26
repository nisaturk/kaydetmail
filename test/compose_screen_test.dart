import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/compose_screen.dart';
import 'package:kaydetmail/screens/outbox_screen.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:kaydetmail/utils/markdown_lite_to_html.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal in-memory [MailRepository] double. Every method not exercised by
/// compose is a harmless no-op/empty-collection stub — compose only ever
/// reads [accounts]/[currentUser]/[getAllEmails] and calls
/// [sendEmail]/[saveDraft]/[deleteDraft]/[scheduleSend].
class _FakeMailRepository extends MailRepository {
  _FakeMailRepository({required this.accounts, List<Email>? emails})
    : currentUser = '',
      _emails = emails ?? const [];

  @override
  final List<MailAccount> accounts;

  @override
  final String currentUser;

  final List<Email> _emails;

  final List<Email> sent = [];
  final List<ScheduledSend> scheduled = [];
  final List<String> deletedDrafts = [];
  final List<Email> savedDrafts = [];

  @override
  bool get isLoggedIn => true;

  @override
  String? get activeAccountId => null;

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async => true;

  @override
  Future<void> logout() async {}

  @override
  Future<void> reconnect({required String password}) async {}

  @override
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async {}

  @override
  Future<void> unregisterDevice() async {}

  @override
  Future<void> setActiveAccount(String? accountId) async {}

  @override
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async => throw UnimplementedError();

  @override
  Future<void> removeAccount(String accountId) async {}

  @override
  MailAccount? getAccount(String accountId) {
    for (final account in accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  @override
  Future<void> restoreSession(String email) async {}

  @override
  Future<List<MailSession>> getSessions() async => const [];

  @override
  Future<void> revokeSession(String sessionId) async {}

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      _emails.where((e) => e.folder == folder).toList();

  @override
  List<Email> getAllEmails() => List.unmodifiable(_emails);

  @override
  List<Email> getScopedEmails() => List.unmodifiable(_emails);

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async => const [];

  @override
  bool hasMoreEmails(MailFolder folder) => false;

  @override
  Future<void> refreshEmails(MailFolder folder) async {}

  @override
  Future<void> syncFolder(MailFolder folder) async {}

  @override
  Future<Email?> getEmail(String id) async {
    for (final email in _emails) {
      if (email.id == id) return email;
    }
    return null;
  }

  /// Lets attachment-readiness tests control success/failure/latency
  /// without a real network. Defaults to succeeding immediately.
  Future<Uint8List> Function(String mailId, Attachment attachment)?
  downloadAttachmentImpl;

  @override
  Future<Uint8List> downloadAttachment(String mailId, Attachment attachment) =>
      (downloadAttachmentImpl ?? (_, _) async => Uint8List(0))(
        mailId,
        attachment,
      );

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async => const [];

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
    bool requestReadReceipt = false,
    bool requestDeliveryReceipt = false,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final email = Email(
      id: 'sent-${sent.length}',
      senderName: from ?? '',
      senderEmail: from ?? '',
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      folder: MailFolder.sent,
      accountId: fromAccountId ?? '',
      attachments: attachments,
    );
    sent.add(email);
    return email;
  }

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
    String? draftId,
  }) async {
    final email = Email(
      id: draftId ?? 'draft-${savedDrafts.length}',
      senderName: from ?? '',
      senderEmail: from ?? '',
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      folder: MailFolder.drafts,
      accountId: fromAccountId ?? '',
    );
    savedDrafts.add(email);
    return email;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    deletedDrafts.add(draftId);
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {}

  @override
  Future<void> deletePermanently(List<String> ids) async {}

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {}

  @override
  Future<void> markAsRead(List<String> ids) async {}

  @override
  Future<void> markAsUnread(List<String> ids) async {}

  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {}

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {}

  @override
  Future<void> markAsReplied(List<String> ids) async {}

  @override
  Future<void> markAsForwarded(List<String> ids) async {}

  @override
  List<MailLabel> getLabels() => const [];

  @override
  List<MailLabel> getLabelsForAccount(String accountId) => const [];

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
  }) async => throw UnimplementedError();

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {}

  @override
  Future<void> deleteLabel(String labelId) async {}

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {}

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {}

  @override
  List<ManualContact> getManualContacts() => const [];

  @override
  List<ManualContact> getManualContactsForAccount(String accountId) => const [];

  @override
  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
  }) async => throw UnimplementedError();

  @override
  Future<void> updateManualContact({
    required String id,
    required String email,
    String? displayName,
  }) async {}

  @override
  Future<void> deleteManualContact(String id) async {}

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
  }) async => const [];

  @override
  Future<void> setSnoozed(List<String> ids, DateTime? until) async {}

  @override
  Future<ScheduledSend> scheduleSend({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? inReplyToId,
    String? identityId,
    required DateTime sendAt,
  }) async {
    final result = ScheduledSend(
      id: 'sched-${scheduled.length}',
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      sendAt: sendAt,
      status: ScheduledSendStatus.pending,
      createdAt: DateTime.now(),
    );
    scheduled.add(result);
    return result;
  }

  @override
  Future<void> cancelScheduledSend(String id) async {}
}

const _accountA = MailAccount(id: 'acc-a', email: 'a@example.com');
const _accountB = MailAccount(id: 'acc-b', email: 'b@example.com');

Future<void> _pumpCompose(
  WidgetTester tester, {
  required _FakeMailRepository repo,
  String? initialFrom,
  String? initialTo,
  String? editingDraftId,
  String? initialBody,
  List<Attachment> initialAttachments = const [],
  String? attachmentSourceMailId,
  bool settle = true,
}) async {
  AppConfig.mailRepositoryForTest = repo;
  // ComposeScreen must be pushed on top of a real base route: it calls
  // `Navigator.of(context).pop(...)` on send/schedule/close, which is a
  // no-op when compose is itself the only (home) route — exactly like the
  // real app, where it's always pushed from HomeScreen.
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox.shrink(key: const Key('home-placeholder'))),
    ),
  );
  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(
    MaterialPageRoute(
      builder: (_) => ComposeScreen(
        initialFrom: initialFrom,
        initialTo: initialTo ?? '',
        editingDraftId: editingDraftId,
        initialBody: initialBody ?? '',
        initialAttachments: initialAttachments,
        attachmentSourceMailId: attachmentSourceMailId,
      ),
    ),
  );
  // A still-downloading attachment keeps a CircularProgressIndicator
  // animating forever, which would make `pumpAndSettle` time out — callers
  // exercising that state pass `settle: false` and pump past the route's
  // push transition manually instead (a single zero-duration `pump()`
  // isn't enough for the pushed route to become hit-testable).
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
    PendingSendQueue.instance.useStoreForTest(OutboxStore.inMemory());
  });

  group('compose exit behavior', () {
    testWidgets('new mail offers save as draft or discard', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      await tester.enterText(
        find.byKey(const Key('body-field')),
        'keep this draft',
      );
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Taslağı kaydedilsin mi?'), findsOneWidget);
      expect(find.text('Taslağı Sil'), findsOneWidget);
      expect(find.text('Taslağı Kaydet'), findsOneWidget);
      await tester.tap(find.text('Taslağı Kaydet'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts.single.bodyText, 'keep this draft');
    });

    testWidgets('discarding a new mail exits without saving it', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      await tester.enterText(
        find.byKey(const Key('body-field')),
        'discard this draft',
      );
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taslağı Sil'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, isEmpty);
    });

    testWidgets('leaving an existing draft saves without asking', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialBody: 'updated draft',
        editingDraftId: 'draft-existing',
      );

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Taslağı kaydedilsin mi?'), findsNothing);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts.single.id, 'draft-existing');
      expect(repo.savedDrafts.single.bodyText, 'updated draft');
    });
  });

  tearDown(() {
    PendingSendQueue.instance.cancelAll();
    AppConfig.resetForTest();
  });

  group('signature auto-insert', () {
    testWidgets('is appended to the body of a brand-new mail', (tester) async {
      const account = MailAccount(
        id: 'acc-a',
        email: 'a@example.com',
        signature: 'Saygılarımla,\nA',
      );
      final repo = _FakeMailRepository(accounts: const [account]);

      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      final bodyText = tester
          .widget<TextField>(find.byKey(const Key('body-field')))
          .controller!
          .text;
      expect(bodyText, '\n\n--\nSaygılarımla,\nA');
    });

    testWidgets('is never inserted while editing an existing draft', (
      tester,
    ) async {
      const account = MailAccount(
        id: 'acc-a',
        email: 'a@example.com',
        signature: 'Saygılarımla,\nA',
      );
      final repo = _FakeMailRepository(accounts: const [account]);

      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        editingDraftId: 'draft-1',
        initialBody: 'orijinal taslak metni',
      );

      final bodyText = tester
          .widget<TextField>(find.byKey(const Key('body-field')))
          .controller!
          .text;
      expect(bodyText, 'orijinal taslak metni');
    });

    testWidgets('re-applies for the newly selected Kimden account', (
      tester,
    ) async {
      const accountA = MailAccount(
        id: 'acc-a',
        email: 'a@example.com',
        signature: 'İmza A',
      );
      const accountB = MailAccount(
        id: 'acc-b',
        email: 'b@example.com',
        signature: 'İmza B',
      );
      final repo = _FakeMailRepository(accounts: const [accountA, accountB]);

      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        '\n\n--\nİmza A',
      );

      await tester.tap(find.byKey(const Key('from-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b@example.com').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        '\n\n--\nİmza B',
      );
    });

    testWidgets('never clobbers body text the user already typed', (
      tester,
    ) async {
      const accountA = MailAccount(
        id: 'acc-a',
        email: 'a@example.com',
        signature: 'İmza A',
      );
      const accountB = MailAccount(
        id: 'acc-b',
        email: 'b@example.com',
        signature: 'İmza B',
      );
      final repo = _FakeMailRepository(accounts: const [accountA, accountB]);

      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      final withSignature = tester
          .widget<TextField>(find.byKey(const Key('body-field')))
          .controller!
          .text;

      final typed = '$withSignature merhaba, ek yazı';
      await tester.enterText(find.byKey(const Key('body-field')), typed);
      await tester.pump();

      await tester.tap(find.byKey(const Key('from-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b@example.com').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        typed,
        reason: 'switching Kimden after real typing must never touch the body again',
      );
    });
  });

  group('formatting toolbar', () {
    testWidgets('bold/italic/underline wrap the cursor position', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(find.byKey(const Key('body-field')), 'Hello');
      await tester.pump();
      await tester.tap(find.byKey(const Key('format-bold')));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        'Hello****',
      );
    });

    testWidgets('list button bullet-prefixes the current line', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(
        find.byKey(const Key('body-field')),
        'Alınacaklar',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('format-list')));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        '- Alınacaklar',
      );
    });

    testWidgets(
      'number, quote, indent and clear actions work from scrollable toolbar',
      (tester) async {
        tester.view
          ..physicalSize = const Size(320, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
        final body = tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!;

        await tester.enterText(find.byKey(const Key('body-field')), 'ana\nalt');
        body.selection = TextSelection(
          baseOffset: 0,
          extentOffset: body.text.length,
        );
        await tester.tap(find.byKey(const Key('format-numbered-list')));
        await tester.pump();
        expect(body.text, '1. ana\n2. alt');

        body.selection = const TextSelection.collapsed(offset: 10);
        await tester.tap(find.byKey(const Key('format-indent-increase')));
        await tester.pump();
        expect(body.text, '1. ana\n  1. alt');

        body.selection = TextSelection(
          baseOffset: 0,
          extentOffset: body.text.length,
        );
        await tester.tap(find.byKey(const Key('format-quote')));
        await tester.pump();
        expect(body.text, '> 1. ana\n>   1. alt');

        await tester.drag(
          find.byKey(const Key('format-toolbar')),
          const Offset(-300, 0),
        );
        await tester.pumpAndSettle();
        body.selection = TextSelection(
          baseOffset: 0,
          extentOffset: body.text.length,
        );
        await tester.tap(find.byKey(const Key('format-clear')));
        await tester.pump();
        expect(body.text, 'ana\nalt');
      },
    );

    testWidgets(
      'link button inserts markdown-lite markup from the URL dialog',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

        await tester.tap(find.byKey(const Key('format-link')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'https://ornek.com',
        );
        await tester.tap(find.text('Ekle'));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(find.byKey(const Key('body-field')))
              .controller!
              .text,
          '[bağlantı](https://ornek.com)',
        );
      },
    );
  });

  group('undo send', () {
    testWidgets(
      'queues the send, pops immediately, and delivers after the window',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

        await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('subject-field')), 'Konu');
        await tester.pump();

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pumpAndSettle();

        expect(find.text('Geri Al'), findsOneWidget);
        expect(repo.sent, isEmpty, reason: 'send is deferred, not immediate');
        expect(
          find.byType(ComposeScreen),
          findsNothing,
          reason: 'compose pops right away',
        );

        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );
        expect(repo.sent, hasLength(1));
        expect(repo.sent.single.recipients, ['x@y.com']);
        expect(repo.sent.single.subject, 'Konu');
      },
    );

    testWidgets(
      'formatted mail delivers bodyHtml matching the toolbar markup, plain mail sends none',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

        await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('body-field')), 'Hello');
        await tester.pump();
        await tester.tap(find.byKey(const Key('format-bold')));
        await tester.pump();

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pumpAndSettle();
        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );

        expect(repo.sent, hasLength(1));
        expect(repo.sent.single.bodyText, 'Hello****');
        expect(repo.sent.single.bodyHtml, markdownLiteToHtml('Hello****'));
        expect(repo.sent.single.bodyHtml, isNot(equals('Hello****')));
      },
    );

    testWidgets('plain unformatted mail sends no bodyHtml alternative', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('body-field')), 'düz metin');
      await tester.pump();

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.bodyHtml, isNull);
    });

    testWidgets(
      'resolves the picked Kimden account to its id, not just the email',
      (tester) async {
        final repo = _FakeMailRepository(
          accounts: const [_accountA, _accountB],
        );
        await _pumpCompose(tester, repo: repo, initialFrom: 'b@example.com');

        await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pumpAndSettle();
        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );

        expect(repo.sent, hasLength(1));
        expect(repo.sent.single.accountId, 'acc-b');
      },
    );

    testWidgets(
      'Geri Al cancels the send and reopens compose with the same content',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

        await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.enterText(find.byKey(const Key('subject-field')), 'Konu');
        await tester.pump();

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Geri Al'));
        await tester.pumpAndSettle();

        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );
        expect(repo.sent, isEmpty, reason: 'cancelled send must never fire');

        expect(find.byType(ComposeScreen), findsOneWidget);
        expect(find.text('x@y.com'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('subject-field')))
              .controller!
              .text,
          'Konu',
        );
      },
    );
  });

  testWidgets(
    'outbox exposes failed message and reopens its content for editing',
    (tester) async {
      final store = OutboxStore.inMemory();
      PendingSendQueue.instance.useStoreForTest(store);
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      store.save(
        OutboxItem(
          send: const PendingSend(
            id: 'failed-1',
            from: 'a@example.com',
            fromAccountId: 'acc-a',
            to: ['x@y.com'],
            subject: 'Saklanan konu',
            body: 'Saklanan gövde',
          ),
          status: OutboxStatus.failed,
          undoUntil: DateTime.now(),
          error: 'Alıcı reddedildi',
        ),
      );
      navigator.push(MaterialPageRoute(builder: (_) => const OutboxScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Saklanan konu'), findsOneWidget);
      expect(find.text('Alıcı reddedildi'), findsOneWidget);
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('body-field')))
            .controller!
            .text,
        'Saklanan gövde',
      );
    },
  );

  testWidgets(
    'uncertain outbox requires explicit duplicate-risk confirmation',
    (tester) async {
      final store = OutboxStore.inMemory();
      PendingSendQueue.instance.useStoreForTest(store);
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      store.save(
        OutboxItem(
          send: const PendingSend(
            id: 'unknown-1',
            from: 'a@example.com',
            fromAccountId: 'acc-a',
            to: ['x@y.com'],
            subject: 'Sonucu belirsiz',
            body: 'Gövde saklandı',
          ),
          status: OutboxStatus.uncertain,
          undoUntil: DateTime.now(),
        ),
      );
      navigator.push(MaterialPageRoute(builder: (_) => const OutboxScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Tekrar dene'), findsNothing);
      await tester.tap(find.text('Elle yeniden oluştur'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ikinci bir kopya'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
      await tester.tap(find.text('Elle yeniden oluştur'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni gönderi').last);
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(store.load().single.status, OutboxStatus.uncertain);
    },
  );

  group('schedule send (Zamanla)', () {
    testWidgets('calls scheduleSend with a future date/time and confirms', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('subject-field')), 'Konu');
      await tester.pump();

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zamanla'));
      await tester.pumpAndSettle();

      // Date picker: move to the next month and pick its first day —
      // deterministically in the future regardless of what day/time the
      // test happens to run at (accepting "today" as-is would be flaky
      // right around midnight, since the time picker's own suggestion can
      // land on the next calendar day).
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Time picker: accept the pre-selected initial time.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(repo.scheduled, hasLength(1));
      expect(repo.scheduled.single.to, ['x@y.com']);
      expect(find.textContaining('zamanlandı'), findsOneWidget);
    });
  });

  group('remote attachment readiness (forward / draft attachments)', () {
    testWidgets('a successfully downloaded remote attachment can be sent', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      repo.downloadAttachmentImpl = (_, _) async =>
          Uint8List.fromList([1, 2, 3]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialTo: 'x@y.com',
        initialAttachments: const [
          Attachment(id: 'att-1', name: 'dosya.pdf', sizeBytes: 100),
        ],
        attachmentSourceMailId: 'source-1',
      );

      expect(find.text('dosya.pdf'), findsOneWidget);
      expect(find.byTooltip('Tekrar indir'), findsNothing);

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.attachments.single.bytes, [1, 2, 3]);
    });

    testWidgets(
      'a still-downloading attachment blocks Send until it resolves',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA]);
        final completer = Completer<Uint8List>();
        repo.downloadAttachmentImpl = (_, _) => completer.future;
        await _pumpCompose(
          tester,
          repo: repo,
          initialFrom: 'a@example.com',
          initialTo: 'x@y.com',
          initialAttachments: const [
            Attachment(id: 'att-1', name: 'dosya.pdf', sizeBytes: 100),
          ],
          attachmentSourceMailId: 'source-1',
          settle: false,
        );

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pump();
        expect(repo.sent, isEmpty, reason: 'still downloading — must not send');
        expect(find.text('Ekler hazırlanıyor, lütfen bekleyin.'), findsWidgets);

        completer.complete(Uint8List.fromList([9]));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );
        expect(repo.sent, hasLength(1));
      },
    );

    testWidgets('a failed attachment download blocks Send and can be retried', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      repo.downloadAttachmentImpl = (_, _) async => throw Exception('boom');
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialTo: 'x@y.com',
        initialAttachments: const [
          Attachment(id: 'att-1', name: 'dosya.pdf', sizeBytes: 100),
        ],
        attachmentSourceMailId: 'source-1',
      );

      expect(find.byTooltip('Tekrar indir'), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        repo.sent,
        isEmpty,
        reason: 'failed attachment must never be silently dropped',
      );
      expect(
        find.text('Bir ek indirilemedi. Tekrar deneyin veya kaldırın.'),
        findsOneWidget,
      );

      repo.downloadAttachmentImpl = (_, _) async => Uint8List.fromList([7]);
      await tester.tap(find.byTooltip('Tekrar indir'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tekrar indir'), findsNothing);

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );
      expect(repo.sent, hasLength(1));
    });

    testWidgets('removing a failed attachment unblocks Send', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      repo.downloadAttachmentImpl = (_, _) async => throw Exception('boom');
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialTo: 'x@y.com',
        initialAttachments: const [
          Attachment(id: 'att-1', name: 'dosya.pdf', sizeBytes: 100),
        ],
        attachmentSourceMailId: 'source-1',
      );

      await tester.tap(find.byTooltip('Kaldır'));
      await tester.pumpAndSettle();
      expect(find.text('dosya.pdf'), findsNothing);

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );
      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.attachments, isEmpty);
    });
  });
}
