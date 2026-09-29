import '../../models/email.dart';
import 'account_session.dart';

/// Every connected account's [AccountSession], in connection order, plus the
/// active-account scope, and the lookups the repository modules share.
///
/// `activeAccountId == null` is the unified mailbox: reads fan out over every
/// session and writes route to whichever session owns the ids involved.
class SessionRegistry {
  /// Insertion-ordered: this is also the order accounts restore in at launch.
  final Map<String, AccountSession> sessions = {};

  String? activeAccountId;

  /// Sessions the public read/write methods operate on: just the active one
  /// when scoped, every connected session when unified.
  Iterable<AccountSession> get scoped {
    final id = activeAccountId;
    if (id == null) return sessions.values;
    final s = sessions[id];
    return s == null ? const [] : [s];
  }

  /// The session bulk actions default to when nothing else identifies one:
  /// the active account when scoped, otherwise the first connected account.
  /// Throws if nothing is connected — callers only reach this while logged in.
  AccountSession get primary {
    final active = activeAccountId;
    if (active != null) {
      final s = sessions[active];
      if (s != null) return s;
    }
    return sessions.values.first;
  }

  /// The session of [accountId]; throws [ArgumentError] when unknown.
  AccountSession forAccount(String accountId) {
    final session = sessions[accountId];
    if (session == null) {
      throw ArgumentError('Unknown account: $accountId');
    }
    return session;
  }

  /// The session that currently caches a mail with [id], if any.
  AccountSession? owning(String id) {
    for (final s in sessions.values) {
      for (final list in s.emails.values) {
        if (list.any((e) => e.id == id)) return s;
      }
      for (final list in s.customFolderEmails.values) {
        if (list.any((e) => e.id == id)) return s;
      }
    }
    return null;
  }

  /// The session that currently caches any message of [threadId], if any.
  AccountSession? forThread(String threadId) {
    for (final s in sessions.values) {
      if (s.emails.values.any(
        (list) => list.any((Email e) => e.threadId == threadId),
      )) {
        return s;
      }
    }
    return null;
  }

  /// The session that owns label [labelId], if any.
  AccountSession? forLabel(String labelId) {
    for (final s in sessions.values) {
      if (s.labels.any((l) => l.id == labelId)) return s;
    }
    return null;
  }

  /// Splits a mixed-account id list by which session actually caches each id.
  /// Unknown ids (not cached anywhere) are dropped — bulk endpoints only ever
  /// act on mail the UI already showed the user.
  Map<AccountSession, List<String>> groupByOwner(List<String> ids) {
    final grouped = <AccountSession, List<String>>{};
    for (final id in ids) {
      final session = owning(id);
      if (session == null) continue;
      grouped.putIfAbsent(session, () => <String>[]).add(id);
    }
    return grouped;
  }

  /// The session a compose action should send/save from: an explicit account
  /// id first, then the picked sender address, otherwise [primary].
  AccountSession forCompose({String? from, String? fromAccountId}) {
    if (fromAccountId != null) {
      final s = sessions[fromAccountId];
      if (s != null) return s;
    }
    if (from != null) {
      for (final s in sessions.values) {
        if (s.account.email == from) return s;
      }
    }
    return primary;
  }
}
