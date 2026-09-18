import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../services/session_store.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
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
/// When selection mode is active the app bar switches to a selection toolbar
/// and a bottom action bar appears. A FAB opens the compose screen when
/// selection mode is off.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MailFolder _folder = MailFolder.inbox;
  final MailSelectionController _selection = MailSelectionController();

  @override
  void dispose() {
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

  Future<void> _actionDelete() async {
    await _repo.moveToTrash(_selection.selectedIds.toList());
    _selection.exit();
  }

  Future<void> _actionArchive() async {
    await _repo.moveToFolder(
      _selection.selectedIds.toList(),
      MailFolder.archive,
    );
    _selection.exit();
  }

  Future<void> _actionLabel() async {
    final ids = _selection.selectedIds.toList();
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
          bottomNavigationBar: _selection.isActive
              ? _buildBulkActionBar()
              : null,
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
        TextButton(
          onPressed: _selection.selectAllVisible,
          child: const Text('Tümünü seç'),
        ),
      ],
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _ActionBtn(
                icon: LucideIcons.trash2,
                label: 'Sil',
                onTap: _actionDelete,
              ),
              _ActionBtn(
                icon: LucideIcons.archive,
                label: 'Arşivle',
                onTap: _actionArchive,
              ),
              _ActionBtn(
                icon: LucideIcons.tag,
                label: 'Etiketle',
                onTap: _actionLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.black),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}
