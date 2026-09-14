import 'dart:math';

import 'package:flutter/material.dart';

import '../data/mock/mock_email_generator.dart';
import '../data/mock/mock_emails.dart';
import '../models/email.dart';
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
  static const Duration _latency = Duration(milliseconds: 350);

  final List<Email> _emails = [...MockEmails.seed];
  final List<MailLabel> _labels = [...MockLabels.all];
  final Random _random = Random();

  String _currentUser = 'me@kaydet.app';
  bool _loading = false;

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
    notifyListeners();
    return true;
  }

  @override
  Future<void> logout() async {
    await _delay();
    notifyListeners();
  }

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
  }) {
    final email = Email(
      id: 'composed-${DateTime.now().microsecondsSinceEpoch}-'
          '${_random.nextInt(1 << 32)}',
      senderName: 'Me',
      senderEmail: _currentUser,
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
  }) async {
    await _delay();
    final email = _createFromCompose(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      folder: MailFolder.drafts,
    );
    notifyListeners();
    return email;
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    await _delay();
    _replaceMany(
        ids, (e) => e.folder == MailFolder.trash ? e : e.copyWith(folder: MailFolder.trash));
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
    _replaceMany(ids, (e) => e.copyWith(isPinned: pinned));
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
      List<String> emailIds, List<String> labelIds) async {
    await _delay();
    _replaceMany(emailIds, (e) {
      final updated = {...e.labelIds, ...labelIds}.toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }

  @override
  Future<void> removeLabelsFromEmails(
      List<String> emailIds, List<String> labelIds) async {
    await _delay();
    final remove = labelIds.toSet();
    _replaceMany(emailIds, (e) {
      final updated =
          e.labelIds.where((id) => !remove.contains(id)).toList();
      return e.copyWith(labelIds: updated);
    });
    notifyListeners();
  }
}