import 'dart:math';

import 'package:flutter/material.dart';

import '../data/mock/mock_email_generator.dart';
import '../data/mock/mock_emails.dart';
import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import 'mail_repository.dart';

/// Fully functional in-memory implementation of [MailRepository].
///
/// All operations mutate an internal list and notify listeners, so the UI
/// updates after read/pin/trash/bulk actions. A short artificial delay makes
/// the loading states behave like a real network call. State is transient —
/// restarting the app resets it, which is fine for mock mode.
class MockMailRepository extends MailRepository {
  /// Documented mock account accepted by login while `AppConfig.useMockApi`
  /// is true. `nisa@kaydet.com` / `kaydet123`. Mock-only — no real account
  /// exists and nothing leaves the device.
  static const String demoEmail = 'nisa@kaydet.com';
  static const String demoPassword = 'kaydet123';

  /// Second mock account so the Compose "Kimden" picker has something to
  /// select. Mock-only — no real provider, no credentials.
  static const String secondMockEmail = 'nisa.yedek@kaydet.com';

  static const Duration _latency = Duration(milliseconds: 350);

  final List<Email> _emails = [...MockEmails.seed];
  final List<MailLabel> _labels = [...MockLabels.all];
  final Random _random = Random();

  String _currentUser = demoEmail;
  bool _loggedIn = false;
  bool _loading = false;

  /// Restores the pristine seed dataset (emails, labels and current user),
  /// discarding any changes made in the current session. Useful for tests and
  /// development; the normal app restart already resets mock state because it
  /// is never persisted anywhere.
  void resetMockData() {
    _emails
      ..clear()
      ..addAll(MockEmails.seed);
    _labels
      ..clear()
      ..addAll(MockLabels.all);
    _currentUser = demoEmail;
    _loggedIn = false;
    _loading = false;
    notifyListeners();
  }

  Future<void> _delay() => Future<void>.delayed(_latency);

  void _replaceMany(List<String> ids, Email Function(Email) transform) {
    for (final id in ids) {
      final index = _emails.indexWhere((e) => e.id == id);
      if (index >= 0) _emails[index] = transform(_emails[index]);
    }
  }

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async {
    await _delay();
    // Simulated auth: any well-formed credentials are accepted.
    _currentUser = email;
    _loggedIn = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> restoreSession(String email) async {
    _currentUser = email;
    _loggedIn = true;
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    await _delay();
    _loggedIn = false;
    notifyListeners();
  }

  @override
  String get currentUser => _currentUser;

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  List<MailAccount> get accounts => List.unmodifiable([
    MailAccount(email: _currentUser, displayName: 'Ben'),
    const MailAccount(email: secondMockEmail, displayName: 'Nisa Yedek'),
  ]);

  @override
  List<Email> getEmailsInFolder(MailFolder folder) {
    final result = folder == MailFolder.pinned
        ? _emails.where((e) => e.isPinned).toList()
        : _emails.where((e) => e.folder == folder).toList();
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(result);
  }

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    if (_loading) return const [];
    _loading = true;
    await _delay();
    final batch = MockEmailGenerator.generateMoreEmails(
      count: 20,
      folder: folder,
      random: _random,
    );
    _emails.addAll(batch);
    _loading = false;
    notifyListeners();
    return batch;
  }

  @override
  Future<Email?> getEmail(String id) async {
    await _delay();
    for (final e in _emails) {
      if (e.id == id) return e;
    }
    return null;
  }

  Email _createFromCompose({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    required MailFolder folder,
    String? from,
  }) {
    final email = Email(
      id:
          'composed-${DateTime.now().microsecondsSinceEpoch}-'
          '${_random.nextInt(1 << 32)}',
      senderName: 'Ben',
      senderEmail: from ?? _currentUser,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: folder,
      attachments: attachments,
    );
    _emails.add(email);
    return email;
  }

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    String? from,
  }) async {
    await _delay();
    final email = _createFromCompose(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: attachments,
      folder: MailFolder.sent,
      from: from,
    );
    notifyListeners();
    return email;
  }

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
  }) async {
    await _delay();
    final email = _createFromCompose(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      attachments: attachments,
      folder: MailFolder.drafts,
      from: from,
    );
    notifyListeners();
    return email;
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    await _delay();
    _replaceMany(
      ids,
      (e) => e.folder == MailFolder.trash
          ? e
          : e.copyWith(folder: MailFolder.trash),
    );
    notifyListeners();
  }

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(folder: folder));
    notifyListeners();
  }

  @override
  Future<void> markAsRead(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isRead: true));
    notifyListeners();
  }

  @override
  Future<void> markAsUnread(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isRead: false));
    notifyListeners();
  }

  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    await _delay();
    // ponytail: pin and star share one state in mock so Yıldızlılar keeps working.
    _replaceMany(ids, (e) => e.copyWith(isPinned: pinned, isStarred: pinned));
    notifyListeners();
  }

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    await _delay();
    // ponytail: starred mirrors pinned for the mock so Yıldızlılar stays working.
    _replaceMany(ids, (e) => e.copyWith(isStarred: starred, isPinned: starred));
    notifyListeners();
  }

  @override
  Future<void> markAsReplied(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isReplied: true, isRead: true));
    notifyListeners();
  }

  @override
  Future<void> markAsForwarded(List<String> ids) async {
    await _delay();
    _replaceMany(ids, (e) => e.copyWith(isForwarded: true, isRead: true));
    notifyListeners();
  }

  @override
  List<MailLabel> getLabels() => List.unmodifiable(_labels);

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
  }) async {
    await _delay();
    final label = MailLabel(
      id: 'label-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      color: color,
    );
    _labels.add(label);
    notifyListeners();
    return label;
  }

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    await _delay();
    _replaceMany(emailIds, (e) {
      final updated = {...e.labelIds, ...labelIds}.toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    await _delay();
    final remove = labelIds.toSet();
    _replaceMany(emailIds, (e) {
      final updated = e.labelIds.where((id) => !remove.contains(id)).toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }
}
