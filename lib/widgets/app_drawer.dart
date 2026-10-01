import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_custom_folder.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../state/custom_folder_order_controller.dart';
import '../theme/app_theme.dart';
import 'mail_avatar.dart';
import '../l10n/l10n.dart';

/// Drawer'dan açılabilen uygulama hedefleri. Klasörler ayrı seçilir
/// ([onSelectFolder]); bu liste menüdeki alt bölümü tek tablodan üretir.
enum DrawerDestination { scheduled, outbox, customFolders, settings }

/// Hedefin menüdeki karşılığı: ikon + Türkçe etiket tek tabloda.
extension DrawerDestinationMeta on DrawerDestination {
  IconData get icon => switch (this) {
    DrawerDestination.scheduled => LucideIcons.calendarClock,
    DrawerDestination.outbox => LucideIcons.send,
    DrawerDestination.customFolders => LucideIcons.folder,
    DrawerDestination.settings => LucideIcons.settings,
  };

  String get label => switch (this) {
    DrawerDestination.scheduled => l10nNow.scheduledSends,
    DrawerDestination.outbox => l10nNow.pendingEmails,
    DrawerDestination.customFolders => l10nNow.otherFolders,
    DrawerDestination.settings => l10nNow.settings,
  };
}

/// Navigation drawer: folders top-aligned, the "Hesap ve uygulama" section
/// (sync, folder management, settings, logout) pinned to the bottom. When
/// the content is taller than the viewport (landscape phones, large text)
/// the whole drawer scrolls as one list instead of overflowing.
///
/// Accounts are managed from Ayarlar → Hesaplar; the drawer's sync entry
/// only triggers [onSyncAccounts].
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.selectedFolder,
    required this.onSelectFolder,
    required this.onLogout,
    required this.onOpenDestination,
    required this.onSyncAccounts,
    required this.onAddAccount,
    required this.onSelectCustomFolder,
  });

  final MailFolder selectedFolder;
  final ValueChanged<MailFolder> onSelectFolder;
  final VoidCallback onLogout;
  final ValueChanged<DrawerDestination> onOpenDestination;

  /// "Hesapları eşitle": runs the mailbox-wide sync for every account in
  /// scope. The host closes the drawer and reports progress/failure.
  final VoidCallback onSyncAccounts;
  final VoidCallback onAddAccount;

  /// Opens one server custom folder's mail list.
  final ValueChanged<MailCustomFolder> onSelectCustomFolder;

  static const _primaryFolders = [
    MailFolder.inbox,
    MailFolder.sent,
    MailFolder.all,
    MailFolder.drafts,
    MailFolder.spam,
    MailFolder.trash,
    MailFolder.starred,
    MailFolder.archive,
  ];

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: AppConfig.mailRepository,
          builder: (context, _) {
            final repo = AppConfig.mailRepository;
            final customFolders = repo.getCustomFolders();
            final standardParents = {
              for (final account in repo.accounts)
                account.id: repo.standardFolderIds(account.id).values.toSet(),
            };
            final accountNames = {
              for (final account in repo.accounts) account.id: account.email,
            };
            final inboxFolders = _inboxSubtree(customFolders, {
              for (final account in repo.accounts)
                account.id: repo.standardFolderIds(
                  account.id,
                )[MailFolder.inbox],
            });
            // minHeight = viewport + spaceBetween pins the lower section to
            // the drawer bottom on tall screens; on short ones the column
            // takes its natural height and everything scrolls together.
            // (SliverFillRemaining/IntrinsicHeight measure these tiles via
            // intrinsics, which came out short and overflowed.)
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DrawerHeader(
                            repo.currentUser,
                            onAddAccount: onAddAccount,
                          ),
                          const Divider(),
                          const SizedBox(height: 4),
                          for (final folder in _primaryFolders)
                            if (folder == MailFolder.inbox)
                              _InboxGroup(
                                selected: folder == selectedFolder,
                                onTap: () => onSelectFolder(folder),
                                badgeCount: _badgeCount(repo, folder),
                                folders: inboxFolders,
                                accountNames: accountNames,
                                standardParents: standardParents,
                                order: CustomFolderOrderController.instance,
                                onSelect: onSelectCustomFolder,
                              )
                            else
                              _FolderTile(
                                folder: folder,
                                selected: folder == selectedFolder,
                                onTap: () => onSelectFolder(folder),
                                badgeCount: _badgeCount(repo, folder),
                              ),
                          for (final destination in [
                            DrawerDestination.outbox,
                            DrawerDestination.scheduled,
                          ])
                            _SectionTile(
                              icon: destination.icon,
                              label: destination.label,
                              onTap: () => onOpenDestination(destination),
                            ),
                          _CustomFolderSection(
                            folders: customFolders,
                            excludedIds: {
                              for (final folder in inboxFolders)
                                folder.folderId,
                            },
                            accountNames: accountNames,
                            standardParents: standardParents,
                            order: CustomFolderOrderController.instance,
                            onSelect: onSelectCustomFolder,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(height: 12),
                          _MenuHeading(l10nNow.accountAndApp),
                          _SectionTile(
                            icon: LucideIcons.refreshCw,
                            label: l10nNow.syncAccounts,
                            onTap: onSyncAccounts,
                          ),
                          for (final destination in [
                            DrawerDestination.customFolders,
                            DrawerDestination.settings,
                          ])
                            _SectionTile(
                              icon: destination.icon,
                              label:
                                  destination == DrawerDestination.customFolders
                                  ? l10nNow.manageFolders
                                  : destination.label,
                              onTap: () => onOpenDestination(destination),
                            ),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SectionTile(
                              icon: LucideIcons.logOut,
                              label: l10nNow.signOut3,
                              onTap: onLogout,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  int _badgeCount(MailRepository repo, MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
      case MailFolder.spam:
        return repo.unreadCount(folder);
      // Drafts carry no read state; the badge is how many are pending.
      case MailFolder.drafts:
      case MailFolder.snoozed:
        return repo.getEmailsInFolder(folder).length;
      case MailFolder.all:
      case MailFolder.sent:
      case MailFolder.starred:
      case MailFolder.trash:
      case MailFolder.archive:
        return 0;
    }
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader(this.currentUser, {required this.onAddAccount});

  final String currentUser;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          MailAvatar(identity: currentUser, displayName: 'KAYDET', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KAYDET',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  currentUser,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.colors(context).secondaryText,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAddAccount,
            tooltip: l10nNow.addNewAccount,
            icon: const Icon(LucideIcons.plus),
          ),
        ],
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.colors(context).secondaryText,
        ),
      ),
    );
  }
}

