import 'package:flutter/foundation.dart';

import '../../models/account_notification_settings.dart';
import '../../models/account_sync_scope.dart';
import '../../models/folder_sync_status.dart';
import '../../models/mail_account.dart';
import '../../services/api_mail_service.dart';
import 'account_session.dart';
import 'session_registry.dart';

/// Per-account server settings: storage quota, sync status/scope and
/// notification preferences.
class AccountSettingsModule {
  AccountSettingsModule(this._registry, this._notify);

  final SessionRegistry _registry;
  final VoidCallback _notify;

  Future<void> refreshQuota(String accountId) async {
    final session = _registry.sessions[accountId];
    if (session != null) await refreshSessionQuota(session);
  }

  /// Loads [session]'s storage quota. `null` from the backend means the
  /// server has no QUOTA support (or refused it), which hides the usage row.
  /// Transport failures keep the last known value so going offline doesn't
  /// flicker the row; a session closed meanwhile is left untouched.
  Future<void> refreshSessionQuota(AccountSession session) async {
    final AccountQuota? quota;
    try {
      quota = await session.mailService.getQuota();
    } catch (_) {
      return;
    }
    if (!identical(_registry.sessions[session.account.id], session)) return;
    session.account = session.account.copyWith(quota: quota);
    _notify();
  }

  Future<List<FolderSyncStatus>> getSyncStatus(String accountId) async {
    final session = _registry.sessions[accountId];
    if (session == null) return const [];
    return session.mailService.getSyncStatus();
  }

  Future<AccountSyncScope> getSyncScope(String accountId) async {
    final service = _registry.forAccount(accountId).mailService;
    final (scope, folders) = await (
      service.getSyncScope(),
      service.getFolders(),
    ).wait;
    return _composeSyncScope(scope, folders);
  }

  Future<AccountSyncScope> updateSyncScope(
    String accountId,
    FolderSyncScope scope, {
    List<String>? folderIds,
  }) async {
    final service = _registry.forAccount(accountId).mailService;
    final updated = await service.updateSyncScope(
      scope.backendValue,
      folderIds: scope == FolderSyncScope.selectedFolders ? folderIds : null,
    );
    return _composeSyncScope(updated, await service.getFolders());
  }

  Future<AccountNotificationSettings> getNotificationSettings(
    String accountId,
  ) => _registry.forAccount(accountId).mailService.getNotificationSettings();

  Future<AccountNotificationSettings> updateNotificationSettings(
    String accountId,
    AccountNotificationSettings settings,
  ) => _registry
      .forAccount(accountId)
      .mailService
      .updateNotificationSettings(settings);

  static const _syncScopeFolderOrder = [
    'Inbox',
    'Sent',
    'Drafts',
    'Archive',
    'Junk',
    'Trash',
  ];

  AccountSyncScope _composeSyncScope(
    ({String scope, Set<String> syncedFolderIds}) scope,
    List<ApiMailFolder> folders,
  ) {
    int rank(ApiMailFolder f) {
      final index = _syncScopeFolderOrder.indexOf(f.type);
      return index < 0 ? _syncScopeFolderOrder.length : index;
    }

    final available = folders.where((f) => f.isAvailable).toList()
      ..sort((a, b) {
        final byType = rank(a).compareTo(rank(b));
        return byType != 0 ? byType : a.fullName.compareTo(b.fullName);
      });
    return AccountSyncScope(
      scope: FolderSyncScope.fromBackend(scope.scope),
      folders: [
        for (final f in available)
          SyncScopeFolder(
            id: f.id,
            name: f.fullName,
            type: f.type,
            synced: scope.syncedFolderIds.contains(f.id),
          ),
      ],
    );
  }
}
