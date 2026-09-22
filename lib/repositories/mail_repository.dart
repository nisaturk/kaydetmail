import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_session.dart';

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
/// `ApiMailRepository` is the only implementation; `AppConfig.mailRepository`
/// is the shared singleton screens read — they never branch on which
/// implementation is active. This class extends [ChangeNotifier] so screens
/// can rebuild whenever the underlying store changes.
abstract class MailRepository extends ChangeNotifier {
  /// Maximum number of mails that can be pinned at the same time.
  ///
  /// Pinning beyond this is ignored (and the UI explains it in Turkish).
  /// Unpinning frees a slot again.
  static const int maxPinnedMails = 3;

  // --- Auth ---------------------------------------------------------

  /// Attempts to sign in. Returns `true` on success, `false` on failure.
  ///
  /// Runs email discovery, then connects (or logs in, if already
  /// registered) against the backend. Server settings from the login screen
  /// switch to the manual IMAP/SMTP connection flow instead.
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  });

  Future<void> logout();

  /// Re-authenticates the signed-in account after its stored credentials
  /// stopped working (`mail_account_needs_reauthentication`). Keeps the
  /// session and the loaded mailbox — only the credentials are replaced.
  Future<void> reconnect({required String password});

  /// Registers this device for FCM pushes (upsert — safe on every launch).
  /// The registration id is remembered so it can be removed again on
  /// [logout].
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  });

  /// Email address of the currently signed-in user.
  String get currentUser;

  /// Whether a session is active. False before login / after logout.
  bool get isLoggedIn;

  /// True when the last attempt to reach the backend for this account's
  /// mailbox failed and the UI is showing a cached (possibly stale)
  /// snapshot instead. Always false for implementations without a cache.
  bool get isOffline => false;

  /// Sending accounts for the Compose "Kimden" picker.
  List<MailAccount> get accounts;

  /// Id of the account whose mailbox is currently shown, or `null` for the
  /// unified mailbox ("Tüm Gelen Kutuları") spanning all connected accounts.
  String? get activeAccountId;

  /// Switches the mailbox scope. `null` selects the unified mailbox.
  /// Unknown ids are ignored so stray navigation never blanks the list.
  Future<void> setActiveAccount(String? accountId);

  /// Connects a mailbox account and returns it. Connecting an
  /// already-registered email falls back to logging into it instead of
  /// registering a duplicate. The password authenticates the connection and
  /// is never stored.
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
  });

  /// Disconnects an account and drops its mails. The last remaining account
  /// cannot be removed. Removing the active account falls back to unified.
  Future<void> removeAccount(String accountId);

  /// Looks up a connected account by id, or `null` when unknown.
  MailAccount? getAccount(String accountId);

  /// Restores a previously persisted session without a password.
  /// Used at startup by the session persistence layer.
  Future<void> restoreSession(String email);

  /// Every device currently signed into this account, for the "Bağlı
  /// cihazlar" settings screen. One entry marks [MailSession.isCurrentDevice].
  Future<List<MailSession>> getSessions();

  /// Closes a device's session. If it's the current device, the caller must
  /// also sign the app out locally — this only revokes it server-side.
  Future<void> revokeSession(String sessionId);

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

  /// Unread badge for [folder]; implementations may prefer a server count.
  int unreadCount(MailFolder folder) =>
      getEmailsInFolder(folder).where((e) => !e.isRead).length;

  /// Fetches/appends the next page of emails for [folder].
  ///
  /// Used for infinite scrolling; should never duplicate previously returned
  /// emails and must keep existing entries intact.
  Future<List<Email>> loadMoreEmails(MailFolder folder);

  /// Re-syncs [folder] from the source without touching the existing page.
  ///
  /// Pull-to-refresh must never duplicate already-loaded mails nor change
  /// read/star/pin/folder state; it only simulates the network round-trip and
  /// notifies listeners so the UI re-reads the current snapshot.
  Future<void> refreshEmails(MailFolder folder);

  /// Triggers a server-side sync of [folder] before the next [refreshEmails].
  ///
  /// Queues a sync job on the backend (no completion notification).
  /// Failures (e.g. a full sync queue) are for the caller to swallow — the
  /// refresh that follows still shows the current snapshot.
  Future<void> syncFolder(MailFolder folder);

  Future<Email?> getEmail(String id);

  /// Downloads one attachment's raw bytes for sharing/saving.
  ///
  /// Streams `GET /api/mails/{mailId}/attachments/{attachmentId}` (404 when
  /// the attachment is gone). Attachments picked locally and not yet
  /// uploaded carry no server id — those return the bytes already held.
  Future<Uint8List> downloadAttachment(String mailId, Attachment attachment);

  /// Every mail belonging to the same conversation, oldest first.
  /// Grouped by [threadId] — never by subject/account, which can coincide
  /// across unrelated conversations.
  ///
  /// This is the synchronously available snapshot (in-memory cache). Remote
  /// conversations load through [fetchThreadEmails].
  List<Email> getThreadEmails(String threadId);

  /// Message count of a conversation as known by the backend, which can be
  /// larger than what is loaded locally (e.g. replies still in Sent).
  int serverThreadSize(String threadId) => 0;

  /// Asynchronously loads the full conversation for [threadId], oldest
  /// first, with complete message bodies.
  ///
  /// Fetches the conversation and then each message's full detail. Callers
  /// must treat a failure as "enrichment unavailable" and keep whatever
  /// mail they already show — never blank the screen because of it.
  Future<List<Email>> fetchThreadEmails(String threadId);

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
    String? threadId,
    String? inReplyToId,
  });

  /// Creates a new draft, or — when [draftId] is given — updates the
  /// existing draft in place instead of creating a duplicate.
  ///
  /// The backend may assign a NEW id on update (`PUT /drafts/{id}` returns a
  /// fresh `mailId`); the returned draft carries the id callers must use
  /// from then on.
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? draftId,
  });

  /// Deletes a draft. Unknown ids are ignored.
  Future<void> deleteDraft(String draftId);

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

  /// Creates a new label. Throws [ArgumentError] (Turkish message) when the
  /// trimmed name is empty or duplicates an existing name case-insensitively.
  Future<MailLabel> createLabel({required String name, required Color color});

  /// Renames and/or recolors an existing label.
  ///
  /// The label [id] is preserved so mails keep pointing at it. Allowed to keep
  /// its current name/color. Throws [ArgumentError] for an empty name or a
  /// duplicate (case-insensitive, trimmed) name held by another label.
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  });

  /// Deletes a label and strips its id from every mail that carried it. The
  /// mails themselves are untouched. Unknown ids are ignored.
  Future<void> deleteLabel(String labelId);

  Future<void> addLabelsToEmails(List<String> emailIds, List<String> labelIds);

  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  );

  /// Aggregates isReplied/isForwarded across every message sharing
  /// [representative]'s thread, so a thread's single list row reflects the
  /// whole conversation instead of only whichever message happens to
  /// represent it (the newest, which may not be the one the user actually
  /// replied to or forwarded).
  Email threadStatusOf(Email representative) {
    if (representative.threadId.isEmpty) return representative;
    final members = getThreadEmails(representative.threadId);
    if (members.isEmpty) return representative;
    final replied =
        representative.isReplied || members.any((m) => m.isReplied);
    final forwarded =
        representative.isForwarded || members.any((m) => m.isForwarded);
    if (replied == representative.isReplied &&
        forwarded == representative.isForwarded) {
      return representative;
    }
    return representative.copyWith(isReplied: replied, isForwarded: forwarded);
  }

  // --- Search -------------------------------------------------------

  /// Conversations matching a client-side text [query] and an optional label
  /// filter, one representative row per conversation, newest first.
  ///
  /// The text query and the label filter are AND-ed at the message level: a
  /// conversation is eligible when any of its messages matches both. The
  /// returned row is the newest message in the conversation that does, so
  /// opening it still reveals the whole thread via [getThreadEmails]. Empty
  /// [query] matches everything; `labelId == null` means no label
  /// restriction. Spans every account, regardless of the active mailbox.
  List<Email> searchEmails({String query = '', String? labelId}) {
    final seen = <String>{};
    final results = <Email>[];
    bool matches(Email e) =>
        e.matchesQuery(query) &&
        (labelId == null || e.labelIds.contains(labelId));

    for (final email in getAllEmails()) {
      if (email.threadId.isEmpty) {
        if (matches(email)) results.add(email);
        continue;
      }
      if (!seen.add(email.threadId)) continue;
      final candidates = getThreadEmails(email.threadId).where(matches).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (candidates.isNotEmpty) results.add(threadStatusOf(candidates.first));
    }
    return results;
  }
}
