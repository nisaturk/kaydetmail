import '../../models/mail_custom_folder.dart';
import '../../models/mail_folder.dart';
import '../../models/mail_folder_info.dart';
import '../../services/api_mail_service.dart';
import 'account_session.dart';
import 'repository_context.dart';

/// Server folders of every account: the standard-role map (which server
/// folder is Inbox/Sent/…), the custom folder tree, user-assigned roles and
/// folder create/rename/move/delete. Mail *inside* folders (paging, caching,
/// moving mail) stays with the mail machinery of the repository.
class FolderModule {
  FolderModule(this._ctx);

  final RepositoryContext _ctx;

  /// Restores the last-known server-folder-id -> [MailFolder] mapping so
  /// cached mail stays actionable (open, move, sync) even before — or
  /// without ever reaching — a successful [_loadMailbox] this session.
  void hydrateFromCache(AccountSession session) {
    final saved = _ctx.cache?.loadFolders(session.account.id) ?? const {};
    if (saved.isEmpty) return;
    session.folderIds.clear();
    session.folderTypeById.clear();
    for (final entry in saved.entries) {
      if (entry.value == 'custom') continue;
      MailFolder logical;
      try {
        logical = MailFolder.values.byName(entry.value);
      } catch (_) {
        continue;
      }
      session.folderIds[logical] = entry.key;
      session.folderTypeById[entry.key] = logical;
    }
  }

  /// Rebuilds the logical-folder map from the server list. `folderType` is
  /// the effective role, so user overrides (e.g. `INBOX.Sent Items` as Sent)
  /// resolve here without extra handling.
  void applyFolderMap(AccountSession session, List<ApiMailFolder> folders) {
    session.folderIds.clear();
    session.folderTypeById.clear();
    session.serverUnread.clear();
    for (final folder in folders) {
      if (!folder.isAvailable) continue;
      final logical = logicalFolderForType(folder.type);
      if (logical != null) {
        session.folderIds[logical] = folder.id;
        session.folderTypeById[folder.id] = logical;
        final unread = folder.unreadCount;
        if (unread != null) session.serverUnread[logical] = unread;
      }
    }
    _applyCustomFolderLists(session, folders);
  }

  void _applyCustomFolderLists(
    AccountSession session,
    List<ApiMailFolder> folders,
  ) {
    session.allFolders = [
      for (final folder in folders)
        if (folder.isAvailable) folder,
    ];
    session.customFolders = folders
        .where((folder) => folder.type == 'Custom' && folder.isAvailable)
        .toList();
    session.roleOverrideFolders = folders
        .where((folder) => folder.roleOverride != null && folder.isAvailable)
        .toList();
  }

  static MailFolder? logicalFolderForType(String type) =>
      switch (type.toLowerCase()) {
        'inbox' => MailFolder.inbox,
        'sent' => MailFolder.sent,
        'drafts' => MailFolder.drafts,
        'trash' => MailFolder.trash,
        'junk' => MailFolder.spam,
        'spam' => MailFolder.spam,
        'archive' => MailFolder.archive,
        _ => null,
      };

  /// Best-effort: remembers the current folder map so
  /// [hydrateFromCache] can restore it on a future offline cold
  /// start.
  void persistFolderMap(AccountSession session) {
    final cache = _ctx.cache;
    if (cache == null) return;
    try {
      cache.saveFolders(session.account.id, {
        for (final entry in session.folderIds.entries)
          entry.value: entry.key.name,
        for (final folder in session.customFolders) folder.id: 'custom',
      });
    } catch (_) {
      // Cache is an optimization; never surface its failures.
    }
  }

