import '../models/mail_folder_info.dart';
import '../l10n/l10n.dart';

/// What the backend allows for a folder, decided client-side so the UI can
/// hide/disable actions and explain instead of failing with a server error.
///
/// Mirrors the backend contract: only `Custom` folders can be renamed, moved
/// or deleted (standard ones are `mail_folder_protected`); deleting requires
/// no children and no mail (`mail_folder_has_children` / `mail_folder_not_empty`);
/// only Sent/Drafts/Trash/Junk can be assigned to a folder as a role.
class FolderRules {
  const FolderRules._();

  /// Roles a user may assign to a folder (backend `PUT /folders/{id}/role`).
  static const assignableRoles = [
    FolderKind.sent,
    FolderKind.drafts,
    FolderKind.trash,
    FolderKind.junk,
  ];

  static bool canRename(MailFolderInfo folder) =>
      folder.kind == FolderKind.custom;

  static bool canMove(MailFolderInfo folder) =>
      folder.kind == FolderKind.custom;

  static bool canDelete(MailFolderInfo folder) =>
      folder.kind == FolderKind.custom;

  /// Any folder that is not INBOX/Archive-detected may take a role; a folder
  /// already holding a user role can be reset to automatic detection.
  static bool canAssignRole(MailFolderInfo folder) =>
      folder.kind == FolderKind.custom || folder.hasUserRole;

  /// Sub-folders can be created under any folder of the account.
  static bool canHaveChildren(MailFolderInfo folder) => true;

  /// Why [folder] cannot be deleted right now, or null when it can. The
  /// server enforces the same rules; this only saves the round trip.
  static String? deleteBlocker(
    MailFolderInfo folder,
    Iterable<MailFolderInfo> siblingsOfAccount,
  ) {
    if (!canDelete(folder)) return l10nNow.standardFoldersCantBeDeleted;
    if (siblingsOfAccount.any((f) => f.parentFolderId == folder.folderId)) {
      return l10nNow.deleteOrMoveTheSubfolders;
    }
    if ((folder.totalCount ?? 0) > 0) {
      return l10nNow.theFolderContainsEmailsMove;
    }
    return null;
  }

  /// Validates a new folder name. [siblings] are the folders that would share
  /// its parent (same-level names must be unique, case-insensitively, like on
  /// the server). [self] is excluded when renaming. Returns a Turkish message
  /// or null when the name is acceptable.
  static String? validateName(
    String name, {
    String? delimiter,
    Iterable<MailFolderInfo> siblings = const [],
    MailFolderInfo? self,
  }) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return l10nNow.folderNameCantBeEmpty;
    if (trimmed.length > 200 || trimmed.runes.any((c) => c < 32 || c == 127)) {
      return l10nNow.theFolderNameIsInvalid;
    }
    // IMAP wildcards are legal in some servers' names but break LIST/LSUB
    // patterns; Dovecot/cPanel also treat the hierarchy delimiter as a path
    // separator, which would silently create a nested folder.
    if (trimmed.contains('*') || trimmed.contains('%')) {
      return l10nNow.folderNameCantContainOr;
    }
    if (delimiter != null &&
        delimiter.isNotEmpty &&
        trimmed.contains(delimiter)) {
      return l10nNow.folderNameCantContain(delimiter);
    }
    if (trimmed == '.' || trimmed == '..') {
      return l10nNow.theFolderNameIsInvalid;
    }
    final lower = trimmed.toLowerCase();
    if (lower == 'inbox') return l10nNow.thisNameIsReservedChoose;
    final clash = siblings.any(
      (f) =>
          f.folderId != self?.folderId && f.name.trim().toLowerCase() == lower,
    );
    if (clash) return l10nNow.aFolderWithThisName;
    return null;
  }
}
