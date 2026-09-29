import '../models/mail_folder_info.dart';

typedef FolderRow = ({MailFolderInfo folder, int depth});

const _standardOrder = [
  FolderKind.inbox,
  FolderKind.sent,
  FolderKind.drafts,
  FolderKind.archive,
  FolderKind.junk,
  FolderKind.trash,
];

/// Flattens an account's folders into display rows: standard folders first in
/// their fixed order, then custom ones alphabetically, each folder followed by
/// its children (indented). The tree follows `parentFolderId` only — a folder
/// whose parent is missing or would create a cycle is shown at the top level.
List<FolderRow> buildFolderRows(Iterable<MailFolderInfo> folders) {
  final list = folders.toList();
  final byId = {for (final f in list) f.folderId: f};
  final children = <String?, List<MailFolderInfo>>{};
  for (final f in list) {
    var parent = f.parentFolderId;
    if (parent == f.folderId || !byId.containsKey(parent)) parent = null;
    children.putIfAbsent(parent, () => []).add(f);
  }

  int rank(MailFolderInfo f) {
    final i = _standardOrder.indexOf(f.kind);
    return i < 0 ? _standardOrder.length : i;
  }

  int compare(MailFolderInfo a, MailFolderInfo b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.name.compareTo(b.name);
  }

  final rows = <FolderRow>[];
  final seen = <String>{};
  void visit(MailFolderInfo f, int depth) {
    if (!seen.add(f.folderId)) return;
    rows.add((folder: f, depth: depth));
    for (final child in [...?children[f.folderId]]..sort(compare)) {
      visit(child, depth + 1);
    }
  }

  for (final root in [...?children[null]]..sort(compare)) {
    visit(root, 0);
  }
  // Members of a parent cycle are unreachable from any root; surface them.
  for (final f in list..sort(compare)) {
    visit(f, 0);
  }
  return rows;
}

/// Ids of [folderId] and every folder below it.
Set<String> subtreeIds(Iterable<MailFolderInfo> folders, String folderId) {
  final result = <String>{folderId};
  var grew = true;
  while (grew) {
    grew = false;
    for (final f in folders) {
      if (f.parentFolderId != null &&
          result.contains(f.parentFolderId) &&
          result.add(f.folderId)) {
        grew = true;
      }
    }
  }
  return result;
}
