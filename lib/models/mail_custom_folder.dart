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
  Iterable<MailCustomFolder> folders,
) {
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

  int compare(MailCustomFolderNode a, MailCustomFolderNode b) {
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
  Iterable<MailCustomFolder> folders,
) {
  final rows = <MailCustomFolderRow>[];
  void visit(MailCustomFolderNode node, int depth) {
    rows.add((folder: node.folder, depth: depth));
    for (final child in node.children) {
      visit(child, depth + 1);
    }
  }

  for (final root in buildCustomFolderTree(folders)) {
    visit(root, 0);
  }
  return rows;
}
