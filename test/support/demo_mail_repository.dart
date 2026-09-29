import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kaydetmail/models/compose_limits.dart';
import 'package:kaydetmail/models/compose_prefill.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_session.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/models/mail_template.dart';
import 'package:kaydetmail/models/manual_contact.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';

/// Fully in-memory [MailRepository] with realistic, deliberately awkward
/// demo data (long subjects and addresses, unbreakable URLs, tables, many
/// recipients, several accounts). Used by the screen-matrix layout tests to
/// render every screen without a backend.
class DemoMailRepository extends MailRepository {
  DemoMailRepository({List<MailAccount>? accounts})
    : accounts = accounts ?? demoAccounts,
      _emails = demoEmails();

  static const demoAccounts = [
    MailAccount(
      id: 'acc-1',
      email: 'ayse.yilmaz.uzun.bir.eposta.adresi@example-kurumsal-alan-adi.com.tr',
      displayName: 'Ayşe Yılmaz',
      provider: AccountProvider.google,
      quota: AccountQuota(usedBytes: 8 * 1024 * 1024 * 1024, limitBytes: 15 * 1024 * 1024 * 1024),
    ),
    MailAccount(id: 'acc-2', email: 'ben@outlook.com', provider: AccountProvider.microsoft),
    MailAccount(
      id: 'acc-3',
      email: 'destek@example.com',
      status: MailAccountStatus.needsReauthentication,
    ),
  ];

  @override
  final List<MailAccount> accounts;

  final List<Email> _emails;
  final List<Email> sent = [];
  String? _active;

  @override
  String get currentUser => accounts.first.email;

  @override
  bool get isLoggedIn => true;

  @override
  String? get activeAccountId => _active;

  @override
  Future<void> setActiveAccount(String? accountId) async {
    _active = accountId;
    notifyListeners();
  }

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
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async => accounts.first;

  @override
  Future<void> removeAccount(String accountId) async {}

  @override
  MailAccount? getAccount(String accountId) =>
      accounts.where((a) => a.id == accountId).firstOrNull;

  @override
  Future<void> restoreSession(String email) async {}

  @override
  Future<List<MailSession>> getSessions({String? accountId}) async => [
    MailSession(
      id: 's1',
      deviceIdentifier: 'Pixel 8 · Android 15 uzun cihaz adı örneği',
      createdAt: DateTime(2026, 1, 1),
      lastUsedAt: DateTime(2026, 9, 1),
      expiresAt: DateTime(2026, 12, 1),
      isCurrentDevice: true,
    ),
    MailSession(
      id: 's2',
      deviceIdentifier: 'Chrome',
      createdAt: DateTime(2026, 1, 1),
      lastUsedAt: DateTime(2026, 9, 1),
      expiresAt: DateTime(2026, 12, 1),
    ),
  ];

  @override
  Future<void> revokeSession(String sessionId, {String? accountId}) async {}

  // --- Reading ---------------------------------------------------------

