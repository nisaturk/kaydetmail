import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';

/// Server connection settings entered on the login screen.
///
/// Currently only stored/simulated. The real API integration will use these
/// once the backend contract is provided.
class MailServerSettings {
  const MailServerSettings({
    this.imapServer = 'imap.example.com',
    this.imapPort = 993,
    this.smtpServer = 'smtp.example.com',
    this.smtpPort = 587,
    this.useTls = true,
  });

  final String imapServer;
  final int imapPort;
  final String smtpServer;
  final int smtpPort;
  final bool useTls;

  MailServerSettings copyWith({
    String? imapServer,
    int? imapPort,
    String? smtpServer,
    int? smtpPort,
    bool? useTls,
  }) {
    return MailServerSettings(
      imapServer: imapServer ?? this.imapServer,
      imapPort: imapPort ?? this.imapPort,
      smtpServer: smtpServer ?? this.smtpServer,
      smtpPort: smtpPort ?? this.smtpPort,
      useTls: useTls ?? this.useTls,
    );
  }
}

/// The single interface the UI depends on.
///
/// The app is wired to either the mock or the API implementation through
/// `AppConfig` — screens never branch on which one is in use. This class
/// extends [ChangeNotifier] so screens can rebuild whenever the underlying
/// store changes.
abstract class MailRepository extends ChangeNotifier {
  // --- Auth ---------------------------------------------------------

  /// Attempts to sign in. Returns `true` on success, `false` on failure.
  ///
  /// The mock implementation accepts any well-formed credentials. The real
  /// implementation (once the backend contract exists) will talk to the API.
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  });

  Future<void> logout();

  /// Email address of the currently signed-in user.
  String get currentUser;

  // --- Reading ------------------------------------------------------

  /// Current snapshot of the folder's emails, newest first.
  List<Email> getEmailsInFolder(MailFolder folder);

  /// Fetches/appends the next page of emails for [folder].
  ///
  /// Used for infinite scrolling; should never duplicate previously returned
  /// emails and must keep existing entries intact.
  Future<List<Email>> loadMoreEmails(MailFolder folder);

  Future<Email?> getEmail(String id);

  // --- Writing ------------------------------------------------------

  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
  });

  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
  });

  /// Moves the given mails to Trash (does not delete them permanently).
  Future<void> moveToTrash(List<String> ids);

  Future<void> moveToFolder(List<String> ids, MailFolder folder);

  Future<void> markAsRead(List<String> ids);

  Future<void> markAsUnread(List<String> ids);

  Future<void> setPinned(List<String> ids, bool pinned);

  // --- Labels -------------------------------------------------------

  List<MailLabel> getLabels();

  Future<MailLabel> createLabel({required String name, required Color color});

  Future<void> addLabelsToEmails(List<String> emailIds, List<String> labelIds);

  Future<void> removeLabelsFromEmails(
      List<String> emailIds, List<String> labelIds);
}