typedef _DrawerFolderRow = ({
  MailCustomFolder folder,
  int depth,
  bool canMoveUp,
  bool canMoveDown,
});

/// Server custom folders shown as an indented tree, grouped per account in
/// the unified mailbox. Reorder mode moves a folder (with its subtree) among
/// the siblings under the same parent; the order persists per account.
class _CustomFolderSection extends StatefulWidget {
  const _CustomFolderSection({
    required this.folders,
    required this.excludedIds,
    required this.accountNames,
    required this.standardParents,
    required this.order,
    required this.onSelect,
  });

  final List<MailCustomFolder> folders;

  /// Folders listed elsewhere in the drawer (below the Inbox entry).
  final Set<String> excludedIds;
  final Map<String, String> accountNames;
  final Map<String, Set<String>> standardParents;
  final CustomFolderOrderController order;
  final ValueChanged<MailCustomFolder> onSelect;

  @override
  State<_CustomFolderSection> createState() => _CustomFolderSectionState();
}

class _CustomFolderSectionState extends State<_CustomFolderSection> {
  bool _reordering = false;
  late String _folderKey = _keyOf(widget.folders);

  static String _keyOf(List<MailCustomFolder> folders) =>
      [for (final folder in folders) '${folder.accountId}/${folder.folderId}']
          .join('|');

  @override
  void initState() {
    super.initState();
    widget.order.sync(widget.folders);
  }

  @override
  void didUpdateWidget(_CustomFolderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = _keyOf(widget.folders);
    if (key == _folderKey) return;
    _folderKey = key;
    widget.order.sync(widget.folders);
  }

