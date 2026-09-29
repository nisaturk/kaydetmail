import 'mail_folder.dart';

/// Logical folders a server folder can be assigned to by the user.
const assignableFolderRoles = [
  MailFolder.sent,
  MailFolder.drafts,
  MailFolder.trash,
  MailFolder.spam,
];

/// A server folder whose Sent/Drafts/Trash/Junk role was chosen by the user
/// instead of detected — e.g. cPanel's `INBOX.Sent Items` used as Sent.
class MailFolderRoleAssignment {
  const MailFolderRoleAssignment({
    required this.accountId,
    required this.folderId,
    required this.name,
    required this.fullName,
    required this.role,
  });

  final String accountId;
  final String folderId;
  final String name;
  final String fullName;
  final MailFolder role;
}

/// A non-standard IMAP folder reported by the server for one account —
/// distinct from the fixed [MailFolder] set (`lib/models/mail_folder.dart`)
/// and from virtual groupings like starred/pinned. Folder ids are unique
/// per account, so two accounts' folders sharing a name never collide.
class MailCustomFolder {
  const MailCustomFolder({
    required this.accountId,
    required this.folderId,
    required this.name,
    required this.fullName,
    required this.isSyncEnabled,
    this.parentFolderId,
    this.delimiter,
    this.unreadCount,
    this.totalCount,
  });

  final String accountId;
  final String folderId;
  final String name;

  /// Full IMAP path (e.g. `Projeler/Arşiv`), including any server prefix
  /// such as `INBOX.`; the tree itself is built from [parentFolderId].
  final String fullName;

  /// Whether the backend already includes this folder in its periodic
  /// background sync (only Inbox/Sent do by default) — custom folders
  /// generally don't, so the UI offers a manual "şimdi eşitle" action.
  final bool isSyncEnabled;

  final String? parentFolderId;
  final String? delimiter;
  final int? unreadCount;
  final int? totalCount;
}

class MailCustomFolderNode {
  MailCustomFolderNode(this.folder);

  final MailCustomFolder folder;
  final List<MailCustomFolderNode> children = [];
}

typedef MailCustomFolderRow = ({MailCustomFolder folder, int depth});

List<MailCustomFolderNode> buildCustomFolderTree(
  Iterable<MailCustomFolder> folders, {
  Map<String, List<String>> orderByAccount = const {},
}) {
  final nodes = <(String, String), MailCustomFolderNode>{};
  final byFullName = <(String, String), MailCustomFolderNode>{};
  for (final folder in folders) {
    final node = MailCustomFolderNode(folder);
    nodes[(folder.accountId, folder.folderId)] = node;
    byFullName[(folder.accountId, folder.fullName)] = node;
  }

  MailCustomFolderNode? parentOf(MailCustomFolder folder) {
    final parentId = folder.parentFolderId;
    if (parentId != null) {
      if (parentId == folder.folderId) return null;
      return nodes[(folder.accountId, parentId)];
    }
    final delimiter = folder.delimiter;
    if (delimiter == null || delimiter.isEmpty) return null;
    final cut = folder.fullName.lastIndexOf(delimiter);
    if (cut <= 0) return null;
    final parent =
        byFullName[(folder.accountId, folder.fullName.substring(0, cut))];
    return identical(parent?.folder, folder) ? null : parent;
  }

  final parents = {
    for (final node in nodes.values) node: parentOf(node.folder),
  };
  final roots = <MailCustomFolderNode>[];
  for (final node in nodes.values) {
    final parent = parents[node];
    if (parent == null) {
      roots.add(node);
    } else {
      parent.children.add(node);
    }
  }

  final reachable = <MailCustomFolderNode>{};
  void mark(MailCustomFolderNode node) {
    if (!reachable.add(node)) return;
    node.children.forEach(mark);
  }

  roots.forEach(mark);
  for (final node in nodes.values) {
    if (reachable.contains(node)) continue;
    parents[node]!.children.remove(node);
    roots.add(node);
    mark(node);
  }

  final positions = {
    for (final entry in orderByAccount.entries)
      entry.key: {for (final (index, id) in entry.value.indexed) id: index},
  };

  // Persisted ids sort first in stored order; unknown (new) folders follow
  // alphabetically, so a fresh folder lands at the end of its siblings.
  int compare(MailCustomFolderNode a, MailCustomFolderNode b) {
    final order = positions[a.folder.accountId];
    final aIndex = order?[a.folder.folderId];
    final bIndex = order?[b.folder.folderId];
    if (aIndex != null || bIndex != null) {
      if (aIndex == null) return 1;
      if (bIndex == null) return -1;
      final byOrder = aIndex.compareTo(bIndex);
      if (byOrder != 0) return byOrder;
    }
    final byName = a.folder.name.toLowerCase().compareTo(
      b.folder.name.toLowerCase(),
    );
    return byName != 0 ? byName : a.folder.name.compareTo(b.folder.name);
  }

  void sortAll(List<MailCustomFolderNode> list) {
    list.sort(compare);
    for (final node in list) {
      sortAll(node.children);
    }
  }

  sortAll(roots);
  return roots;
}

List<MailCustomFolderRow> flattenCustomFolderTree(
  Iterable<MailCustomFolder> folders, {
  Map<String, List<String>> orderByAccount = const {},
}) {
  final rows = <MailCustomFolderRow>[];
  void visit(MailCustomFolderNode node, int depth) {
    rows.add((folder: node.folder, depth: depth));
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  for (final root in buildCustomFolderTree(
    folders,
    orderByAccount: orderByAccount,
  )) {
    visit(root, 0);
  }
  return rows;
}

/// Reconciles persisted preorder with current server folders. Removed ids are
/// dropped; new ids follow deterministically in tree/name order.
List<String> reconcileCustomFolderOrder(
  Iterable<MailCustomFolder> folders,
  Iterable<String> persisted,
) {
  final folderList = folders.toList();
  final liveIds = folderList.map((folder) => folder.folderId).toSet();
  final result = <String>[
    for (final id in persisted)
      if (liveIds.remove(id)) id,
  ];
  result.addAll(
    flattenCustomFolderTree(folderList)
        .map((row) => row.folder.folderId)
        .where(liveIds.contains),
  );
  return result;
}

/// Moves [folderId] by [offset] positions among its siblings (children of the
/// same parent, or roots) and returns the account's new persisted preorder.
/// Subtrees travel with their folder. Returns null when the folder is
/// unknown or the move would leave the sibling range.
///
/// [folders] must all belong to one account.
List<String>? moveCustomFolderAmongSiblings(
  Iterable<MailCustomFolder> folders,
  List<String> order,
  String folderId,
  int offset,
) {
  final folderList = folders.toList();
  if (folderList.isEmpty) return null;
  final roots = buildCustomFolderTree(
    folderList,
    orderByAccount: {folderList.first.accountId: order},
  );

  List<MailCustomFolderNode>? siblingsOf(List<MailCustomFolderNode> list) {
    if (list.any((node) => node.folder.folderId == folderId)) return list;
    for (final node in list) {
      final found = siblingsOf(node.children);
      if (found != null) return found;
    }
    return null;
  }

  final siblings = siblingsOf(roots);
  if (siblings == null) return null;
  final from = siblings.indexWhere((node) => node.folder.folderId == folderId);
  final to = from + offset;
  if (to < 0 || to >= siblings.length) return null;
  siblings.insert(to, siblings.removeAt(from));

  final result = <String>[];
  void visit(MailCustomFolderNode node) {
    result.add(node.folder.folderId);
    node.children.forEach(visit);
  }

  roots.forEach(visit);
  return result;
}
