import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/compose_prefill.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/compose_screen.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';

/// Repository double covering everything [MailDetailScreen]'s
/// reply/reply-all/forward actions and the [ComposeScreen] they open touch.
/// Unlike the unsubscribe-test double, this can't fall back to
/// `noSuchMethod` — opening `ComposeScreen` exercises most of the write-side
/// interface (accounts, contacts, signature lookups, etc.).
class _FakeRepo extends MailRepository {
  _FakeRepo(this.email, {required this.accounts, this.prefillError});

  final Email email;
  @override
  final List<MailAccount> accounts;
  final Object? prefillError;

  final List<String> repliedIds = [];
  final List<String> forwardedIds = [];
  final List<String> requestedPrefillModes = [];
  final List<String> downloadedAttachmentIds = [];

  @override
  String get currentUser => accounts.first.email;

  @override
  bool get isLoggedIn => true;

  @override
  String? get activeAccountId => null;

  @override
  MailAccount? getAccount(String accountId) {
    for (final account in accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  @override
  Future<Email?> getEmail(String id) async => id == email.id ? email : null;

  @override
  List<Email> getThreadEmails(String threadId) => const [];

  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async => const [];

  @override
  List<Email> getAllEmails() => [email];

  @override
  List<Email> getScopedEmails() => [email];

  @override
  List<Email> getEmailsInFolder(dynamic folder) => const [];

  @override
  List<MailLabel> getLabels() => const [];

  @override
  List<ManualContact> getManualContacts() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {}

  @override
  Future<void> markAsReplied(List<String> ids) async {
    repliedIds.addAll(ids);
  }

  @override
  Future<void> markAsForwarded(List<String> ids) async {
    forwardedIds.addAll(ids);
  }

  @override
  Future<ComposePrefill> getComposePrefill(
    String sourceMailId,
    String mode,
  ) async {
    requestedPrefillModes.add(mode);
    if (prefillError != null) throw prefillError!;
    return switch (mode) {
      'reply' => const ComposePrefill(
        sourceMailId: 'm1',
        to: ['gonderen@example.com'],
        cc: [],
        suggestedSubject: 'Re: Konu',
      ),
      'reply-all' => const ComposePrefill(
        sourceMailId: 'm1',
        to: ['gonderen@example.com'],
        cc: ['diger@example.com'],
        suggestedSubject: 'Re: Konu',
      ),
      'forward' => const ComposePrefill(
        sourceMailId: 'm1',
        to: [],
        cc: [],
        suggestedSubject: 'Fwd: Konu',
        originalFrom: 'gonderen@example.com',
        originalSubject: 'Konu',
        attachments: [
          Attachment(id: 'att-1', name: 'dosya.pdf', sizeBytes: 100),
        ],
      ),
      _ => throw ArgumentError('unexpected mode: $mode'),
    };
  }

  @override
  Future<Uint8List> downloadAttachment(
    String mailId,
    Attachment attachment,
  ) async {
    downloadedAttachmentIds.add(attachment.id ?? '');
    return Uint8List.fromList([1, 2, 3]);
  }

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
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async => throw UnimplementedError();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _account = MailAccount(id: 'acc-1', email: 'ben@example.com');

Email _mail() => Email(
  id: 'm1',
  senderName: 'Gönderen',
  senderEmail: 'gonderen@example.com',
  recipients: const ['ben@example.com'],
  subject: 'Konu',
  bodyText: 'Gövde metni',
  timestamp: DateTime(2026, 1, 1),
  accountId: 'acc-1',
  threadId: 't1',
);

Future<void> _pumpDetail(WidgetTester tester, _FakeRepo repo) async {
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(
    MaterialApp(home: MailDetailScreen(emailId: repo.email.id)),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(AppConfig.resetForTest);

  testWidgets(
    'Yanıtla fetches the backend reply context and prefills ComposeScreen',
    (tester) async {
      final repo = _FakeRepo(_mail(), accounts: [_account]);
      await _pumpDetail(tester, repo);

      await tester.tap(find.byTooltip('Yanıtla'));
      await tester.pumpAndSettle();

      expect(repo.requestedPrefillModes, ['reply']);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.text('gonderen@example.com'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('subject-field')))
            .controller!
            .text,
        'Re: Konu',
      );
    },
  );

  testWidgets(
    'Tümünü Yanıtla is a visible action and includes every recipient the backend returns',
    (tester) async {
      final repo = _FakeRepo(_mail(), accounts: [_account]);
      await _pumpDetail(tester, repo);

      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tümünü Yanıtla'));
      await tester.pumpAndSettle();

      expect(repo.requestedPrefillModes, ['reply-all']);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(find.text('gonderen@example.com'), findsOneWidget);
      expect(find.text('diger@example.com'), findsOneWidget);
    },
  );

  testWidgets(
    'İlet uses the backend forward context for subject/original-context and downloads its attachment',
    (tester) async {
      final repo = _FakeRepo(_mail(), accounts: [_account]);
      await _pumpDetail(tester, repo);

      await tester.tap(find.byTooltip('İlet'));
      await tester.pumpAndSettle();

      expect(repo.requestedPrefillModes, ['forward']);
      expect(find.byType(ComposeScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('subject-field')))
            .controller!
            .text,
        'Fwd: Konu',
      );
      final body = tester
          .widget<TextField>(find.byKey(const Key('body-field')))
          .controller!
          .text;
      expect(body, contains('gonderen@example.com'));
      expect(body, contains('Konu'));
      // Attachment metadata came with no bytes — ComposeScreen must download it
      // itself rather than dropping it (spec §4/§5).
      expect(repo.downloadedAttachmentIds, ['att-1']);
      expect(find.text('dosya.pdf'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed compose-context fetch shows an error and never opens ComposeScreen',
    (tester) async {
      final repo = _FakeRepo(
        _mail(),
        accounts: [_account],
        prefillError: Exception('offline'),
      );
      await _pumpDetail(tester, repo);

      await tester.tap(find.byTooltip('Yanıtla'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposeScreen), findsNothing);
      expect(find.textContaining('Yanıt hazırlanamadı'), findsOneWidget);
    },
  );
}
