import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../services/local_mail_flags_store.dart';
import '../../services/mail_cache.dart';
import 'account_session.dart';
import 'session_registry.dart';

/// What the repository modules need from the repository that hosts them.
/// Keeps the modules free of a dependency on `ApiMailRepository` itself:
/// they share the session registry, the device cache and a handful of
/// cross-cutting helpers (change notification, offline detection, optimistic
/// mail updates) through this interface.
abstract class RepositoryContext {
  SessionRegistry get registry;

  /// The encrypted on-device cache, when one is open.
  MailCache? get cache;

  /// Rebuilds views and notifies listeners.
  void notify();

  /// Whether [error] means "no path to the server" (queue and retry later)
  /// rather than a definite server answer.
  bool isOfflineFailure(Object error);

  /// Flags [session] as offline and starts its reconnect probing.
  void markOffline(AccountSession session);

  /// Optimistically rewrites the cached mails [ids] of [session] with
  /// [update] (all folder buckets) and refreshes derived views.
  void replaceMany(
    AccountSession session,
    List<String> ids,
    Email Function(Email) update,
  );

  /// Refreshes the server unread counters of [session] in the background.
  void refreshCounts(AccountSession session);

  /// Re-evaluates the soonest snooze deadline the expiry timer watches.
  void recomputeSnoozeDeadline();

  /// Backend-first, cache-fallback loaders used when replay re-reads state.
  Future<Set<String>> loadPinnedIds(
    AccountSession session,
    LocalMailFlagsStore store,
  );
  Future<Map<String, int>> loadSnoozedUntil(
    AccountSession session,
    LocalMailFlagsStore store,
  );
  Future<void> loadManualContacts(
    AccountSession session,
    LocalMailFlagsStore store,
  );

  /// Re-derives the label ids stamped on [ids] from the session's label map.
  void restampLabels(AccountSession session, Iterable<String> ids);

  /// Writes the session's manual contacts to the device cache.
  Future<void> persistContacts(AccountSession session);

  /// Drops the memoised folder views so the next read rebuilds them.
  void touch();

  /// Re-fetches the first page of [folder] for [session].
  Future<void> refreshFolderMail(AccountSession session, MailFolder folder);

  /// Removes mails [ids] from every cached bucket of [session].
  void removeMany(AccountSession session, Iterable<String> ids);

  /// Remembers where mails [ids] sit so a failed server call can put them back.
  Map<String, MailLocationSnapshot> snapshotMailLocations(
    AccountSession session,
    Iterable<String> ids,
  );

  void restoreMailLocations(
    AccountSession session,
    Map<String, MailLocationSnapshot> snapshots,
  );
}

/// Where one cached mail sat before an optimistic change: its position in
/// each logical and custom-folder bucket.
typedef MailLocationSnapshot = ({
  Map<MailFolder, (Email, int)> folders,
  Map<String, (Email, int)> customFolders,
});