  List<MailCustomFolder> getCustomFolders({String? accountId}) {
    final sessions = accountId == null
        ? _ctx.registry.scoped
        : [?_ctx.registry.sessions[accountId]];
    final result = <MailCustomFolder>[
      for (final session in sessions)
        for (final f in session.customFolders)
          MailCustomFolder(
            accountId: session.account.id,
            folderId: f.id,
            name: f.name,
            fullName: f.fullName,
            isSyncEnabled: f.isSyncEnabled,
            parentFolderId: f.parentId,
            parentIdKnown: f.parentIdKnown,
            delimiter: f.delimiter,
            unreadCount: f.unreadCount,
            totalCount: f.totalCount,
          ),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return result;
  }

  List<MailFolderInfo> getAccountFolders(String accountId) => [
    for (final f in _ctx.registry.forAccount(accountId).allFolders)
      MailFolderInfo(
        accountId: accountId,
        folderId: f.id,
        name: f.name,
        fullName: f.fullName,
        kind: FolderKind.fromBackend(f.type),
        isSyncEnabled: f.isSyncEnabled,
        parentFolderId: f.parentId,
        delimiter: f.delimiter,
        unreadCount: f.unreadCount,
        totalCount: f.totalCount,
        roleOverride: f.roleOverride == null
            ? null
            : FolderKind.fromBackend(f.roleOverride!),
      ),
  ];

  Map<MailFolder, String> standardFolderIds(String accountId) =>
      Map.unmodifiable(_ctx.registry.forAccount(accountId).folderIds);

  Future<void> refreshCustomFolders({
    String? accountId,
    bool rediscover = false,
  }) async {
    final sessions = accountId == null
        ? _ctx.registry.scoped
        : [_ctx.registry.forAccount(accountId)];
    await Future.wait(
      sessions.map((s) => _loadFolders(s, rediscover: rediscover)),
    );
    _ctx.notify();
  }

  Future<void> _loadFolders(
    AccountSession session, {
    bool rediscover = false,
  }) async {
    if (rediscover) await session.mailService.refreshFolders();
    var folders = await session.mailService.getFolders();
    if (!rediscover &&
        !session.folderHierarchyRequested &&
        folders.any((f) => f.isAvailable && f.delimiter == null)) {
      session.folderHierarchyRequested = true;
      await session.mailService.refreshFolders();
      folders = await session.mailService.getFolders();
    }
    _applyCustomFolderLists(session, folders);
  }

  Future<void> _reloadAfterChange(AccountSession session) async {
    try {
      await _loadFolders(session);
    } catch (_) {
    } finally {
      _ctx.notify();
    }
  }

  void _put(AccountSession session, ApiMailFolder folder) {
    session.customFolders = [
      for (final f in session.customFolders)
        if (f.id != folder.id) f,
      if (folder.type == 'Custom' && folder.isAvailable) folder,
    ];
  }

  Future<void> createCustomFolder({
    required String accountId,
    required String name,
    String? parentFolderId,
  }) async {
    final session = _ctx.registry.forAccount(accountId);
    final created = await session.mailService.createFolder(
      name,
      parentId: parentFolderId,
    );
    _put(session, created);
    await _reloadAfterChange(session);
  }

  Future<void> renameCustomFolder({
    required String accountId,
    required String folderId,
    required String name,
  }) async {
    final session = _ctx.registry.forAccount(accountId);
    final renamed = await session.mailService.renameFolder(folderId, name);
    _put(session, renamed);
    await _reloadAfterChange(session);
  }

  Future<void> changeCustomFolderParent({
    required String accountId,
    required String folderId,
    required String? parentFolderId,
  }) async {
    final session = _ctx.registry.forAccount(accountId);
    final moved = await session.mailService.setFolderParent(
      folderId,
      parentFolderId,
    );
    _put(session, moved);
    await _reloadAfterChange(session);
  }

  Future<void> deleteCustomFolder({
    required String accountId,
    required String folderId,
  }) async {
    final session = _ctx.registry.forAccount(accountId);
    await session.mailService.deleteFolder(folderId);
    session.customFolders = [
      for (final f in session.customFolders)
        if (f.id != folderId) f,
    ];
    session.forgetCustomFolderMails(folderId);
    await _reloadAfterChange(session);
  }

  List<MailFolderRoleAssignment> getFolderRoleAssignments({String? accountId}) {
    final sessions = accountId == null
        ? _ctx.registry.scoped
        : [?_ctx.registry.sessions[accountId]];
    return [
      for (final session in sessions)
        for (final f in session.roleOverrideFolders)
          if (logicalFolderForType(f.roleOverride!) case final role?)
            MailFolderRoleAssignment(
              accountId: session.account.id,
              folderId: f.id,
              name: f.name,
              fullName: f.fullName,
              role: role,
            ),
    ];
  }

  Future<void> setFolderRole({
    required String accountId,
    required String folderId,
    required MailFolder? role,
  }) async {
    final wire = switch (role) {
      null => null,
      MailFolder.sent => 'Sent',
      MailFolder.drafts => 'Drafts',
      MailFolder.trash => 'Trash',
      MailFolder.spam => 'Junk',
      _ => throw ArgumentError.value(role, 'role', 'not assignable'),
    };
    final session = _ctx.registry.forAccount(accountId);
    final previous = Map.of(session.folderIds);
    await session.mailService.setFolderRole(folderId, wire);
    applyFolderMap(session, await session.mailService.getFolders());
    persistFolderMap(session);
    // A logical bucket now backed by a different server folder holds the
    // old folder's mail; drop it so the next open fetches the new folder.
    for (final logical in {...previous.keys, ...session.folderIds.keys}) {
      if (previous[logical] == session.folderIds[logical]) continue;
      session.emails.remove(logical);
      session.pages.remove(logical);
      session.hasMore.remove(logical);
      session.lastSynced.remove(logical);
    }
    session.forgetCustomFolderMails(folderId);
    _ctx.notify();
  }

  Set<MailFolder> availableFolders(String accountId) =>
      _ctx.registry.sessions[accountId]?.folderIds.keys.toSet() ?? const {};
}
