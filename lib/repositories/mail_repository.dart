import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/compose_prefill.dart';
import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_custom_folder.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_session.dart';
import '../models/manual_contact.dart';
import '../models/scheduled_send.dart';

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

/// The server confirmed that SMTP delivery never started; resending the
/// identical message with the same idempotency key is safe.
class SendBeforeDeliveryException implements Exception {
  const SendBeforeDeliveryException();
}

/// The single interface the UI depends on.
///
/// `ApiMailRepository` is the only implementation; `AppConfig.mailRepository`
/// is the shared singleton screens read — they never branch on which
/// implementation is active. This class extends [ChangeNotifier] so screens
/// can rebuild whenever the underlying store changes.
abstract class MailRepository extends ChangeNotifier {
  /// Maximum number of mails that can be pinned at the same time, enforced
  /// per account (each connected account gets its own 3 slots) — matches
  /// the backend's per-account cap.
  ///
  /// Pinning beyond this is ignored (and the UI explains it in Turkish).
  /// Unpinning frees a slot again.
  static const int maxPinnedMails = 3;

  /// Master switch for the "Yanıt bekliyor"/"Yanıtlanmadı" nudge (badge +
  /// Sent-folder stale sort) — off for now per product decision, without
  /// deleting the feature: flip back to `true` to re-enable everywhere,
  /// see `MailListItem._needsReply` and `ApiMailRepository._isStaleUnanswered`.
  static const bool unansweredReminderEnabled = false;

