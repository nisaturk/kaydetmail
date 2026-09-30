import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/compose_screen.dart';
import 'package:kaydetmail/screens/home_screen.dart';
import 'package:kaydetmail/screens/outbox_screen.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:kaydetmail/services/session_store.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
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
  final List<bool> readReceiptRequests = [];
  final draftFailures = StreamController<Email>.broadcast();

  @override
  Stream<Email> get draftSyncFailures => draftFailures.stream;

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
  Future<void> signOutAccount(String accountId) async {}

  @override
  Future<void> reconnect({required String password}) async {}

  @override
  Future<Set<String>> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async => {};

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
  Future<List<MailSession>> getSessions({String? accountId}) async => const [];

  @override
  Future<void> revokeSession(String sessionId, {String? accountId}) async {}

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

  Future<List<MailIdentity>> Function(String accountId)? listIdentitiesImpl;

  Map<String, List<MailSignature>> signatures = {};

  @override
  Future<List<MailSignature>> listSignatures(
    String accountId, {
    bool refresh = false,
  }) async => signatures[accountId] ?? const [];

  @override
  Future<SignatureDefaults> getSignatureDefaults(String accountId) async {
    final available = signatures[accountId];
    if (available == null) throw StateError('signatures unavailable');
    return SignatureDefaults(
      newMailSignatureId: available.first.id,
      replySignatureId: available.first.id,
    );
  }

  @override
  Future<List<MailIdentity>> listIdentities(
    String accountId, {
    bool refresh = false,
  }) => (listIdentitiesImpl ?? (_) async => const [])(accountId);

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
    readReceiptRequests.add(requestReadReceipt);
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
    void Function(Email draft)? onSyncFailure,
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
    String? accountId,
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
    String? accountId,
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
    bool requestReadReceipt = false,
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

