import 'folder_sync_status.dart';
import '../l10n/l10n.dart';

enum FolderSyncScope {
  inboxAndSent('InboxAndSent'),
  allFolders('AllFolders'),
  selectedFolders('SelectedFolders');

  const FolderSyncScope(this.backendValue);

  final String backendValue;

  String get label => switch (this) {
    FolderSyncScope.inboxAndSent => l10nNow.inboxSent,
    FolderSyncScope.allFolders => l10nNow.allFolders,
    FolderSyncScope.selectedFolders => l10nNow.selectedFolders,
  };

  static FolderSyncScope fromBackend(String? value) => values.firstWhere(
    (scope) => scope.backendValue == value,
    orElse: () => FolderSyncScope.inboxAndSent,
  );
}

class SyncScopeFolder {
  const SyncScopeFolder({
    required this.id,
    required this.name,
    required this.type,
    required this.synced,
  });

  final String id;
  final String name;
  final String type;
  final bool synced;

  String get displayName => friendlyFolderName(type, name);
}

class AccountSyncScope {
  const AccountSyncScope({required this.scope, required this.folders});

  final FolderSyncScope scope;
  final List<SyncScopeFolder> folders;
}
