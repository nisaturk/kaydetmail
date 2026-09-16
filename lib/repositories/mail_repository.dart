import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
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
  /// Maximum number of mails that can be pinned at the same time.
  ///
  /// Pinning beyond this is ignored (and the UI explains it in Turkish).
  /// Unpinning frees a slot again.
  static const int maxPinnedMails = 3;

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

  /// Whether a session is active. False before login / after logout.
  bool get isLoggedIn;

  /// Locally represented sending accounts for the Compose "Kimden" picker.
  /// Mock-first: no sync, no backend contract.
  List<MailAccount> get accounts;

  /// Id of the account whose mailbox is currently shown, or `null` for the
  /// unified mailbox ("Tüm Gelen Kutuları") spanning all connected accounts.
  String? get activeAccountId;

  /// Switches the mailbox scope. `null` selects the unified mailbox.
  /// Unknown ids are ignored so stray navigation never blanks the list.
  Future<void> setActiveAccount(String? accountId);

  /// Connects a mailbox account (mock flow for now, OAuth later) and returns
  /// it. Connecting an already-connected email re-selects it instead of
  /// duplicating it.
  Future<MailAccount> connectAccount({
    required String email,
    String? displayName,
    AccountProvider? provider,
  });

  /// Disconnects an account and drops its mails. The last remaining account
  /// cannot be removed. Removing the active account falls back to unified.
  Future<void> removeAccount(String accountId);

  /// Looks up a connected account by id, or `null` when unknown.
  MailAccount? getAccount(String accountId);

  /// Restores a previously persisted session without a password.
  /// Used at startup by the session persistence layer.
  Future<void> restoreSession(String email);

  // --- Reading ------------------------------------------------------

  /// Current snapshot of the folder's emails, newest first.
  ///
  /// Scoped to the active mailbox: one account when an account is selected,
  /// all accounts when unified. Within a folder, starred/pinned mails float
  /// above the rest; newest-first is preserved inside each group.
  List<Email> getEmailsInFolder(MailFolder folder);

  /// Every mail the repository holds, regardless of folder or account,
  /// newest first. Powers unified search across accounts.
  List<Email> getAllEmails();

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
    String? from,
    String? fromAccountId,
  });

  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
  });

  /// Moves the given mails to Trash (does not delete them permanently).
  Future<void> moveToTrash(List<String> ids);

  Future<void> moveToFolder(List<String> ids, MailFolder folder);

  Future<void> markAsRead(List<String> ids);

  Future<void> markAsUnread(List<String> ids);

  Future<void> setPinned(List<String> ids, bool pinned);

  Future<void> setStarred(List<String> ids, bool starred);

  Future<void> markAsReplied(List<String> ids);

  Future<void> markAsForwarded(List<String> ids);

  // --- Labels -------------------------------------------------------

  List<MailLabel> getLabels();

  Future<MailLabel> createLabel({required String name, required Color color});

  Future<void> addLabelsToEmails(List<String> emailIds, List<String> labelIds);

  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  );
}