MailSignature _signature(String id, String text) => MailSignature(
  id: id,
  name: id,
  bodyText: text,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Future<void> _pumpCompose(
  WidgetTester tester, {
  required _FakeMailRepository repo,
  String? initialFrom,
  String? initialTo,
  String? editingDraftId,
  String? initialBody,
  String? initialBodyHtml,
  String? initialIdentityId,
  String? inReplyToId,
  int initialReplyWritingLines = 0,
  bool insertSignature = true,
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
        initialBodyHtml: initialBodyHtml,
        initialIdentityId: initialIdentityId,
        inReplyToId: inReplyToId,
        initialReplyWritingLines: initialReplyWritingLines,
        insertSignature: insertSignature,
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

quill.QuillController _body(WidgetTester tester) => tester
    .widget<quill.QuillEditor>(find.byKey(const Key('body-field')))
    .controller;

String _bodyText(WidgetTester tester) {
  final text = _body(tester).document.toPlainText();
  return text.substring(0, text.length - 1);
}

void _setBody(WidgetTester tester, String text) {
  final body = _body(tester);
  body.replaceText(
    0,
    body.document.length - 1,
    text,
    TextSelection.collapsed(offset: text.length),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
    PendingSendQueue.instance.useStoreForTest(OutboxStore.inMemory());
  });

  group('compose exit behavior', () {
    testWidgets('background draft failure opens editor only on user request', (
      tester,
    ) async {
      final draft = Email(
        id: 'local-draft-failed',
        accountId: _accountA.id,
        senderEmail: _accountA.email,
        senderName: 'Me',
        recipients: const ['reply@example.com'],
        subject: 'Saved reply',
        bodyText: 'My locally saved reply',
        timestamp: DateTime.utc(2026),
        folder: MailFolder.drafts,
      );
      final repo = _FakeMailRepository(
        accounts: const [_accountA],
        emails: [draft],
      );
      AppSettingsController.resetForTest();
      const widgetUpdates = MethodChannel('home_widget/updates');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        widgetUpdates,
        (_) async => null,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          widgetUpdates,
          null,
        );
      });
      AppConfig.mailRepositoryForTest = repo;
      await SessionStore.addEmail(_accountA.email);
      await tester.runAsync(() async {
        await tester.pumpWidget(const KaydetApp());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);

      repo.draftFailures.add(draft);
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
      await tester.tap(find.widgetWithText(SnackBarAction, 'Aç'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(_bodyText(tester), draft.bodyText);
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);

      repo.draftFailures.add(draft);
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await repo.draftFailures.close();
      AppSettingsController.resetForTest();
    });

    testWidgets('new mail offers save as draft or discard', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      _setBody(tester, 'keep this draft');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Bu taslak ne olsun?'), findsOneWidget);
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
      _setBody(tester, 'discard this draft');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taslağı Sil'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, isEmpty);
    });

    testWidgets('leaving an unchanged existing draft does not rewrite it', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialBody: 'existing draft',
        editingDraftId: 'draft-existing',
      );

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Taslağı kaydedilsin mi?'), findsNothing);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, isEmpty);
    });

    testWidgets('leaving a changed existing draft saves without asking', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialBody: 'existing draft',
        editingDraftId: 'draft-existing',
      );
      _setBody(tester, 'updated draft');

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.text('Taslağı kaydedilsin mi?'), findsNothing);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts.single.id, 'draft-existing');
      expect(repo.savedDrafts.single.bodyText, 'updated draft');
    });

    testWidgets('clearing an existing draft persists the empty content', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialBody: 'remove this',
        editingDraftId: 'draft-existing',
      );
      _setBody(tester, '');

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts.single.id, 'draft-existing');
      expect(repo.savedDrafts.single.bodyText, isEmpty);
    });

    testWidgets('overflow menu deletes the edited draft after confirmation', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialBody: 'eski taslak',
        editingDraftId: 'draft-existing',
      );

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(repo.deletedDrafts, isEmpty);
      expect(find.byType(ComposeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-discard')));
      await tester.pumpAndSettle();

      expect(repo.deletedDrafts, ['draft-existing']);
      expect(repo.savedDrafts, isEmpty);
      expect(find.byType(ComposeScreen), findsNothing);
    });

    testWidgets('Sil on an empty new mail closes without asking', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, isEmpty);
    });

    testWidgets('Sil on an unsaved mail with content confirms and saves '
        'nothing', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      _setBody(tester, 'at gitsin');

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, isEmpty);
      expect(repo.deletedDrafts, isEmpty);
    });

    testWidgets('Taslağı kaydet is disabled until there is content', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      PopupMenuItem<Object?> saveItem() =>
          tester.widget(find.byKey(const Key('compose-menu-saveDraft')));
      expect(saveItem().enabled, isFalse);
      await tester.tap(find.text('Taslağı kaydet'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.savedDrafts, isEmpty);

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      _setBody(tester, 'yarım kalan');
      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      expect(saveItem().enabled, isTrue);
    });

    testWidgets('saving from the menu keeps compose open and exit does not '
        'ask again or duplicate the draft', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      _setBody(tester, 'yarım kalan');

      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taslağı kaydet'));
      await tester.pumpAndSettle();

      expect(repo.savedDrafts, hasLength(1));
      expect(find.text('Taslak kaydedildi.'), findsOneWidget);
      expect(find.byType(ComposeScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('save-draft-on-exit')), findsNothing);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, hasLength(1));
    });

    testWidgets('edits after a menu save are saved to the same draft on exit', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      _setBody(tester, 'ilk');
      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taslağı kaydet'));
      await tester.pumpAndSettle();

      _setBody(tester, 'ikinci');
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(repo.savedDrafts, hasLength(2));
      expect(repo.savedDrafts.last.id, repo.savedDrafts.first.id);
      expect(repo.savedDrafts.last.bodyText, 'ikinci');
    });
  });

  group('read receipt toggle', () {
    testWidgets('toggles with feedback and reaches the send', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      Future<void> toggle() async {
        await tester.tap(find.byKey(const Key('send-options-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Okundu bilgisi iste'));
        await tester.pumpAndSettle();
      }

      await toggle();
      expect(
        find.text('Alıcılardan okundu bilgisi istenecek.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('send-options-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('read-receipt-on')), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await toggle();
      expect(find.text('Okundu bilgisi istenmeyecek.'), findsOneWidget);
      await toggle();

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.readReceiptRequests, [true]);
    });

    testWidgets('is off unless the user opts in', (tester) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.readReceiptRequests, [false]);
    });
  });

  group('add from contacts', () {
    testWidgets('adds picked contacts to the chosen field, skipping '
        'duplicates', (tester) async {
      final repo = _FakeMailRepository(
        accounts: const [_accountA],
        emails: [
          Email(
            id: 'm1',
            senderName: 'Ayşe Yılmaz',
            senderEmail: 'ayse@example.com',
            recipients: const ['a@example.com'],
            subject: 'S',
            bodyText: 'B',
            timestamp: DateTime(2024, 1, 2),
          ),
          Email(
            id: 'm2',
            senderName: 'Mehmet Kaya',
            senderEmail: 'mehmet@example.com',
            recipients: const ['a@example.com'],
            subject: 'S',
            bodyText: 'B',
            timestamp: DateTime(2024, 1, 1),
          ),
        ],
      );
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      Future<void> openPicker() async {
        await tester.tap(find.byKey(const Key('send-options-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kişilerden ekle'));
        await tester.pumpAndSettle();
      }

      await openPicker();
      await tester.enterText(
        find.byKey(const Key('contact-picker-search')),
        'ayş',
      );
      await tester.pump();
      expect(find.text('Mehmet Kaya'), findsNothing);
      await tester.tap(find.text('Ayşe Yılmaz'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('contact-picker-add')));
      await tester.pumpAndSettle();
      expect(find.text('ayse@example.com'), findsOneWidget);
      await openPicker();
      await tester.tap(find.text('Ayşe Yılmaz'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('contact-picker-add')));
      await tester.pumpAndSettle();
      expect(find.text('ayse@example.com'), findsOneWidget);

      await openPicker();
      await tester.tap(find.text('Cc'));
      await tester.pump();
      await tester.tap(find.text('Mehmet Kaya'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('contact-picker-add')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('subject-field')), 'Konu');
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.sent.single.recipients, ['ayse@example.com']);
      expect(repo.sent.single.cc, ['mehmet@example.com']);
    });
  });

  group('identity loading', () {
    testWidgets('reports an unavailable requested identity without raw error', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA])
        ..listIdentitiesImpl = (_) async => throw StateError('secret detail');
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        initialIdentityId: 'identity-a',
      );

      expect(
        find.textContaining('Gönderen kimliği yüklenemedi'),
        findsOneWidget,
      );
      expect(find.textContaining('secret detail'), findsNothing);
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

      final bodyText = _bodyText(tester);
      expect(bodyText, '\n\n--\nSaygılarımla,\nA');
    });

    for (final rich in [false, true]) {
      testWidgets(
        'reply signature precedes history and switches without altering ${rich ? 'rich' : 'plain'} quotation',
        (tester) async {
          final repo =
              _FakeMailRepository(accounts: const [_accountA, _accountB])
                ..signatures = {
                  'acc-a': [_signature('a', 'İmza A')],
                  'acc-b': [_signature('b', 'İmza B')],
                };
          await _pumpCompose(
            tester,
            repo: repo,
            initialFrom: 'a@example.com',
            inReplyToId: 'old-mail',
            initialReplyWritingLines: 5,
            initialBody: 'Ayşe yazdı:\n> Eski yanıt\n> İç geçmiş',
            initialBodyHtml: rich
                ? '<p>Ayşe yazdı:</p><blockquote><p><strong>Eski yanıt</strong></p>'
                      '<p><a href="https://example.com">İç geçmiş</a></p></blockquote>'
                : null,
          );
          final before = _bodyText(tester);
          expect(
            before.indexOf('İmza A'),
            lessThan(before.indexOf('Ayşe yazdı:')),
          );
          final history = before.substring(before.indexOf('Ayşe yazdı:'));
          expect(history, contains('Eski yanıt'));
          expect(history, contains('İç geçmiş'));
          final historyOffset = before.indexOf('Ayşe yazdı:');
          final historyDelta = _body(tester).document
              .toDelta()
              .slice(historyOffset);

          await tester.tap(find.byKey(const Key('from-account-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('b@example.com').last);
          await tester.pumpAndSettle();

          final after = _bodyText(tester);
          expect(
            after.indexOf('İmza B'),
            lessThan(after.indexOf('Ayşe yazdı:')),
          );
          expect(after, isNot(contains('İmza A')));
          expect(after.substring(after.indexOf('Ayşe yazdı:')), history);
          expect(
            _body(tester).document
                .toDelta()
                .slice(after.indexOf('Ayşe yazdı:')),
            historyDelta,
          );
          if (rich) {
            await tester.tap(find.byTooltip('Kapat'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Taslağı Kaydet'));
            await tester.pumpAndSettle();
            final saved = repo.savedDrafts.single;
            expect(
              saved.bodyHtml!.indexOf('İmza B'),
              lessThan(saved.bodyHtml!.indexOf('Ayşe yazdı:')),
            );
            final quote = html_parser
                .parse(saved.bodyHtml)
                .querySelector('blockquote')!;
            expect(quote.querySelector('strong')!.text, 'Eski yanıt');
            expect(
              quote.querySelector('a')!.attributes['href'],
              'https://example.com',
            );
          }
        },
      );
    }

    testWidgets(
      'formatting-only changes are not overwritten on sender switch',
      (tester) async {
        final repo = _FakeMailRepository(
          accounts: const [
            MailAccount(
              id: 'acc-a',
              email: 'a@example.com',
              signature: 'İmza A',
            ),
            MailAccount(
              id: 'acc-b',
              email: 'b@example.com',
              signature: 'İmza B',
            ),
          ],
        );
        await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
        final controller = _body(tester);
        controller.formatText(
          _bodyText(tester).indexOf('İmza A'),
          6,
          quill.Attribute.bold,
        );
        final edited = controller.document.toDelta();

        await tester.tap(find.byKey(const Key('from-account-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('b@example.com').last);
        await tester.pumpAndSettle();

        expect(controller.document.toDelta(), edited);
      },
    );

    testWidgets('a delayed default identity uses its own reply signature', (
      tester,
    ) async {
      final identities = Completer<List<MailIdentity>>();
      final repo = _FakeMailRepository(accounts: const [_accountA])
        ..signatures = {
          'acc-a': [
            _signature('reply', 'Hesap imzası'),
            _signature('alias', 'Kimlik imzası'),
          ],
        }
        ..listIdentitiesImpl = (_) => identities.future;
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        inReplyToId: 'old-mail',
        initialReplyWritingLines: 5,
        initialBody: 'Ayşe yazdı:\n> Eski yanıt',
      );
      expect(_bodyText(tester), contains('Hesap imzası'));
      identities.complete(const [
        MailIdentity(
          id: 'alias-id',
          emailAddress: 'alias@example.com',
          signatureId: 'alias',
          isDefault: true,
        ),
      ]);
      await tester.pumpAndSettle();
      final body = _bodyText(tester);
      expect(body, isNot(contains('Hesap imzası')));
      expect(
        body.indexOf('Kimlik imzası'),
        lessThan(body.indexOf('Ayşe yazdı:')),
      );
      expect(body, contains('Eski yanıt'));
    });

    testWidgets('restoring a composed reply never duplicates its signature', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA])
        ..signatures = {
          'acc-a': [_signature('reply', 'İmza A')],
        };
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        inReplyToId: 'old-mail',
        insertSignature: false,
        initialBody: '\n\n\n\n\nYanıt\n\n--\nİmza A\n\nAyşe yazdı:\nEski yanıt',
        initialBodyHtml:
            '<p><br></p><p><br></p><p><br></p><p><br></p><p><br></p>'
            '<p>Yanıt</p><p><br></p><p>--</p><p>İmza A</p><p><br></p>'
            '<p>Ayşe yazdı:</p><blockquote><p>Eski yanıt</p></blockquote>',
      );
      final text = _bodyText(tester);
      expect('İmza A'.allMatches(text), hasLength(1));
      expect(text.indexOf('İmza A'), lessThan(text.indexOf('Ayşe yazdı:')));
      expect(
        _body(tester).document
            .toDelta()
            .toList()
            .any((op) => op.attributes?['blockquote'] == true),
        isTrue,
      );
    });

    testWidgets(
      'Undo restores reply writing space and signature exactly once',
      (tester) async {
        final repo = _FakeMailRepository(accounts: const [_accountA])
          ..signatures = {
            'acc-a': [_signature('reply', 'İmza A')],
          };
        await _pumpCompose(
          tester,
          repo: repo,
          initialFrom: 'a@example.com',
          initialTo: 'friend@example.com',
          inReplyToId: 'old-mail',
          initialReplyWritingLines: 5,
          initialBody: 'Ayşe yazdı:\nEski yanıt',
          initialBodyHtml:
              '<p>Ayşe yazdı:</p>'
              '<blockquote><p><strong>Eski yanıt</strong></p></blockquote>',
        );
        _body(tester).replaceText(
          0,
          0,
          'Yeni yanıt',
          const TextSelection.collapsed(offset: 10),
        );
        final before = _bodyText(tester);
        final beforeDelta = _body(tester).document.toDelta();
        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Geri Al'));
        await tester.pumpAndSettle();

        expect(_bodyText(tester), before);
        expect(_body(tester).document.toDelta(), beforeDelta);
        expect('İmza A'.allMatches(_bodyText(tester)), hasLength(1));
        await tester.pump(
          PendingSendQueue.undoWindow + const Duration(seconds: 1),
        );
        expect(repo.sent, isEmpty);
      },
    );

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

      final bodyText = _bodyText(tester);
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
      expect(_bodyText(tester), '\n\n--\nİmza A');

      await tester.tap(find.byKey(const Key('from-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b@example.com').last);
      await tester.pumpAndSettle();

      expect(_bodyText(tester), '\n\n--\nİmza B');
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
      final withSignature = _bodyText(tester);

      final typed = '$withSignature merhaba, ek yazı';
      _setBody(tester, typed);
      await tester.pump();

      await tester.tap(find.byKey(const Key('from-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b@example.com').last);
      await tester.pumpAndSettle();

      expect(
        _bodyText(tester),
        typed,
        reason: 'switching Kimden after real typing must never touch the body again',
      );
    });
  });

  group('rich body', () {
    testWidgets('restores draft HTML as rich text and saves it back as HTML', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        editingDraftId: 'draft-rich',
        initialBody: 'Merhaba dünya',
        initialBodyHtml: '<p><strong>Merhaba</strong> dünya</p>',
      );

      expect(_bodyText(tester), 'Merhaba dünya');
      final body = _body(tester);
      body.replaceText(
        body.document.length - 1,
        0,
        '!',
        TextSelection.collapsed(offset: body.document.length),
      );
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      final saved = repo.savedDrafts.single;
      expect(saved.bodyText, 'Merhaba dünya!');
      expect(saved.bodyHtml, contains('<strong>Merhaba</strong>'));
    });

    testWidgets('bullet list toolbar action is serialized to HTML list', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');
      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      _setBody(tester, 'Alınacaklar');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.format_list_bulleted));
      await tester.pump();

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.sent.single.bodyText, 'Alınacaklar');
      expect(
        repo.sent.single.bodyHtml,
        contains('<ul><li>Alınacaklar</li></ul>'),
      );
    });

    testWidgets('quoted images render as placeholders and survive in HTML', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(
        tester,
        repo: repo,
        initialFrom: 'a@example.com',
        editingDraftId: 'draft-img',
        initialBody: 'Logo',
        initialBodyHtml:
            '<p>Logo</p><p><img src="https://cdn.example.com/logo.png"></p>',
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Görsel'), findsOneWidget);
      _body(tester)
          .replaceText(0, 0, 'Yeni ', const TextSelection.collapsed(offset: 5));
      await tester.pump();
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();

      final saved = repo.savedDrafts.single;
      expect(saved.bodyText, isNot(contains('\uFFFC')));
      expect(saved.bodyText, startsWith('Yeni Logo'));
      expect(saved.bodyHtml, contains('https://cdn.example.com/logo.png'));
    });
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

    testWidgets('formatted mail delivers bodyHtml matching the editor styles', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      _setBody(tester, 'Hello');
      _body(tester).updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
        quill.ChangeSource.local,
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.format_bold));
      await tester.pump();

      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      await tester.pump(
        PendingSendQueue.undoWindow + const Duration(seconds: 1),
      );

      expect(repo.sent, hasLength(1));
      expect(repo.sent.single.bodyText, 'Hello');
      expect(repo.sent.single.bodyHtml, contains('<strong>Hello</strong>'));
    });

    testWidgets('plain unformatted mail sends no bodyHtml alternative', (
      tester,
    ) async {
      final repo = _FakeMailRepository(accounts: const [_accountA]);
      await _pumpCompose(tester, repo: repo, initialFrom: 'a@example.com');

      await tester.enterText(find.byKey(const Key('to-field')), 'x@y.com');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      _setBody(tester, 'düz metin');
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
      expect(_bodyText(tester), 'Saklanan gövde');
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
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
      messenger
        ..showSnackBar(const SnackBar(content: Text('Eski uyarı')))
        ..showSnackBar(const SnackBar(content: Text('Kuyruktaki eski uyarı')));

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
      expect(repo.sent, isEmpty);
      expect(find.byType(ComposeScreen), findsNothing);
      expect(find.text('Eski uyarı'), findsNothing);
      expect(find.text('Kuyruktaki eski uyarı'), findsNothing);
      expect(find.textContaining('gönderiliyor'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Kuyruktaki eski uyarı'), findsNothing);
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
