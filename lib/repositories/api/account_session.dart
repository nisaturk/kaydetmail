import 'dart:async';

import '../../models/email.dart';
import '../../models/mail_account.dart';
import '../../models/mail_folder.dart';
import '../../models/mail_label.dart';
import '../../models/mail_signature.dart';
import '../../models/mail_template.dart';
import '../../models/manual_contact.dart';
import '../../models/scheduled_send.dart';
import '../../services/api_auth_service.dart';
import '../../services/api_mail_service.dart';
import '../../services/local_mail_flags_store.dart';

/// Everything one connected mailbox needs to operate independently: its own
/// authenticated HTTP session, its own folder/mail cache, and its own
/// backend-backed pin/snooze/label/contact state plus local reply/forward flags.
/// Multiple accounts hold multiple [AccountSession]s side by side — connecting a
/// second account never touches the first one's tokens, mail, or flags.
class AccountSession {
  AccountSession({
    required this.authService,
    required this.mailService,
    required this.account,
  });

  MailAccount account;
  final ApiAuthService authService;
  final ApiMailService mailService;

  bool offline = false;
  String? deviceId;
  LocalMailFlagsStore? flagsStore;

  /// See [ApiMailRepository.offlineMutationConflicts].
  final Set<String> mutationConflicts = {};

  final Map<MailFolder, String> folderIds = {};
  final Map<String, MailFolder> folderTypeById = {};
  final Map<MailFolder, List<Email>> emails = {};
  final Map<MailFolder, int> pages = {};
  final Map<MailFolder, int> serverUnread = {};
  final Map<MailFolder, bool> hasMore = {};

  /// Set on every successful `_loadMoreFor`/`_refreshEmailsFor` fetch for
  /// the folder — the "son senkronizasyon" hint on empty/error states.
  final Map<MailFolder, DateTime> lastSynced = {};
  final Map<String, int> serverThreadSizes = {};

  Set<String> pinnedIds = {};
  final Set<String> starredIds = {};
  Set<String> repliedFromKaydetMailIds = {};
  Set<String> forwardedFromKaydetMailIds = {};
  Set<String> repliedFromKaydetMailThreadIds = {};
  Set<String> forwardedFromKaydetMailThreadIds = {};

  List<MailLabel> labels = [];
  Map<String, List<String>> labelMap = {};
  List<ManualContact> manualContacts = [];
  List<MailTemplate>? templates;

  /// Cached snooze deadlines (mail id -> epoch millis), fetched from the
  /// backend or read from [LocalMailFlagsStore] while offline. A mail past
  /// its timestamp is treated as not-snoozed everywhere below.
  Map<String, int> snoozedUntil = {};

  /// Scheduled sends known for this account, soonest first. Populated by
  /// [ApiMailRepository.refreshScheduledSends].
  List<ScheduledSend> scheduledSends = [];

  List<MailSignature>? signatures;
  SignatureDefaults? signatureDefaults;
  List<MailIdentity>? identities;

  /// Non-standard IMAP folders reported for this account by the last
  /// [ApiMailRepository.refreshCustomFolders]. Populated on demand, not on
  /// every login, since most accounts never open the custom-folders screen.
  List<ApiMailFolder> customFolders = [];

  /// Every available server folder (standard and custom) from the last
  /// folder fetch — the folder manager's source of truth.
  List<ApiMailFolder> allFolders = [];

  /// Folders whose role the user assigned (see
  /// [ApiMailRepository.setFolderRole]); refreshed with [customFolders].
  List<ApiMailFolder> roleOverrideFolders = [];
  bool folderHierarchyRequested = false;
  final Map<String, List<Email>> customFolderEmails = {};
  final Map<String, int> customFolderPages = {};
  final Map<String, bool> customFolderHasMore = {};

  // Debounced whole-mailbox cache write-behind, mirrored per account so one
  // account's writes never race another's.
  Timer? persistTimer;
  Map<String, Email> persisted = {};

  // Polls the backend every 15s while [offline] until a probe succeeds —
  // see [ApiMailRepository._scheduleReconnectRetry].
  Timer? reconnectTimer;

  /// Maps a raw API folder id back to our logical [MailFolder]. Custom
  /// server folders we don't track locally fall back to inbox.
  MailFolder resolveFolder(String folderId) =>
      folderTypeById[folderId] ?? MailFolder.inbox;

  /// Finds an already-loaded mail by id, regardless of which folder bucket
  /// it currently sits in. Used to resolve a message's threadId when only
  /// its id is known (e.g. [ApiMailRepository.markAsReplied]).
  Email? findLoaded(String id) {
    for (final list in emails.values) {
      for (final email in list) {
        if (email.id == id) return email;
      }
    }
    return null;
  }

  /// Overlays the locally-persisted pin/reply/forward/label flags onto a
  /// mail freshly mapped from the API — the server has no concept of any of
  /// them, so every fetch would otherwise reset them. Also stamps the owning
  /// account: list and conversation responses carry no `accountId`, and
  /// account-local features (labels) resolve through it.
  ///
  /// Reply/forward also check the thread-level sets: the user marks these
  /// by opening a specific message, but every message sharing its thread
  /// should show the icon too, even when that specific message isn't
  /// currently loaded into memory (e.g. it lives in a folder not yet
  /// fetched this session) — see [ApiMailRepository.markAsReplied].
  Email stampLocalFlags(Email email) => email.copyWith(
    accountId: account.id,
    isStarred: email.isStarred || starredIds.contains(email.id),
    isPinned: pinnedIds.contains(email.id),
    repliedFromKaydetMail:
        email.repliedFromKaydetMail ||
        repliedFromKaydetMailIds.contains(email.id) ||
        (email.threadId.isNotEmpty &&
            repliedFromKaydetMailThreadIds.contains(email.threadId)),
    forwardedFromKaydetMail:
        forwardedFromKaydetMailIds.contains(email.id) ||
        (email.threadId.isNotEmpty &&
            forwardedFromKaydetMailThreadIds.contains(email.threadId)),
    labelIds: labelMap[email.id] ?? const [],
  );

  /// Drops the cached mail pages of custom folder [folderId].
  void forgetCustomFolderMails(String folderId) {
    customFolderEmails.remove(folderId);
    customFolderPages.remove(folderId);
    customFolderHasMore.remove(folderId);
  }

  /// Removes mails [ids] from every cached custom-folder bucket.
  void dropFromCustomFolderMails(Set<String> ids) {
    for (final entry in customFolderEmails.entries.toList()) {
      if (entry.value.any((e) => ids.contains(e.id))) {
        customFolderEmails[entry.key] = [
          for (final email in entry.value)
            if (!ids.contains(email.id)) email,
        ];
      }
    }
  }
}
