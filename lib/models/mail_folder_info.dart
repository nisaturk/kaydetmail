import 'mail_folder.dart';

/// Server folder kinds as the backend reports them (`folderType`).
enum FolderKind {
  inbox,
  sent,
  drafts,
  trash,
  junk,
  archive,
  custom,
  unknown;

  static FolderKind fromBackend(String value) => switch (value.toLowerCase()) {
    'inbox' => FolderKind.inbox,
    'sent' => FolderKind.sent,
    'drafts' => FolderKind.drafts,
    'trash' => FolderKind.trash,
    'junk' || 'spam' => FolderKind.junk,
    'archive' => FolderKind.archive,
    'custom' => FolderKind.custom,
    _ => FolderKind.unknown,
  };

  /// The app's logical folder for the standard kinds; null for custom.
  MailFolder? get logical => switch (this) {
    FolderKind.inbox => MailFolder.inbox,
    FolderKind.sent => MailFolder.sent,
    FolderKind.drafts => MailFolder.drafts,
    FolderKind.trash => MailFolder.trash,
    FolderKind.junk => MailFolder.spam,
    FolderKind.archive => MailFolder.archive,
    _ => null,
  };

  bool get isStandard => logical != null;
}

/// One available server folder of an account — standard or custom — with
/// everything the folder manager needs. Built by the repository from the
/// backend folder list; the tree is built from [parentFolderId], never from
/// [fullName] (the backend may hold a local parent override).
class MailFolderInfo {
  const MailFolderInfo({
    required this.accountId,
    required this.folderId,
    required this.name,
    required this.fullName,
    required this.kind,
    required this.isSyncEnabled,
    this.parentFolderId,
    this.delimiter,
    this.unreadCount,
    this.totalCount,
    this.roleOverride,
  });

  final String accountId;
  final String folderId;
  final String name;
  final String fullName;
  final FolderKind kind;
  final bool isSyncEnabled;
  final String? parentFolderId;
  final String? delimiter;
  final int? unreadCount;
  final int? totalCount;

  /// Role the user assigned to this (custom-named) folder; null when the role
  /// was detected. [kind] already reflects it.
  final FolderKind? roleOverride;

  bool get isStandard => kind.isStandard;
  bool get hasUserRole => roleOverride != null;
}
