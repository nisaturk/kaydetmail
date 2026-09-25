import 'folder_sync_status.dart';

enum FolderSyncScope {
  inboxAndSent('InboxAndSent', 'Gelen + Gönderilen'),
  allFolders('AllFolders', 'Tüm klasörler'),
  selectedFolders('SelectedFolders', 'Seçili klasörler');

  const FolderSyncScope(this.backendValue, this.label);

  final String backendValue;
  final String label;

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