  List<Email> _scoped() => [
    for (final e in _emails)
      if (_active == null || e.accountId == _active) e,
  ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  @override
  List<Email> getEmailsInFolder(MailFolder folder) => [
    for (final e in _scoped())
      if (folder == MailFolder.all ||
          e.folder == folder ||
          (folder == MailFolder.starred && e.isStarred))
        e,
  ];

  @override
  List<Email> getAllEmails() => List.unmodifiable(_emails);

  @override
  List<Email> getScopedEmails() => _scoped();

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async => const [];

  @override
  bool hasMoreEmails(MailFolder folder) => false;

  @override
  Future<void> refreshEmails(MailFolder folder) async {}

  @override
  Future<void> syncFolder(MailFolder folder) async {}

  @override
  Future<Email?> getEmail(String id) async =>
      _emails.where((e) => e.id == id).firstOrNull;

  @override
  Future<Uint8List> downloadAttachment(String mailId, Attachment attachment) async =>
      Uint8List(0);

  @override
  List<Email> getThreadEmails(String threadId) => [
    for (final e in _emails)
      if (threadId.isNotEmpty && e.threadId == threadId) e,
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async =>
      getThreadEmails(threadId);

  @override
  Future<ComposeLimits> composeLimits(String accountId) async =>
      const ComposeLimits(
        maxAttachmentBytes: 25 * 1024 * 1024,
        maxMessageAttachmentBytes: 25 * 1024 * 1024,
        maxAttachmentCount: 10,
      );

  @override
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String mode) async {
    final source = _emails.firstWhere((e) => e.id == sourceMailId);
    return ComposePrefill(
      sourceMailId: sourceMailId,
      to: mode == 'forward' ? const [] : [source.senderEmail],
      cc: mode == 'reply-all' ? source.recipients : const [],
      suggestedSubject: '${mode == 'forward' ? 'Fwd' : 'Re'}: ${source.subject}',
    );
  }

  @override
  Future<List<MailSignature>> listSignatures(String accountId, {bool refresh = false}) async => [
    MailSignature(
      id: 'sig-1',
      name: 'Kurumsal imza',
      bodyText: 'Saygılarımla,\nAyşe Yılmaz',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      accountId: accountId,
    ),
  ];

  @override
  Future<SignatureDefaults> getSignatureDefaults(String accountId) async =>
      const SignatureDefaults();

  @override
  Future<List<MailIdentity>> listIdentities(String accountId, {bool refresh = false}) async => const [];

  @override
  Future<List<MailTemplate>> listTemplates(String accountId, {bool refresh = false}) async => [
    MailTemplate(
      id: 't1',
      name: 'Toplantı daveti — uzun bir şablon adı örneği',
      subject: 'Toplantı',
      bodyText: 'Merhaba,',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      accountId: accountId,
    ),
  ];

  // --- Writing ---------------------------------------------------------

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
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      folder: MailFolder.sent,
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
    void Function(Email draft)? onSyncFailure,
  }) async => Email(
    id: draftId ?? 'draft-1',
    senderName: '',
    senderEmail: from ?? '',
    recipients: to,
    subject: subject,
    bodyText: body,
    timestamp: DateTime.now(),
    folder: MailFolder.drafts,
  );

  @override
  Future<void> deleteDraft(String draftId) async {}

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

  // --- Labels / contacts ------------------------------------------------

  static const _labels = [
    MailLabel(id: 'l1', name: 'İş', color: Color(0xFF3E7CB1)),
    MailLabel(id: 'l2', name: 'Çok uzun bir etiket adı örneği', color: Color(0xFF2E8B6E)),
  ];

  @override
  List<MailLabel> getLabels() => _labels;

  @override
  List<MailLabel> getLabelsForAccount(String accountId) => _labels;

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
    String? accountId,
  }) async => MailLabel(id: 'new', name: name, color: color);

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {}

  @override
  Future<void> deleteLabel(String labelId) async {}

  @override
  Future<void> addLabelsToEmails(List<String> emailIds, List<String> labelIds) async {}

  @override
  Future<void> removeLabelsFromEmails(List<String> emailIds, List<String> labelIds) async {}

  @override
  List<ManualContact> getManualContacts() => const [];

  @override
  List<ManualContact> getManualContactsForAccount(String accountId) => const [];

  @override
  Future<ManualContact> addManualContact({required String email, String? displayName, String? accountId}) async =>
      ManualContact(id: 'c1', accountId: 'acc-1', email: email, displayName: displayName);

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
  }) async => ScheduledSend(
    id: 'sched',
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    sendAt: sendAt,
    status: ScheduledSendStatus.pending,
    createdAt: DateTime.now(),
  );

  @override
  Future<void> cancelScheduledSend(String id) async {}
}

const _lorem =
    'Merhaba, bu mesaj yerleşim testleri için üretilmiş uzunca bir gövde '
    'metnidir. Satır sonları ve boşluklar olmadan uzayan bağlantılar taşma '
    'sorunlarını ortaya çıkarır: '
    'https://ornek-alan-adi.example.com/cok/uzun/bir/yol/parcasi/ki/ekrana/sigmaz/'
    '1234567890abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklmnopqrstuvwxyz';

