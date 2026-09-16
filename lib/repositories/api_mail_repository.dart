import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import 'mail_repository.dart';

/// Placeholder for the future real backend implementation.
///
/// All methods currently throw [UnimplementedError]. Once the backend
/// documentation/endpoints are available, implement each method here (mapping
/// the API JSON to our models) WITHOUT touching the UI.
class ApiMailRepository extends MailRepository {
  Never _notImplemented() => throw UnimplementedError(
    'ApiMailRepository is not connected yet. '
    'Implement this method once the backend contract is provided.',
  );

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) {
    _notImplemented();
  }

  @override
  Future<void> logout() => _notImplemented();

  @override
  String get currentUser => _notImplemented();

  @override
  bool get isLoggedIn => _notImplemented();

  @override
  List<MailAccount> get accounts => _notImplemented();

  @override
  Future<void> restoreSession(String email) => _notImplemented();

  @override
  List<Email> getEmailsInFolder(MailFolder folder) => _notImplemented();

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) => _notImplemented();

  @override
  Future<Email?> getEmail(String id) => _notImplemented();

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    String? from,
  }) => _notImplemented();

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
  }) => _notImplemented();

  @override
  Future<void> moveToTrash(List<String> ids) => _notImplemented();

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) =>
      _notImplemented();

  @override
  Future<void> markAsRead(List<String> ids) => _notImplemented();

  @override
  Future<void> markAsUnread(List<String> ids) => _notImplemented();

  @override
  Future<void> setPinned(List<String> ids, bool pinned) => _notImplemented();

  @override
  Future<void> setStarred(List<String> ids, bool starred) => _notImplemented();

  @override
  Future<void> markAsReplied(List<String> ids) => _notImplemented();

  @override
  Future<void> markAsForwarded(List<String> ids) => _notImplemented();

  @override
  List<MailLabel> getLabels() => _notImplemented();

  @override
  Future<MailLabel> createLabel({required String name, required Color color}) =>
      _notImplemented();

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _notImplemented();

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _notImplemented();
}
