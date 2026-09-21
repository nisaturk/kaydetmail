import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';

/// Expands representative row ids to every message id in their conversations.
///
/// A list row stands for a whole thread, so swipe/bulk operations must affect
/// every member — never just the representative message.
List<String> expandThreadIds(
  MailRepository repo,
  Iterable<String> representativeIds,
) {
  final byId = {for (final email in repo.getAllEmails()) email.id: email};
  final out = <String>[];
  final seen = <String>{};
  for (final repId in representativeIds) {
    final rep = byId[repId];
    final members = rep == null
        ? const <Email>[]
        : rep.threadId.isEmpty
        ? [rep]
        : repo.getThreadEmails(rep.threadId);
    for (final member in members) {
      if (seen.add(member.id)) out.add(member.id);
    }
  }
  return out;
}

/// Previous folder per message id, captured before a move so one Undo can
/// restore every affected message to its exact original folder.
Map<String, MailFolder> previousFoldersOf(
  MailRepository repo,
  Iterable<String> ids,
) {
  final byId = {for (final email in repo.getAllEmails()) email.id: email};
  return {
    for (final id in ids)
      if (byId[id] != null) id: byId[id]!.folder,
  };
}

/// Restores every message to its previous folder through the repository
/// abstraction — the UI never assumes a specific restore endpoint.
Future<void> restorePreviousFolders(
  MailRepository repo,
  Map<String, MailFolder> previous,
) {
  return Future.wait(
    previous.entries.map((e) => repo.moveToFolder([e.key], e.value)),
  );
}