List<Email> demoEmails() {
  final base = DateTime(2026, 9, 28, 14, 30);
  const table = '<table border="1" style="width:640px"><tr><td>Ürün</td>'
      '<td>Adet</td><td>Fiyat</td><td>Toplam</td></tr>'
      '<tr><td>Kalem</td><td>10</td><td>5,00</td><td>50,00</td></tr></table>';
  Email mail(
    String id, {
    required String subject,
    String from = 'Ali Veli',
    String fromEmail = 'ali.veli@example.com',
    int minutes = 0,
    bool read = false,
    bool starred = false,
    bool pinned = false,
    String threadId = '',
    String? html,
    List<Attachment> attachments = const [],
    List<String> to = const ['ayse.yilmaz.uzun.bir.eposta.adresi@example-kurumsal-alan-adi.com.tr'],
    List<String> cc = const [],
    String accountId = 'acc-1',
    MailFolder folder = MailFolder.inbox,
    List<String> labels = const [],
  }) => Email(
    id: id,
    senderName: from,
    senderEmail: fromEmail,
    recipients: to,
    cc: cc,
    subject: subject,
    bodyText: _lorem,
    bodyHtml: html,
    timestamp: base.subtract(Duration(minutes: minutes)),
    isRead: read,
    isStarred: starred,
    isPinned: pinned,
    threadId: threadId,
    attachments: attachments,
    hasAttachments: attachments.isNotEmpty,
    accountId: accountId,
    folder: folder,
    labelIds: labels,
  );
  return [
    mail(
      'm1',
      subject: 'Çeyrek sonu raporu ve önümüzdeki dönem için bütçe planlaması hakkında',
      from: 'Muhasebe Departmanı Sorumlusu Mehmet Çelebi',
      fromEmail: 'mehmet.celebi.cok.uzun.bir.eposta@kurumsal-alan-adi-ornegi.com.tr',
      pinned: true,
      threadId: 't1',
      labels: const ['l1', 'l2'],
      attachments: const [
        Attachment(id: 'a1', name: 'ceyrek-sonu-raporu-2026-q3-final-v12-son-hali.pdf', sizeBytes: 2 * 1024 * 1024, mimeType: 'application/pdf'),
        Attachment(id: 'a2', name: 'bütçe.xlsx', sizeBytes: 90 * 1024),
      ],
      html: '<p>Merhaba <b>Ayşe</b>,</p><p>$_lorem</p>$table<ul><li>Madde bir</li><li>Madde iki</li></ul>'
          '<blockquote>Alıntı metni</blockquote>',
      to: const ['ayse@example.com', 'ali.veli@example.com', 'uzun.alici.adresi.bir@kurumsal-alan-adi-ornegi.com.tr'],
      cc: const ['cc1@example.com', 'cc2@example.com'],
    ),
    mail('m2', subject: 'Re: Çeyrek sonu raporu', from: 'Ayşe Yılmaz', fromEmail: 'ayse@example.com', minutes: 60, read: true, threadId: 't1', html: '<p>Teşekkürler, inceleyip dönüyorum.</p>'),
    mail('m3', subject: 'Re: Re: Çeyrek sonu raporu', minutes: 120, read: true, threadId: 't1'),
    mail('m4', subject: 'Kısa', minutes: 200, read: true, starred: true),
    mail('m5', subject: 'Toplantı notları', from: 'Zeynep', fromEmail: 'zeynep@example.com', minutes: 400, accountId: 'acc-2'),
    mail('m6', subject: 'Fatura', minutes: 900, read: true, folder: MailFolder.sent),
    mail('m7', subject: 'Taslak konu', minutes: 1000, folder: MailFolder.drafts),
    for (var i = 8; i < 20; i++)
      mail('m$i', subject: 'Bülten $i — haftalık özet ve kampanyalar', from: 'Bülten $i', fromEmail: 'news$i@example.com', minutes: 1000 + i * 30, read: i.isEven),
  ];
}