  /// Age past which an Inbox mail with no reply, or a Sent mail with no
  /// reply received, earns the "Yanıt bekliyor"/"Yanıtlanmadı" nudge — see
  /// `MailListItem._needsReply` and `ApiMailRepository`'s Sent-folder sort.
  static const Duration unansweredReminderThreshold = Duration(days: 3);

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
  /// [logout] or [unregisterDevice].
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  });

  /// Removes this device's push registration (e.g. the user turned
  /// notifications off in Settings). Safe to call when nothing is
  /// registered — a no-op then. Best-effort: a network failure is
  /// swallowed since the server registration expires on its own.
  Future<void> unregisterDevice();

  /// Email address of the currently signed-in user.
  String get currentUser;

  /// Whether a session is active. False before login / after logout.
  bool get isLoggedIn;

  /// True when the last attempt to reach the backend for this account's
  /// mailbox failed and the UI is showing a cached (possibly stale)
  /// snapshot instead. Always false for implementations without a cache.
  bool get isOffline => false;

  /// Mail ids whose offline read/unread mutation could not be replayed
  /// after reconnecting — the mailbox changed underneath it (stale UID) or
  /// the mail no longer exists, so replaying it blind risked landing on
  /// the wrong message. Empty for implementations without an offline
  /// mutation queue. See [markAsRead]/[markAsUnread].
  List<String> get offlineMutationConflicts => const [];

  /// Acknowledges one entry from [offlineMutationConflicts] (e.g. after
  /// showing it to the user) so it isn't surfaced again.
  void dismissMutationConflict(String mailId) {}

  /// Sending accounts for the Compose "Kimden" picker.
  List<MailAccount> get accounts;

  /// Sets or clears (`null`/blank) [accountId]'s signature, synced to the
  /// backend so every device signed into that account sees it. Throws
  /// [ArgumentError] for an unknown accountId.
  Future<void> setSignature(String accountId, String? signature) async {}

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
    MailServerSettings? serverSettings,
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

  /// Every mail in the active mailbox scope, regardless of folder.
  ///
  /// Unlike [getAllEmails], this narrows to [activeAccountId] when one is
  /// selected. Folder UI uses this for scope-local thread aggregation.
  List<Email> getScopedEmails();

  /// Unread badge for [folder]; implementations may prefer a server count.
  int unreadCount(MailFolder folder) =>
      getEmailsInFolder(folder).where((e) => !e.isRead).length;

  /// Fetches/appends the next page of emails for [folder].
  ///
  /// Used for infinite scrolling; should never duplicate previously returned
  /// emails and must keep existing entries intact.
  Future<List<Email>> loadMoreEmails(MailFolder folder);

  /// Whether at least one account in the active mailbox scope has another
  /// page for [folder].
  bool hasMoreEmails(MailFolder folder);

  /// Re-fetches [folder] after a completed server sync without changing the
  /// existing page until the network responds.
  Future<void> refreshEmails(MailFolder folder);

  /// Waits for the server's sync job to succeed for every account in scope.
  /// A failed, timed-out or unavailable job throws; the caller must not
  /// report the current cached snapshot as freshly synchronized.
  Future<void> syncFolder(MailFolder folder);

  /// Timestamp of the most recent successful sync for [folder] in the
  /// active mailbox scope, or null if it hasn't synced yet this session.
  /// Powers the "son senkronizasyon" hint on empty/error/offline states.
  DateTime? lastSyncedAt(MailFolder folder) => null;

  Future<Email?> getEmail(String id);

  /// Backend-computed reply/reply-all/forward context: recipients,
  /// subject and threading headers computed server-side — the UI must
  /// never re-derive recipients/subject itself (Reply-To vs. From
  /// precedence, Reply-All self-exclusion, `In-Reply-To`/`References`
  /// chains all live in `ComposeContextService` on the backend). [mode]
  /// is one of `'reply'`, `'reply-all'`, `'forward'`. See docs-dev spec §4.
  ///
  /// Default throws — only meaningful for [ApiMailRepository]; other
  /// implementations/test doubles that never trigger reply/forward don't
  /// need to override it.
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String mode) =>
      throw UnimplementedError('getComposePrefill');

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
    // HTML alternative to [body], sent alongside it (multipart/alternative)
    // when the user actually used compose's formatting toolbar. Null sends
    // plain text only — see `_ComposeScreenState._bodyHtmlFor`.
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? idempotencyKey,
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
    String? bodyHtml,
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

  /// Permanently deletes mails that are in Trash or Spam — expunged on the
  /// mail server, not recoverable. Mails that succeed leave every folder;
  /// throws when any id could not be deleted (e.g. it isn't in Trash/Spam).
  Future<void> deletePermanently(List<String> ids);

  Future<void> moveToFolder(List<String> ids, MailFolder folder);

  Future<void> markAsRead(List<String> ids);

  Future<void> markAsUnread(List<String> ids);

  Future<void> setPinned(List<String> ids, bool pinned);

  Future<void> setStarred(List<String> ids, bool starred);

  Future<void> markAsReplied(List<String> ids);

  Future<void> markAsForwarded(List<String> ids);

  // --- Labels -------------------------------------------------------

  List<MailLabel> getLabels();

  /// Labels owned by one account. Label ids are account-local and must never
  /// be applied to mail belonging to another account.
  List<MailLabel> getLabelsForAccount(String accountId);

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

  // --- Manually-added contacts ---------------------------------------

  /// From every connected account, unified — same shape as [getLabels].
  List<ManualContact> getManualContacts();

  /// Contacts owned by one account. Contact ids are account-local and must
  /// never be edited/deleted through another account's session.
  List<ManualContact> getManualContactsForAccount(String accountId);

  /// Adds a contact to the primary/active account. Throws [ArgumentError]
  /// (Turkish message) for an invalid or already-saved (case-insensitive)
  /// email.
  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
  });

  /// Edits a contact's email/display name. Same validation as
  /// [addManualContact].
  Future<void> updateManualContact({
    required String id,
    required String email,
    String? displayName,
  });

  /// Removes a contact. Unknown ids are ignored.
  Future<void> deleteManualContact(String id);

  /// Aggregates isReplied/isForwarded across every message sharing
  /// [representative]'s thread, so a thread's single list row reflects the
  /// whole conversation instead of only whichever message happens to
  /// represent it (the newest, which may not be the one the user actually
  /// replied to or forwarded).
  Email threadStatusOf(Email representative) {
    if (representative.threadId.isEmpty) return representative;
    final members = getThreadEmails(representative.threadId);
    if (members.isEmpty) return representative;
    final replied = representative.isReplied || members.any((m) => m.isReplied);
    final forwarded =
        representative.isForwarded || members.any((m) => m.isForwarded);
    if (replied == representative.isReplied &&
        forwarded == representative.isForwarded) {
      return representative;
    }
    return representative.copyWith(isReplied: replied, isForwarded: forwarded);
  }

  // --- Search -------------------------------------------------------

  /// Searches the complete server-side corpus across every connected account,
  /// independent of [activeAccountId]. All filters beyond [query] mirror
  /// `GET /api/search` and are optional/AND-ed; `hasAttachment` is singular
  /// to match that endpoint's query parameter name.
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
  });

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

  // --- Snooze (client-side only; see LocalMailFlagsStore) -----------

  /// Hides mail from its normal folder view until [until] (UTC), when it
  /// reappears where it already lives — same independence as pin/star.
  /// `until: null` clears the snooze immediately. Never synced to the
  /// backend or to other devices signed into the same account.
  Future<void> setSnoozed(List<String> ids, DateTime? until);

  /// The snooze deadline for [mailId], or null when it isn't snoozed (or
  /// the snooze already elapsed).
  DateTime? snoozedUntilOf(String mailId) => null;

  // --- Scheduled send -------------------------------------------------

  /// Queues [sendEmail]'s fields to send at [sendAt] (UTC) instead of now.
  /// The backend owns the clock — this fires even if the app is closed.
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
  });

  /// Cancels a still-[ScheduledSendStatus.pending] scheduled send. Throws
  /// if it already sent.
  Future<void> cancelScheduledSend(String id);

  /// Current snapshot of every scheduled send in the active mailbox scope,
  /// soonest first. Populated by [refreshScheduledSends].
  List<ScheduledSend> getScheduledSends() => const [];

  /// Re-fetches the scheduled-send list from the backend.
  Future<void> refreshScheduledSends() async {}

  // --- Custom folders -------------------------------------------------

  /// Non-standard IMAP folders across every account in the active mailbox
  /// scope — distinct from [MailFolder]'s fixed set and from virtual
  /// groupings like starred/pinned. Populated by [refreshCustomFolders].
  List<MailCustomFolder> getCustomFolders() => const [];

  /// Re-fetches the custom folder list for every account in scope.
  Future<void> refreshCustomFolders() async {}

  /// One page of mail from one custom folder, newest first. Independent of
  /// the [MailFolder]-keyed paging used elsewhere — custom folders are
  /// browsed directly by (accountId, folderId), not through a logical
  /// folder. Throws [ArgumentError] for an unknown accountId.
  Future<List<Email>> getCustomFolderMails({
    required String accountId,
    required String folderId,
  }) async => const [];

  /// Whether another page exists for [folderId] after the last
  /// [getCustomFolderMails] call.
  bool hasMoreCustomFolderMails(String accountId, String folderId) => false;

  /// Loads the next page into the same folder's cache; returns the full
  /// accumulated list so far, like [getCustomFolderMails].
  Future<List<Email>> loadMoreCustomFolderMails({
    required String accountId,
    required String folderId,
  }) async => const [];

  /// Requests a server sync of one custom folder and waits for it to
  /// finish — same job-based contract as [syncFolder]. Callers must
  /// re-fetch with [getCustomFolderMails] afterwards.
  Future<void> syncCustomFolder({
    required String accountId,
    required String folderId,
  }) async {}
}
