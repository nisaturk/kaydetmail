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
    this.unreadCount,
    this.totalCount,
  });

  final String accountId;
  final String folderId;
  final String name;

  /// Full IMAP path (e.g. `Projeler/Arşiv`), used to show hierarchy without
  /// the app modeling a real tree.
  final String fullName;

  /// Whether the backend already includes this folder in its periodic
  /// background sync (only Inbox/Sent do by default) — custom folders
  /// generally don't, so the UI offers a manual "şimdi eşitle" action.
  final bool isSyncEnabled;

  final int? unreadCount;
  final int? totalCount;
}
