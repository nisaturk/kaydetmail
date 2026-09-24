import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/signature_settings_screen.dart';
import 'package:kaydetmail/services/signature_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SignatureSettingsScreen] only ever reads [accounts] — every other member
/// below is an unused stub required only to satisfy the abstract interface.
class _StubMailRepository extends MailRepository {
  _StubMailRepository(this.accounts);

  @override
  final List<MailAccount> accounts;

  @override
  String get currentUser => accounts.isNotEmpty ? accounts.first.email : '';

  @override
  bool get isLoggedIn => true;

  @override
  String? get activeAccountId => null;

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async => throw UnimplementedError();

  @override
  Future<void> reconnect({required String password}) async =>
      throw UnimplementedError();

  @override
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async => throw UnimplementedError();

  @override
  Future<void> unregisterDevice() async => throw UnimplementedError();

  @override
  Future<void> setActiveAccount(String? accountId) async =>
      throw UnimplementedError();

  @override
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async => throw UnimplementedError();

  @override
  Future<void> removeAccount(String accountId) async =>
      throw UnimplementedError();

  @override
  MailAccount? getAccount(String accountId) => throw UnimplementedError();

  @override
  Future<void> restoreSession(String email) async =>
      throw UnimplementedError();

  @override
  Future<List<MailSession>> getSessions() async => throw UnimplementedError();

  @override
  Future<void> revokeSession(String sessionId) async =>
      throw UnimplementedError();

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      throw UnimplementedError();

  @override
  List<Email> getAllEmails() => const [];

  @override
  List<Email> getScopedEmails() => throw UnimplementedError();

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async =>
      throw UnimplementedError();

  @override
  bool hasMoreEmails(MailFolder folder) => throw UnimplementedError();

  @override
  Future<void> refreshEmails(MailFolder folder) async =>
      throw UnimplementedError();

  @override
  Future<void> syncFolder(MailFolder folder) async =>
      throw UnimplementedError();

  @override
  Future<Email?> getEmail(String id) async => throw UnimplementedError();

  @override
  Future<Uint8List> downloadAttachment(
    String mailId,
    Attachment attachment,
  ) async => throw UnimplementedError();

  @override
  List<Email> getThreadEmails(String threadId) => throw UnimplementedError();

  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async =>
      throw UnimplementedError();

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
  }) async => throw UnimplementedError();

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
    String? draftId,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteDraft(String draftId) async =>
      throw UnimplementedError();

  @override
  Future<void> moveToTrash(List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<void> deletePermanently(List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async =>
      throw UnimplementedError();

  @override
  Future<void> markAsRead(List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<void> markAsUnread(List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<void> setPinned(List<String> ids, bool pinned) async =>
      throw UnimplementedError();

  @override
  Future<void> setStarred(List<String> ids, bool starred) async =>
      throw UnimplementedError();

  @override
  Future<void> markAsReplied(List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<void> markAsForwarded(List<String> ids) async =>
      throw UnimplementedError();

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
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteLabel(String labelId) async =>
      throw UnimplementedError();

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async => throw UnimplementedError();

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async => throw UnimplementedError();

  @override
  Future<List<Email>> searchEmailsOnServer({
    required String query,
    String? folderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    int page = 1,
    int pageSize = 20,
  }) async => throw UnimplementedError();

  @override
  Future<void> setSnoozed(List<String> ids, DateTime? until) async =>
      throw UnimplementedError();

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
    required DateTime sendAt,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelScheduledSend(String id) async =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
  });

  tearDown(() => AppConfig.resetForTest());

  testWidgets('loads and shows the saved signature per connected account', (
    tester,
  ) async {
    await SignatureStore.save('a@example.com', 'Saygılarımla,\nA');
    AppConfig.mailRepositoryForTest = _StubMailRepository(const [
      MailAccount(id: 'a', email: 'a@example.com'),
      MailAccount(id: 'b', email: 'b@example.com'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: SignatureSettingsScreen()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('signature-field-a@example.com')),
          )
          .controller!
          .text,
      'Saygılarımla,\nA',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('signature-field-b@example.com')),
          )
          .controller!
          .text,
      '',
    );
  });

  testWidgets('editing and saving persists the new signature for that account', (
    tester,
  ) async {
    AppConfig.mailRepositoryForTest = _StubMailRepository(const [
      MailAccount(id: 'a', email: 'a@example.com'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: SignatureSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('signature-field-a@example.com')),
      'Yeni imza',
    );
    await tester.tap(find.byKey(const ValueKey('signature-save-a@example.com')));
    await tester.pumpAndSettle();

    expect(await SignatureStore.load('a@example.com'), 'Yeni imza');
    expect(find.text('İmza kaydedildi.'), findsOneWidget);
  });

  testWidgets('shows an empty state when no account is connected', (tester) async {
    AppConfig.mailRepositoryForTest = _StubMailRepository(const []);

    await tester.pumpWidget(const MaterialApp(home: SignatureSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Bağlı hesap bulunamadı.'), findsOneWidget);
  });
}