  List<_DrawerFolderRow> _rowsFor(
    List<MailCustomFolder> accountFolders,
    String accountId,
  ) => _drawerRows(
    accountFolders,
    widget.standardParents[accountId] ?? const {},
    widget.order.orders,
  );

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final folder in widget.folders)
        if (!widget.excludedIds.contains(folder.folderId)) folder,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: widget.order,
      builder: (context, _) {
        final groups = _groupByAccount(visible, widget.accountNames.keys);
        final showAccounts = groups.length > 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Divider(height: 12),
            Row(
              children: [
                Expanded(child: _MenuHeading(l10nNow.folders)),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: _reordering
                        ? l10nNow.finishSorting
                        : l10nNow.sortFolders,
                    icon: Icon(
                      _reordering ? LucideIcons.check : LucideIcons.arrowUpDown,
                    ),
                    onPressed: () => setState(() => _reordering = !_reordering),
                  ),
                ),
              ],
            ),
            for (final MapEntry(key: accountId, value: accountFolders)
                in groups.entries) ...[
              if (showAccounts)
                _AccountSubheading(widget.accountNames[accountId] ?? ''),
              for (final row in _rowsFor(accountFolders, accountId))
                _CustomFolderTile(
                  row: row,
                  reordering: _reordering,
                  onTap: () => widget.onSelect(row.folder),
                  onMove: (offset) => widget.order.move(
                    accountFolders,
                    row.folder.folderId,
                    offset,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Indented tree rows for one account's [accountFolders]. Folders hanging
/// directly below a standard folder (listed in [standardParents]) start at
/// depth 1.
List<_DrawerFolderRow> _drawerRows(
  List<MailCustomFolder> accountFolders,
  Set<String> standardParents,
  Map<String, List<String>> orders,
) {
  final rows = <_DrawerFolderRow>[];
  void visit(List<MailCustomFolderNode> siblings, int depth) {
    for (final (index, node) in siblings.indexed) {
      final actualDepth =
          depth == 0 && standardParents.contains(node.folder.parentFolderId)
          ? 1
          : depth;
      rows.add((
        folder: node.folder,
        depth: actualDepth,
        canMoveUp: index > 0,
        canMoveDown: index < siblings.length - 1,
      ));
      visit(node.children, actualDepth + 1);
    }
  }

  visit(buildCustomFolderTree(accountFolders, orderByAccount: orders), 0);
  return rows;
}

/// Non-empty per-account folder lists, in [accountIds] order first.
Map<String, List<MailCustomFolder>> _groupByAccount(
  Iterable<MailCustomFolder> folders,
  Iterable<String> accountIds,
) {
  final groups = <String, List<MailCustomFolder>>{
    for (final accountId in accountIds) accountId: [],
  };
  for (final folder in folders) {
    groups.putIfAbsent(folder.accountId, () => []).add(folder);
  }
  groups.removeWhere((_, list) => list.isEmpty);
  return groups;
}

/// Every folder that sits anywhere below its account's INBOX. [inboxIds] maps
/// account id to that account's INBOX folder id (null when unknown).
List<MailCustomFolder> _inboxSubtree(
  List<MailCustomFolder> folders,
  Map<String, String?> inboxIds,
) {
  final byKey = {
    for (final folder in folders) (folder.accountId, folder.folderId): folder,
  };
  bool isBelowInbox(MailCustomFolder folder, String inboxId) {
    final seen = <String>{};
    var current = folder;
    while (seen.add(current.folderId)) {
      final parentId = current.parentFolderId;
      if (parentId == null) return false;
      if (parentId == inboxId) return true;
      final parent = byKey[(folder.accountId, parentId)];
      if (parent == null) return false;
      current = parent;
    }
    return false;
  }

  return [
    for (final folder in folders)
      if (inboxIds[folder.accountId] case final inboxId?)
        if (isBelowInbox(folder, inboxId)) folder,
  ];
}

/// The Inbox entry. When the account has folders below INBOX a chevron on the
/// right expands them in place.
class _InboxGroup extends StatefulWidget {
  const _InboxGroup({
    required this.selected,
    required this.onTap,
    required this.badgeCount,
    required this.folders,
    required this.accountNames,
    required this.standardParents,
    required this.order,
    required this.onSelect,
  });

  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  final List<MailCustomFolder> folders;
  final Map<String, String> accountNames;
  final Map<String, Set<String>> standardParents;
  final CustomFolderOrderController order;
  final ValueChanged<MailCustomFolder> onSelect;

  @override
  State<_InboxGroup> createState() => _InboxGroupState();
}

class _InboxGroupState extends State<_InboxGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.folders.isNotEmpty;
    final expanded = _expanded && hasChildren;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FolderTile(
          folder: MailFolder.inbox,
          selected: widget.selected,
          onTap: widget.onTap,
          badgeCount: widget.badgeCount,
          expander: hasChildren
              ? IconButton(
                  key: const Key('inbox-expander'),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  tooltip: expanded
                      ? l10nNow.hideSubfolders
                      : l10nNow.showSubfolders,
                  icon: Icon(
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  ),
                  onPressed: () => setState(() => _expanded = !expanded),
                )
              : null,
        ),
        if (expanded)
          ListenableBuilder(
            listenable: widget.order,
            builder: (context, _) {
              final groups = _groupByAccount(
                widget.folders,
                widget.accountNames.keys,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final MapEntry(key: accountId, value: accountFolders)
                      in groups.entries) ...[
                    if (groups.length > 1)
                      _AccountSubheading(widget.accountNames[accountId] ?? ''),
                    for (final row in _drawerRows(
                      accountFolders,
                      widget.standardParents[accountId] ?? const {},
                      widget.order.orders,
                    ))
                      _CustomFolderTile(
                        row: row,
                        reordering: false,
                        onTap: () => widget.onSelect(row.folder),
                      ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }
}

class _AccountSubheading extends StatelessWidget {
  const _AccountSubheading(this.email);

  final String email;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 2),
      child: Text(
        email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: AppTheme.colors(context).secondaryText,
        ),
      ),
    );
  }
}

class _CustomFolderTile extends StatelessWidget {
  const _CustomFolderTile({
    required this.row,
    required this.reordering,
    required this.onTap,
    this.onMove,
  });

  final _DrawerFolderRow row;
  final bool reordering;
  final VoidCallback onTap;
  final ValueChanged<int>? onMove;

  @override
  Widget build(BuildContext context) {
    final secondaryText = AppTheme.colors(context).secondaryText;
    final unread = row.folder.unreadCount ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minTileHeight: 42,
        contentPadding: EdgeInsets.only(
          left: 16.0 + 16.0 * row.depth,
          right: 8,
        ),
        onTap: reordering ? null : onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(LucideIcons.folder, size: 20, color: secondaryText),
        title: Text(
          row.folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14.5, color: secondaryText),
        ),
        trailing: reordering
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: l10nNow.moveUp,
                    icon: const Icon(LucideIcons.chevronUp),
                    onPressed: row.canMoveUp ? () => onMove?.call(-1) : null,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: l10nNow.moveDown,
                    icon: const Icon(LucideIcons.chevronDown),
                    onPressed: row.canMoveDown ? () => onMove?.call(1) : null,
                  ),
                ],
              )
            : unread > 0
            ? Badge(label: Text('$unread'), largeSize: 20)
            : null,
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
    required this.badgeCount,
    this.expander,
  });

  final MailFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  /// Optional trailing button (the Inbox's sub-folder chevron).
  final Widget? expander;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minTileHeight: 42,
        onTap: onTap,
        selected: selected,
        selectedColor: onSurface,
        selectedTileColor: colors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(
          folder.icon,
          size: 20,
          color: selected ? onSurface : colors.secondaryText,
        ),
        title: Text(
          folder.label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? onSurface : colors.secondaryText,
          ),
        ),
        trailing: badgeCount > 0 || expander != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (badgeCount > 0)
                    Badge(label: Text('$badgeCount'), largeSize: 20),
                  ?expander,
                ],
              )
            : null,
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondaryText = AppTheme.colors(context).secondaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        minTileHeight: 42,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(icon, size: 20, color: secondaryText),
        title: Text(
          label,
          style: TextStyle(fontSize: 14.5, color: secondaryText),
        ),
      ),
    );
  }
}
