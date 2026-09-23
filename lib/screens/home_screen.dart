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
import '../utils/error_messages.dart';
import '../widgets/app_drawer.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/permanent_delete_dialog.dart';
import 'accounts_screen.dart';
import 'compose_screen.dart';
import 'inbox_screen.dart';
import 'mail_detail_screen.dart';
import 'scheduled_sends_screen.dart';
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
  bool _bulkBusy = false;

  /// Mail shown in the wide-layout detail pane (>=[_masterDetailBreakpoint]).
  /// Null shows [_DetailPanePlaceholder] instead — nothing selected yet, or
  /// the folder was just switched (see [_selectFolder]).
  String? _selectedMailId;

  // ── Adaptive layout breakpoints ─────────────────────────────────────
  //
  // Below `_railBreakpoint` this screen is untouched: `Scaffold.drawer` +
  // a full-width list, identical to the phone-only layout. At and above it
  // folders become a persistent rail (no drawer to open/close), and at
  // `_masterDetailBreakpoint` a detail pane joins a width-constrained list.

  /// Tablet-and-up: folder navigation becomes a persistent rail instead of
  /// a `Scaffold.drawer`.
  static const double _railBreakpoint = 840;

  /// Desktop-class: a persistent detail pane joins the rail and a width-
  /// constrained list (master/detail).
  static const double _masterDetailBreakpoint = 1200;

  /// True once the rail replaces the drawer — [_selectFolder] and the other
  /// drawer callbacks must not try to pop a drawer this layout never opened.
  bool get _isRailLayout =>
      mounted && MediaQuery.sizeOf(context).width >= _railBreakpoint;

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
    setState(() {
      _folder = folder;
      _selectedMailId = null;
    });
    if (!_isRailLayout) Navigator.of(context).pop();
  }

  Future<void> _logout() async {
    if (!_isRailLayout) Navigator.of(context).pop();
    await _repo.logout();
    await SessionStore.clear();
    // The root auth coordinator observes the repository logout and replaces
    // the entire authenticated surface, including any routes above Home.
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openSettings() {
    if (!_isRailLayout) Navigator.of(context).pop(); // close the drawer
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openAccounts() {
    if (!_isRailLayout) Navigator.of(context).pop(); // close the drawer
    _selection.exit();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AccountsScreen()));
  }

  void _openScheduledSends() {
    if (!_isRailLayout) Navigator.of(context).pop(); // close the drawer
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScheduledSendsScreen()),
    );
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
                leading: Icon(
                  LucideIcons.inbox,
                  size: 20,
                  color: AppTheme.colors(ctx).secondaryText,
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
                        ? Theme.of(ctx).colorScheme.onSurface
                        : AppTheme.colors(ctx).tertiaryText,
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

  // ── Folder-contextual bulk actions ───────────────────────────────────
  //
  // Trash and Drafts don't support the generic move/delete flow: Trash
  // mails can only be restored or permanently deleted, and Drafts delete
  // through a distinct one-id-at-a-time endpoint rather than a folder move. Spam/Archive/Sent keep the
  // generic flow but hide or add the specific moves that make sense there.

  /// Delete (move to Trash) is hidden in Trash, which offers
  /// [_actionDeleteForever] instead; in Drafts it routes to
  /// [_actionDeleteDrafts] instead of a folder move.
  bool get _showDeleteAction => _folder != MailFolder.trash;

  bool get _showArchiveAction => switch (_folder) {
    MailFolder.drafts ||
    MailFolder.trash ||
    MailFolder.spam ||
    MailFolder.archive => false,
    _ => true,
  };

  bool get _showRestoreAction => _folder == MailFolder.trash;
  bool get _showDeleteForeverAction => _folder == MailFolder.trash;
  bool get _showUnarchiveAction => _folder == MailFolder.archive;
  bool get _showMarkNotSpamAction => _folder == MailFolder.spam;

  /// "Spam kutusuna gönder" only makes sense where a mail could plausibly
  /// still be legitimate — not already in Drafts/Trash/Spam/Sent.
  bool get _showMarkAsSpamAction => switch (_folder) {
    MailFolder.drafts ||
    MailFolder.trash ||
    MailFolder.spam ||
    MailFolder.sent => false,
    _ => true,
  };

  Future<void> _actionDelete() {
    if (_folder == MailFolder.drafts) return _actionDeleteDrafts();
    return _runBulkMove(
      action: (ids) => _repo.moveToTrash(ids),
      success: (count) => '$count e-posta silindi',
    );
  }

  /// Drafts delete through [MailRepository.deleteDraft] — a distinct,
  /// one-id-at-a-time endpoint (see docs/flutter-api-integration.md), never
  /// the generic trash/move flow. There is nothing to restore once a draft
  /// is gone, so this intentionally offers no Undo rather than one that
  /// would silently do nothing.
  Future<void> _actionDeleteDrafts() async {
    if (_bulkBusy) return;
    final ids = _selection.selectedIds.toList();
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    setState(() => _bulkBusy = true);
    try {
      await Future.wait(ids.map(_repo.deleteDraft));
      _selection.exit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ids.length} taslak silindi')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  /// Trash only: expunges the selected conversations' Trash messages. No
  /// Undo exists, so it asks first.
  Future<void> _actionDeleteForever() async {
    if (_bulkBusy) return;
    final ids = idsInFolder(
      _repo,
      expandThreadIds(_repo, _selection.selectedIds),
      _folder,
    );
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    final confirmed = await confirmPermanentDelete(context, ids.length);
    if (!confirmed || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      await _repo.deletePermanently(ids);
      _selection.exit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ids.length} e-posta kalıcı olarak silindi')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _actionArchive() => _runBulkMove(
    action: (ids) => _repo.moveToFolder(ids, MailFolder.archive),
    success: (count) => '$count e-posta arşivlendi',
  );

  Future<void> _actionSpam() => _runBulkMove(
    action: (ids) => _repo.moveToFolder(ids, MailFolder.spam),
    success: (count) => '$count e-posta spam kutusuna taşındı',
  );

  /// Trash's `moveToFolder(ids, inbox)` is auto-resolved by the repository
  /// to a real `restore` call for trashed ids, returning each mail to its
  /// original pre-trash folder — see `MailRepository.moveToFolder` docs.
  Future<void> _actionRestoreFromTrash() => _runBulkMove(
    action: (ids) => _repo.moveToFolder(ids, MailFolder.inbox),
    success: (count) => '$count e-posta geri yüklendi',
    onlyCurrentFolder: true,
  );

  Future<void> _actionUnarchive() => _runBulkMove(
    action: (ids) => _repo.moveToFolder(ids, MailFolder.inbox),
    success: (count) => '$count e-posta arşivden çıkarıldı',
    onlyCurrentFolder: true,
  );

  Future<void> _actionMarkNotSpam() => _runBulkMove(
    action: (ids) => _repo.moveToFolder(ids, MailFolder.inbox),
    success: (count) => '$count e-posta spam olmaktan çıkarıldı',
    onlyCurrentFolder: true,
  );

  /// [onlyCurrentFolder] limits the thread-expanded ids to messages in the
  /// folder being viewed — see [idsInFolder].
  Future<void> _runBulkMove({
    required Future<void> Function(List<String> ids) action,
    required String Function(int count) success,
    bool onlyCurrentFolder = false,
  }) async {
    if (_bulkBusy) return;
    final threadIds = expandThreadIds(_repo, _selection.selectedIds);
    final ids = onlyCurrentFolder
        ? idsInFolder(_repo, threadIds, _folder)
        : threadIds;
    if (ids.isEmpty) {
      _selection.exit();
      return;
    }
    final previous = previousFoldersOf(_repo, ids);
    setState(() => _bulkBusy = true);
    try {
      await action(ids);
      _selection.exit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success(ids.length)),
          // A SnackBar with an action persists by default; Undo is only
          // offered for a short window.
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () => restorePreviousFolders(_repo, previous),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _actionStar() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    await _repo.setStarred(ids, !_selectionAllStarred);
    _selection.exit();
  }

  /// Marks read unless every selected message is already read.
  Future<void> _actionToggleRead() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    if (_selectionAnyUnread) {
      await _repo.markAsRead(ids);
    } else {
      await _repo.markAsUnread(ids);
    }
    _selection.exit();
  }

  /// True while any selected message (thread-expanded) is unread — drives
  /// both [_actionToggleRead]'s decision and the toolbar button's
  /// icon/tooltip, so the button always names the action it is about to
  /// perform instead of a fixed label regardless of state.
  bool get _selectionAnyUnread {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    final byId = {for (final e in _repo.getAllEmails()) e.id: e};
    return ids.any((id) => !(byId[id]?.isRead ?? true));
  }

  /// True when every selected message (thread-expanded) is already
  /// starred — drives both [_actionStar] and the "Yıldızla"/"Yıldızı
  /// kaldır" menu label, matching mail_detail_screen's per-mail toggle.
  bool get _selectionAllStarred {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return false;
    final byId = {for (final e in _repo.getAllEmails()) e.id: e};
    return ids.every((id) => byId[id]?.isStarred ?? false);
  }

  Future<void> _actionLabel() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    // Shared picker with the mail detail screen, so labeling never forks into
    // two implementations.
    await showLabelPicker(context, emailIds: ids);
    _selection.exit();
  }

  Future<void> _actionUnlabel() async {
    final ids = expandThreadIds(_repo, _selection.selectedIds);
    if (ids.isEmpty) return;
    await removeAllLabels(_repo, ids);
    _selection.exit();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, _selection]),
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final showRail = width >= _railBreakpoint;
        final showDetailPane = width >= _masterDetailBreakpoint;
        final drawerContent = AppDrawer(
          selectedFolder: _folder,
          onSelectFolder: _selectFolder,
          onLogout: _logout,
          onOpenSettings: _openSettings,
          onOpenAccounts: _openAccounts,
          onOpenScheduledSends: _openScheduledSends,
        );
        return Scaffold(
          appBar: _selection.isActive
              ? _buildSelectionAppBar()
              : _buildNormalAppBar(),
          drawer: showRail ? null : drawerContent,
          floatingActionButton: _selection.isActive
              ? null
              : FloatingActionButton(
                  onPressed: _openCompose,
                  tooltip: 'Yeni E-posta',
                  child: const Icon(LucideIcons.mailPlus),
                ),
          body: showRail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    drawerContent,
                    VerticalDivider(
                      width: 1,
                      color: AppTheme.colors(context).border,
                    ),
                    Expanded(
                      child: _buildMailArea(showDetailPane: showDetailPane),
                    ),
                  ],
                )
              : _buildMailArea(showDetailPane: false),
        );
      },
    );
  }

  /// Offline banner plus the mail list. At [_masterDetailBreakpoint] and up
  /// the list is width-constrained and a persistent detail pane shows
  /// whichever mail was last tapped (via `InboxScreen.onOpenMail`) instead
  /// of `InboxScreen` pushing `MailDetailScreen` full-screen; below that
  /// this is exactly the full-width list the phone layout has always had.
  Widget _buildMailArea({required bool showDetailPane}) {
    final list = KeyedSubtree(
      key: ValueKey(_folder),
      child: InboxScreen(
        folder: _folder,
        selection: _selection,
        onOpenMail: showDetailPane
            ? (id) => setState(() => _selectedMailId = id)
            : null,
      ),
    );
    final content = showDetailPane
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 440, child: list),
              VerticalDivider(
                width: 1,
                color: AppTheme.colors(context).border,
              ),
              Expanded(
                child: _selectedMailId == null
                    ? const _DetailPanePlaceholder()
                    : MailDetailScreen(
                        key: ValueKey(_selectedMailId),
                        emailId: _selectedMailId!,
                      ),
              ),
            ],
          )
        : list;
    return Column(
      children: [
        if (_repo.isOffline) const _OfflineBanner(),
        Expanded(child: content),
      ],
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    // The inbox title doubles as the mailbox selector when more than one
    // account is connected. Its second line makes the current mailbox scope
    // visible without opening the selector.
    final accounts = _repo.accounts;
    final isInbox = _folder == MailFolder.inbox;
    final selectingInbox = isInbox && accounts.length > 1;
    final activeAccountId = _repo.activeAccountId;
    final activeEmail = activeAccountId == null
        ? (accounts.length == 1 ? accounts.single.email : null)
        : _repo.getAccount(activeAccountId)?.email;
    final scopeLabel = activeEmail ?? 'Tüm Gelen Kutuları';

    final inboxTitle = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gelen Kutusu'),
              if (selectingInbox) ...[
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppTheme.colors(context).secondaryText,
                ),
              ],
            ],
          ),
          Text(
            scopeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.colors(context).secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.15,
            ),
          ),
        ],
      ),
    );

    final Widget title = !isInbox
        ? Text(_folder.label)
        : selectingInbox
        ? InkWell(
            key: const Key('mailbox-selector'),
            borderRadius: BorderRadius.circular(6),
            onTap: _showMailboxSelector,
            child: inboxTitle,
          )
        : inboxTitle;

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

  /// Selection toolbar: cancel + count on the left; inline actions vary by
  /// folder (see the `_show*Action` getters) since delete/archive/spam have
  /// no meaning — or a different meaning — outside Inbox/Starred/Sent. Star,
  /// read/unread and Etiketle stay available in every folder.
  PreferredSizeWidget _buildSelectionAppBar() {
    final inlineActions = <Widget>[
      if (_showDeleteAction)
        IconButton(
          onPressed: _bulkBusy ? null : _actionDelete,
          tooltip: 'Sil',
          icon: const Icon(LucideIcons.trash2),
        ),
      if (_showRestoreAction)
        IconButton(
          onPressed: _bulkBusy ? null : _actionRestoreFromTrash,
          tooltip: 'Geri Yükle',
          icon: const Icon(LucideIcons.rotateCcw),
        ),
      if (_showDeleteForeverAction)
        IconButton(
          onPressed: _bulkBusy ? null : _actionDeleteForever,
          tooltip: 'Kalıcı olarak sil',
          icon: const Icon(LucideIcons.trash2),
        ),
      IconButton(
        onPressed: _bulkBusy ? null : _actionToggleRead,
        tooltip: _selectionAnyUnread
            ? 'Okundu olarak işaretle'
            : 'Okunmadı olarak işaretle',
        icon: Icon(
          _selectionAnyUnread ? LucideIcons.mailOpen : LucideIcons.mail,
        ),
      ),
      if (_showArchiveAction)
        IconButton(
          onPressed: _bulkBusy ? null : _actionArchive,
          tooltip: 'Arşivle',
          icon: const Icon(LucideIcons.archive),
        ),
      if (_showUnarchiveAction)
        IconButton(
          onPressed: _bulkBusy ? null : _actionUnarchive,
          tooltip: 'Arşivden çıkar',
          icon: const Icon(LucideIcons.archiveRestore),
        ),
    ];

    final overflowItems = <PopupMenuEntry<String>>[
      PopupMenuItem(
        value: 'star',
        child: Text(_selectionAllStarred ? 'Yıldızı kaldır' : 'Yıldızla'),
      ),
      if (_showMarkAsSpamAction)
        const PopupMenuItem(
          value: 'spam',
          child: Text('Spam kutusuna gönder'),
        ),
      if (_showMarkNotSpamAction)
        const PopupMenuItem(value: 'not_spam', child: Text('Spam değil')),
      if (anyLabeled(_repo, expandThreadIds(_repo, _selection.selectedIds)))
        const PopupMenuItem(value: 'unlabel', child: Text('Etiketi kaldır'))
      else
        const PopupMenuItem(value: 'label', child: Text('Etiketle')),
      const PopupMenuItem(value: 'all', child: Text('Tümünü seç')),
    ];

    return AppBar(
      leading: _bulkBusy
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          : IconButton(
              onPressed: _selection.exit,
              tooltip: 'Seçimi iptal et',
              icon: const Icon(LucideIcons.x),
            ),
      title: Text(
        _selection.count == 1 ? '1 seçili' : '${_selection.count} seçili',
      ),
      actions: [
        ...inlineActions,
        PopupMenuButton<String>(
          enabled: !_bulkBusy,
          tooltip: 'Diğer',
          icon: const Icon(LucideIcons.ellipsisVertical),
          onSelected: (v) {
            switch (v) {
              case 'star':
                _actionStar();
              case 'spam':
                _actionSpam();
              case 'not_spam':
                _actionMarkNotSpam();
              case 'label':
                _actionLabel();
              case 'unlabel':
                _actionUnlabel();
              case 'all':
                _selection.selectAllVisible();
            }
          },
          itemBuilder: (_) => overflowItems,
        ),
      ],
    );
  }
}

/// Empty state for the wide-layout detail pane before any mail has been
/// tapped, or right after switching folders (see `_selectFolder`).
class _DetailPanePlaceholder extends StatelessWidget {
  const _DetailPanePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mailOpen, size: 40, color: colors.tertiaryText),
            const SizedBox(height: AppTheme.space3),
            Text(
              'Görüntülemek için bir e-posta seçin',
              style: AppTheme.bodyText2.copyWith(color: colors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thin strip shown when the backend can't be reached and the mail list is
/// falling back to the on-device cache. Non-blocking — the mailbox below
/// stays fully usable, just possibly stale.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.colors(context).warningBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            LucideIcons.cloudOff,
            size: 16,
            color: AppTheme.colors(context).warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bağlantı yok. Önbellekteki son postalar gösteriliyor.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.colors(context).warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
