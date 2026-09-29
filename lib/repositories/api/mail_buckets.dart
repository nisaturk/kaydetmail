import 'dart:math';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import 'account_session.dart';
import 'repository_context.dart';

/// In-memory mail buckets of a session: optimistic edits (flags, moves,
/// removals) and the snapshots that let a rejected server call put mail back
/// exactly where it was. [_touch] invalidates the repository's memoised
/// folder views after every change.
class MailBuckets {
  MailBuckets(this._touch);

  final void Function() _touch;

  /// Applies [update] in place to every cached mail in [ids] within
  /// [session], wherever its bucket, without changing which folder bucket it
  /// lives in.
  void replaceMany(
    AccountSession session,
    Iterable<String> ids,
    Email Function(Email) update,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    for (final folder in session.emails.keys.toList()) {
      final list = session.emails[folder]!;
      session.emails[folder] = [
        for (final email in list)
          idSet.contains(email.id) ? update(email) : email,
      ];
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          idSet.contains(email.id) ? update(email) : email,
      ];
    }
  }

  /// Re-derives every loaded mail's flags (backend-backed pin/labels,
  /// IMAP-backed star and local replied/forwarded) from [session]'s sets.
  /// Used instead of [replaceMany] when a change can affect mail beyond
  /// the ids the caller touched directly — e.g. marking one message replied
  /// also marks every other loaded message in its thread.
  void restampFlags(AccountSession session) {
    _touch();
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          session.stampLocalFlags(email),
      ];
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          session.stampLocalFlags(email),
      ];
    }
  }

  /// Moves every cached mail in [ids] into [targetFolder]'s bucket within
  /// [session], stamping the new folder on each and dropping it from
  /// wherever it used to live. Mails not currently cached are ignored.
  void moveMany(
    AccountSession session,
    Iterable<String> ids,
    MailFolder targetFolder,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    final moved = <Email>[
      for (final list in session.customFolderEmails.values)
        for (final email in list)
          if (idSet.contains(email.id)) email.copyWith(folder: targetFolder),
    ];
    session.dropFromCustomFolderMails(idSet);
    for (final folder in session.emails.keys.toList()) {
      if (folder == targetFolder) continue;
      final list = session.emails[folder]!;
      final keep = <Email>[];
      for (final email in list) {
        if (idSet.contains(email.id)) {
          moved.add(email.copyWith(folder: targetFolder));
        } else {
          keep.add(email);
        }
      }
      session.emails[folder] = keep;
    }
    if (moved.isNotEmpty) {
      session.emails
          .putIfAbsent(targetFolder, () => <Email>[])
          .insertAll(0, moved);
    }
  }

  /// Ids from [ids] whose cached copy currently lives in Trash or Spam —
  /// the only two folders `restore` is valid from.
  List<String> idsInTrashOrSpam(AccountSession session, Iterable<String> ids) {
    final trashed = {
      for (final e in session.emails[MailFolder.trash] ?? const []) e.id,
    };
    final spammed = {
      for (final e in session.emails[MailFolder.spam] ?? const []) e.id,
    };
    return ids
        .where((id) => trashed.contains(id) || spammed.contains(id))
        .toList();
  }

  /// Captures exact local bucket positions so rejected requests can be rolled
  /// back without replacing unrelated cached mail.
  Map<String, MailLocationSnapshot> snapshotMailLocations(
    AccountSession session,
    Iterable<String> ids,
  ) {
    final snapshots = {
      for (final id in ids)
        id: (
          folders: <MailFolder, (Email, int)>{},
          customFolders: <String, (Email, int)>{},
        ),
    };
    for (final entry in session.emails.entries) {
      for (var index = 0; index < entry.value.length; index++) {
        final email = entry.value[index];
        final snapshot = snapshots[email.id];
        if (snapshot != null) {
          snapshot.folders[entry.key] = (email, index);
        }
      }
    }
    for (final entry in session.customFolderEmails.entries) {
      for (var index = 0; index < entry.value.length; index++) {
        final email = entry.value[index];
        final snapshot = snapshots[email.id];
        if (snapshot != null) {
          snapshot.customFolders[entry.key] = (email, index);
        }
      }
    }
    return snapshots;
  }

  Map<String, MailLocationSnapshot> selectMailLocations(
    Map<String, MailLocationSnapshot> snapshots,
    Iterable<String> ids,
  ) {
    final selected = <String, MailLocationSnapshot>{};
    for (final id in ids) {
      final snapshot = snapshots[id];
      if (snapshot != null) selected[id] = snapshot;
    }
    return selected;
  }

  void restoreMailLocations(
    AccountSession session,
    Map<String, MailLocationSnapshot> snapshots,
  ) {
    if (snapshots.isEmpty) return;
    final ids = snapshots.keys.toSet();
    _touch();
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          if (!ids.contains(email.id)) email,
      ];
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          if (!ids.contains(email.id)) email,
      ];
    }
    final folderLocations = <MailFolder, List<(Email, int)>>{};
    final customFolderLocations = <String, List<(Email, int)>>{};
    for (final entry in snapshots.entries) {
      for (final location in entry.value.folders.entries) {
        folderLocations
            .putIfAbsent(location.key, () => <(Email, int)>[])
            .add(location.value);
      }
      for (final location in entry.value.customFolders.entries) {
        customFolderLocations
            .putIfAbsent(location.key, () => <(Email, int)>[])
            .add(location.value);
      }
      final originalEmail =
          entry.value.folders.values.firstOrNull?.$1 ??
          entry.value.customFolders.values.firstOrNull?.$1;
      if (originalEmail != null) {
        if (originalEmail.isStarred) {
          session.starredIds.add(originalEmail.id);
        } else {
          session.starredIds.remove(originalEmail.id);
        }
      }
    }
    for (final entry in folderLocations.entries) {
      entry.value.sort((a, b) => a.$2.compareTo(b.$2));
      final list = session.emails.putIfAbsent(entry.key, () => <Email>[]);
      for (final (email, index) in entry.value) {
        list.insert(min(index, list.length), email);
      }
    }
    for (final entry in customFolderLocations.entries) {
      entry.value.sort((a, b) => a.$2.compareTo(b.$2));
      final list = session.customFolderEmails.putIfAbsent(
        entry.key,
        () => <Email>[],
      );
      for (final (email, index) in entry.value) {
        list.insert(min(index, list.length), email);
      }
    }
  }

  /// Drops every cached mail in [ids] from whichever bucket holds it.
  void removeMany(AccountSession session, Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    session.dropFromCustomFolderMails(idSet);
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          if (!idSet.contains(email.id)) email,
      ];
    }
  }
}
