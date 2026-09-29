import '../utils/insets.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/account_sync_scope.dart';
import '../models/mail_folder_info.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/folder_rules.dart';
import '../utils/folder_tree.dart';
import 'custom_folder_mail_screen.dart';
import '../l10n/l10n.dart';

IconData _iconFor(FolderKind kind) => kind.logical?.icon ?? LucideIcons.folder;

String _roleLabel(FolderKind kind) => kind.logical?.label ?? l10nNow.folder;

/// One account's complete folder tree — the standard folders (Gelen Kutusu,
/// Giden, Taslaklar, …) and the user's own — with counts, roles and the
/// actions the backend allows for each. Modelled on webmail folder managers
/// (Roundcube, cPanel/Dovecot): hierarchy under INBOX, per-folder sync
/// ("subscription") and role assignment for servers whose names differ
/// (`INBOX.Sent Items`).
class FolderManagerScreen extends StatefulWidget {
  const FolderManagerScreen({super.key, required this.accountId});

  final String accountId;

  @override
  State<FolderManagerScreen> createState() => _FolderManagerScreenState();
}

class _FolderManagerScreenState extends State<FolderManagerScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  AccountSyncScope? _scope;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool rediscover = false}) async {
    setState(() {
      _loading = _repo.getAccountFolders(widget.accountId).isEmpty;
      _error = null;
    });
    try {
      await _repo.refreshCustomFolders(
        accountId: widget.accountId,
        rediscover: rediscover,
      );
      await _loadScope();
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  Future<void> _loadScope() async {
    try {
      final scope = await _repo.getSyncScope(widget.accountId);
      if (mounted) setState(() => _scope = scope);
    } catch (_) {
      // Sync scope is optional decoration; the tree works without it.
      if (mounted) setState(() => _scope = null);
    }
  }

  Future<void> _perform(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MailFolderInfo> get _folders =>
      _repo.getAccountFolders(widget.accountId);

  MailFolderInfo? _find(String id) =>
      _folders.where((f) => f.folderId == id).firstOrNull;

  // --- Dialogs ---------------------------------------------------------

  Future<String?> _askName({
    required String title,
    required String initial,
    required String? delimiter,
    required Iterable<MailFolderInfo> siblings,
    MailFolderInfo? self,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _FolderNameDialog(
      title: title,
      initial: initial,
      delimiter: delimiter,
      siblings: siblings,
      self: self,
    ),
  );

  Future<(String?,)?> _chooseParent({
    MailFolderInfo? moving,
    String? selectedId,
  }) {
    final all = _folders;
    final excluded = moving == null
        ? const <String>{}
        : subtreeIds(all, moving.folderId);
    final rows = buildFolderRows(all);
    return showDialog<(String?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10nNow.chooseParentFolder),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (null,)),
            child: Row(
              children: [
                if (selectedId == null)
                  const Icon(LucideIcons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(l10nNow.topLevelFolder),
              ],
            ),
          ),
          for (final row in rows)
            if (!excluded.contains(row.folder.folderId))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (row.folder.folderId,)),
                child: Padding(
                  padding: EdgeInsets.only(left: 16.0 * row.depth),
                  child: Row(
                    children: [
                      if (selectedId == row.folder.folderId)
                        const Icon(LucideIcons.check, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Icon(_iconFor(row.folder.kind), size: 18),
                      const SizedBox(width: 8),
                      Flexible(child: Text(row.folder.name)),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  // --- Actions ---------------------------------------------------------

  Future<void> _create({String? parentFolderId}) async {
    final all = _folders;
    var parentId = parentFolderId;
    if (parentId == null) {
      final choice = await _chooseParent();
      if (choice == null || !mounted) return;
      parentId = choice.$1;
    }
    final parent = parentId == null ? null : _find(parentId);
    final name = await _askName(
      title: parentId == null ? l10nNow.newFolder : l10nNow.createSubfolder,
      initial: '',
      delimiter: parent?.delimiter ?? all.firstOrNull?.delimiter,
      siblings: all.where((f) => f.parentFolderId == parentId),
    );
    if (name == null || !mounted) return;
    await _perform(
      () => _repo.createCustomFolder(
        accountId: widget.accountId,
        name: name,
        parentFolderId: parentId,
      ),
      success: l10nNow.folderCreated,
    );
  }

  Future<void> _rename(MailFolderInfo folder) async {
    final name = await _askName(
      title: l10nNow.rename,
      initial: folder.name,
      delimiter: folder.delimiter,
      siblings: _folders.where(
        (f) => f.parentFolderId == folder.parentFolderId,
      ),
      self: folder,
    );
    if (name == null || !mounted || name == folder.name) return;
    await _perform(
      () => _repo.renameCustomFolder(
        accountId: widget.accountId,
        folderId: folder.folderId,
        name: name,
      ),
      success: l10nNow.folderRenamed,
    );
  }

  Future<void> _changeParent(MailFolderInfo folder) async {
    final choice = await _chooseParent(
      moving: folder,
      selectedId: folder.parentFolderId,
    );
    if (choice == null || !mounted || choice.$1 == folder.parentFolderId) {
      return;
    }
    await _perform(
      () => _repo.changeCustomFolderParent(
        accountId: widget.accountId,
        folderId: folder.folderId,
        parentFolderId: choice.$1,
      ),
      success: l10nNow.parentFolderChanged,
    );
  }

  Future<void> _delete(MailFolderInfo folder) async {
    final blocker = FolderRules.deleteBlocker(folder, _folders);
    if (blocker != null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10nNow.folderCantBeDeleted),
          content: Text(blocker),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10nNow.ok),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10nNow.deleteFolder),
        content: Text(l10nNow.theFolderWillBePermanently(folder.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10nNow.cancel2),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10nNow.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(
      () => _repo.deleteCustomFolder(
        accountId: widget.accountId,
        folderId: folder.folderId,
      ),
      success: l10nNow.folderDeleted,
    );
  }

  Future<void> _assignRole(MailFolderInfo folder) async {
    final role = await showDialog<FolderKind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10nNow.whatShouldBeUsedAs(folder.name)),
        children: [
          for (final role in FolderRules.assignableRoles)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(role),
              child: Row(
                children: [
                  Icon(_iconFor(role), size: 18),
                  const SizedBox(width: 12),
                  Text(_roleLabel(role)),
                ],
              ),
            ),
        ],
      ),
    );
    if (role == null || !mounted) return;
    await _perform(
      () => _repo.setFolderRole(
        accountId: widget.accountId,
        folderId: folder.folderId,
        role: role.logical,
      ),
      success: l10nNow.isNowUsedAs(folder.name, _roleLabel(role)),
    );
  }

  Future<void> _resetRole(MailFolderInfo folder) => _perform(
    () => _repo.setFolderRole(
      accountId: widget.accountId,
      folderId: folder.folderId,
      role: null,
    ),
    success: l10nNow.automaticDetectionRestoredFor(folder.name),
  );

  Future<void> _syncNow(MailFolderInfo folder) => _perform(() async {
    await _repo.syncCustomFolder(
      accountId: widget.accountId,
      folderId: folder.folderId,
    );
    await _repo.refreshCustomFolders(accountId: widget.accountId);
  }, success: l10nNow.synced(folder.name));

  int get _syncedCount => _scope?.folders.where((f) => f.synced).length ?? 0;

  bool _isSynced(MailFolderInfo folder) {
    final scoped = _scope?.folders
        .where((f) => f.id == folder.folderId)
        .firstOrNull;
    return scoped?.synced ?? folder.isSyncEnabled;
  }

  Future<void> _toggleSync(MailFolderInfo folder) async {
    final scope = _scope;
    if (scope == null) return;
    final synced = {
      for (final f in scope.folders)
        if (f.synced) f.id,
    };
    if (synced.contains(folder.folderId)) {
      // The backend needs at least one synced folder; the menu item is
      // disabled for the last one, this is only a safety net.
      if (synced.length == 1) return;
      synced.remove(folder.folderId);
    } else {
      synced.add(folder.folderId);
    }
    await _perform(
      () async {
        final updated = await _repo.updateSyncScope(
          widget.accountId,
          FolderSyncScope.selectedFolders,
          folderIds: synced.toList(),
        );
        if (mounted) setState(() => _scope = updated);
      },
      success: synced.contains(folder.folderId)
          ? l10nNow.willSyncAutomatically(folder.name)
          : l10nNow.willNotSyncAutomatically(folder.name),
    );
  }

  void _open(MailFolderInfo folder) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CustomFolderMailScreen(
        accountId: folder.accountId,
        folderId: folder.folderId,
        name: folder.name,
      ),
    ),
  );

  // --- Build -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final account = _repo.getAccount(widget.accountId);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10nNow.folders),
        actions: [
          IconButton(
            tooltip: l10nNow.rescanFoldersOnTheServer,
            onPressed: _busy || _loading ? null : () => _load(rediscover: true),
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-folder'),
        onPressed: _busy || _loading ? null : () => _create(),
        icon: const Icon(LucideIcons.folderPlus),
        label: Text(l10nNow.newFolder),
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (_loading) return const Center(child: CircularProgressIndicator());
          if (_error != null) {
            return _ErrorState(message: _error!, onRetry: _load);
          }
          final rows = buildFolderRows(_folders);
          return RefreshIndicator(
            onRefresh: () => _load(rediscover: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: withBottomInset(
                context,
                const EdgeInsets.only(bottom: 96),
              ),
              children: [
                if (account != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.colors(context).secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text(l10nNow.folderNotFound)),
                  ),
                for (final row in rows) _row(row),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _row(FolderRow row) {
    final folder = row.folder;
    final colors = AppTheme.colors(context);
    final parts = <String>[
      if (folder.hasUserRole)
        l10nNow.usedAs(_roleLabel(folder.kind))
      else if (folder.isStandard && folder.kind != FolderKind.inbox)
        l10nNow.standardFolder,
      if ((folder.unreadCount ?? 0) > 0) l10nNow.unread(folder.unreadCount!),
      if (folder.totalCount != null) l10nNow.emailCount(folder.totalCount!),
    ];
    final synced = _isSynced(folder);
    return ListTile(
      key: ValueKey('folder-${folder.folderId}'),
      contentPadding: EdgeInsets.only(left: 16.0 + 24.0 * row.depth, right: 4),
      leading: Icon(_iconFor(folder.kind), color: colors.secondaryText),
      title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (synced)
            Tooltip(
              message: l10nNow.syncingAutomatically,
              child: Icon(
                LucideIcons.refreshCw,
                size: 14,
                color: colors.tertiaryText,
              ),
            ),
          PopupMenuButton<String>(
            key: ValueKey('folder-menu-${folder.folderId}'),
            enabled: !_busy,
            onSelected: (action) => switch (action) {
              'open' => _open(folder),
              'child' => _create(parentFolderId: folder.folderId),
              'rename' => _rename(folder),
              'parent' => _changeParent(folder),
              'role' => _assignRole(folder),
              'reset-role' => _resetRole(folder),
              'sync-now' => _syncNow(folder),
              'sync-toggle' => _toggleSync(folder),
              'delete' => _delete(folder),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(l10nNow.open)),
              if (FolderRules.canHaveChildren(folder))
                PopupMenuItem(
                  value: 'child',
                  child: Text(l10nNow.createSubfolder),
                ),
              if (FolderRules.canRename(folder))
                PopupMenuItem(value: 'rename', child: Text(l10nNow.rename)),
              if (FolderRules.canMove(folder))
                PopupMenuItem(
                  value: 'parent',
                  child: Text(l10nNow.changeParentFolder),
                ),
              if (folder.kind == FolderKind.custom)
                PopupMenuItem(
                  value: 'role',
                  child: Text(l10nNow.assignFolderRole),
                ),
              if (folder.hasUserRole)
                PopupMenuItem(
                  value: 'reset-role',
                  child: Text(l10nNow.revertToAutomatic),
                ),
              PopupMenuItem(value: 'sync-now', child: Text(l10nNow.syncNow)),
              if (_scope != null)
                PopupMenuItem(
                  value: 'sync-toggle',
                  enabled: !(synced && _syncedCount == 1),
                  child: Text(
                    synced
                        ? l10nNow.turnOffAutomaticSync
                        : l10nNow.turnOnAutomaticSync,
                  ),
                ),
              if (FolderRules.canDelete(folder))
                PopupMenuItem(value: 'delete', child: Text(l10nNow.delete)),
            ],
          ),
        ],
      ),
      onTap: () => _open(folder),
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.initial,
    required this.delimiter,
    required this.siblings,
    this.self,
  });

  final String title;
  final String initial;
  final String? delimiter;
  final Iterable<MailFolderInfo> siblings;
  final MailFolderInfo? self;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = FolderRules.validateName(
      _controller.text,
      delimiter: widget.delimiter,
      siblings: widget.siblings,
      self: widget.self,
    );
    setState(() => _error = error);
    if (error == null) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: l10nNow.folderName,
        errorText: _error,
        errorMaxLines: 2,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10nNow.cancel2),
      ),
      FilledButton(onPressed: _submit, child: Text(l10nNow.save)),
    ],
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function({bool rediscover}) onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: Text(l10nNow.tryAgain)),
      ],
    ),
  );
}
