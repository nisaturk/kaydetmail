import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';

/// The subset of [ids] whose message currently lives in [folder].
///
/// Used when restoring or expunging explicit selections from a physical folder.
List<String> idsInFolder(
  MailRepository repo,
  List<String> ids,
  MailFolder folder,
) {
  final wanted = ids.toSet();
  return [
    for (final email in repo.getAllEmails())
      if (email.folder == folder && wanted.remove(email.id)) email.id,
  ];
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
