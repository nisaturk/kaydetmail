import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../services/session_store.dart';
import '../services/share_intake.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/mail_threads.dart';
import '../widgets/app_drawer.dart';
import '../widgets/label_picker_sheet.dart';
import 'accounts_screen.dart';
import 'compose_screen.dart';
import 'inbox_screen.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// The main mail interface: a drawer to switch folders plus the mail list.
///
/// When selection mode is active the app bar switches to a compact selection
/// toolbar (Sil, Arşivle, Etiketle). A FAB opens the compose screen when
/// selection mode is off.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MailFolder _folder = MailFolder.inbox;
  final MailSelectionController _selection = MailSelectionController();

  late final ShareIntake _shareIntake = ShareIntake(
    () => mounted ? context : null,
  );

  @override
  void initState() {
    super.initState();
    _shareIntake.start();
  }

  @override
  void dispose() {
    _shareIntake.dispose();
    _selection.dispose();
    super.dispose();
  }

  MailRepository get _repo => AppConfig.mailRepository;

  void _selectFolder(MailFolder folder) {
    _selection.exit();
    setState(() => _folder = folder);
    Navigator.of(context).pop();
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();
    await _repo.logout();
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openSettings() {
    Navigator.of(context).pop(); // close the drawer
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAccounts() {
    Navigator.of(context).pop(); // close the drawer
    _selection.exit();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
  }

  void _showMailboxSelector() {
    _selection.exit();
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final activeId = _repo.activeAccountId;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gelen Kutusu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('selector-unified'),
                leading: const Icon(
                  LucideIcons.inbox,
                  size: 20,
                  color: AppTheme.secondaryText,
                ),
                title: const Text('Tüm Gelen Kutuları'),
                selected: activeId == null,
                onTap: () => Navigator.of(ctx).pop(_unifiedScope),
              ),
              for (final account in _repo.accounts)
                ListTile(
                  key: ValueKey('selector-${account.id}'),
                  leading: Icon(
                    account.id == activeId
                        ? LucideIcons.circleCheckBig
                        : LucideIcons.circle,
                    size: 20,
                    color: account.id == activeId
                        ? Colors.black
                        : AppTheme.tertiaryText,
                  ),
                  title: Text(
                    account.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: account.id == activeId,
                  onTap: () => Navigator.of(ctx).pop(account.id),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((picked) {
      if (picked == null || !mounted) return;
      if (picked == _unifiedScope) {
        _repo.setActiveAccount(null);
      } else {
        _repo.setActiveAccount(picked);
      }
    });
  }

  /// Sentinal returned by the mailbox selector for the unified scope.
  static const String _unifiedScope = '__unified__';

  void _openCompose() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ComposeScreen()));
  }

  // ── Bulk actions ──────────────────────────────────────────────────────
  //
  // Selected rows stand for whole conversations, so every operation expands
  // them to all member messages first. Delete/archive confirm with a compact
  // SnackBar whose Undo restores each message to its exact previous folder.

  Future<void> _actionDelete() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    final previous = previousFoldersOf(_repo, ids);
    await _repo.moveToTrash(ids);
    _selection.exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length} e-posta silindi'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => restorePreviousFolders(_repo, previous),
        ),
      ),
    );
  }

  Future<void> _actionArchive() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    final previous = previousFoldersOf(_repo, ids);
    await _repo.moveToFolder(ids, MailFolder.archive);
    _selection.exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length} e-posta arşivlendi'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => restorePreviousFolders(_repo, previous),
        ),
      ),
    );
  }

  Future<void> _actionSpam() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    final previous = previousFoldersOf(_repo, ids);
    await _repo.moveToFolder(ids, MailFolder.spam);
    _selection.exit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length} e-posta spam kutusuna taşındı'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => restorePreviousFolders(_repo, previous),
        ),
      ),
    );
  }

  Future<void> _actionStar() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    final byId = {for (final e in _repo.getAllEmails()) e.id: e};
    // All starred already -> unstar; otherwise star everything.
    final allStarred = ids.every((id) => byId[id]?.isStarred ?? false);
    await _repo.setStarred(ids, !allStarred);
    _selection.exit();
  }

  /// Marks read unless every selected message is already read.
  Future<void> _actionToggleRead() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    final byId = {for (final e in _repo.getAllEmails()) e.id: e};
    final anyUnread = ids.any((id) => !(byId[id]?.isRead ?? true));
    if (anyUnread) {
      await _repo.markAsRead(ids);
    } else {
      await _repo.markAsUnread(ids);
    }
    _selection.exit();
  }

  Future<void> _actionLabel() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    // Shared picker with the mail detail screen, so labeling never forks into
    // two implementations.
    await showLabelPicker(context, emailIds: ids);
    _selection.exit();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, _selection]),
      builder: (context, _) {
        return Scaffold(
          appBar: _selection.isActive
              ? _buildSelectionAppBar()
              : _buildNormalAppBar(),
          drawer: AppDrawer(
            selectedFolder: _folder,
            onSelectFolder: _selectFolder,
            onLogout: _logout,
            onOpenSettings: _openSettings,
            onOpenAccounts: _openAccounts,
          ),
          floatingActionButton: _selection.isActive
              ? null
              : FloatingActionButton(
                  onPressed: _openCompose,
                  tooltip: 'Yeni E-posta',
                  child: const Icon(LucideIcons.mailPlus),
                ),
          body: KeyedSubtree(
            key: ValueKey(_folder),
            child: InboxScreen(folder: _folder, selection: _selection),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    // The inbox title doubles as the mailbox selector when more than one
    // account is connected: tap it to pick "Tüm Gelen Kutuları" or a single
    // mailbox. With one account — and outside the inbox — the plain folder
    // label stands alone, no chevron, no redundant scope subtitle.
    final selectingInbox =
        _folder == MailFolder.inbox && _repo.accounts.length > 1;
    final Widget title = selectingInbox
        ? InkWell(
            key: const Key('mailbox-selector'),
            borderRadius: BorderRadius.circular(6),
            onTap: _showMailboxSelector,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Gelen Kutusu'),
                  const SizedBox(width: 6),
                  const Icon(
                    LucideIcons.chevronDown,
                    size: 18,
                    color: AppTheme.secondaryText,
                  ),
                ],
              ),
            ),
          )
        : Text(_folder.label);

    return AppBar(
      title: title,
      actions: [
        IconButton(
          onPressed: _openSearch,
          icon: const Icon(LucideIcons.search),
          tooltip: 'Ara',
        ),
      ],
    );
  }

  /// Selection toolbar: cancel + count on the left; Sil, Okundu/Okunmadı and
  /// Arşivle inline; Yıldızla, Spam'e gönder, Etiketle and Tümünü seç in the
  /// overflow menu.
  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        onPressed: _selection.exit,
        tooltip: 'Seçimi iptal et',
        icon: const Icon(LucideIcons.x),
      ),
      title: Text(
        _selection.count == 1 ? '1 seçili' : '${_selection.count} seçili',
      ),
      actions: [
        IconButton(
          onPressed: _actionDelete,
          tooltip: 'Sil',
          icon: const Icon(LucideIcons.trash2),
        ),
        IconButton(
          onPressed: _actionToggleRead,
          tooltip: 'Okundu/Okunmadı işaretle',
          icon: const Icon(LucideIcons.mailOpen),
        ),
        IconButton(
          onPressed: _actionArchive,
          tooltip: 'Arşivle',
          icon: const Icon(LucideIcons.archive),
        ),
        PopupMenuButton<String>(
          tooltip: 'Diğer',
          icon: const Icon(LucideIcons.ellipsisVertical),
          onSelected: (v) {
            switch (v) {
              case 'star':
                _actionStar();
              case 'spam':
                _actionSpam();
              case 'label':
                _actionLabel();
              case 'all':
                _selection.selectAllVisible();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'star', child: Text('Yıldızla')),
            PopupMenuItem(value: 'spam', child: Text('Spam kutusuna gönder')),
            PopupMenuItem(value: 'label', child: Text('Etiketle')),
            PopupMenuItem(value: 'all', child: Text('Tümünü seç')),
          ],
        ),
      ],
    );
  }
}
