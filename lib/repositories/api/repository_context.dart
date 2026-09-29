import '../../models/email.dart';
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
}
