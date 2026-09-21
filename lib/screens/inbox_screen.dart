import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../state/app_settings_controller.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/mail_threads.dart';
import '../widgets/mail_list_item.dart';
import 'compose_screen.dart';
import 'mail_detail_screen.dart';

/// Mail list for a single folder with infinite scrolling.
///
/// Loading, empty, error and retry states are handled explicitly, even though
/// the mock data source succeeds almost always — the same code will drive the
/// real API later. Selection mode is entered by long-pressing a mail avatar;
/// swiping a row left deletes it, swiping right archives it.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.folder, required this.selection});

  final MailFolder folder;
  final MailSelectionController selection;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final ScrollController _scrollController = ScrollController();
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Conversations removed from the local list right after a swipe, before the
  /// async trash move lands. Keyed by thread id (see [_dismissKey]).
  final Set<String> _dismissed = {};

  /// Stable identity used to hide a row after swiping and to key the
  /// Dismissible. Threads share one identity; standalone mails use their id.
  static String _dismissKey(Email e) =>
      e.threadId.isEmpty ? 'one:${e.id}' : e.threadId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      if (_repo.getEmailsInFolder(widget.folder).isEmpty) {
        await _repo.loadMoreEmails(widget.folder);
      }
      if (mounted) setState(() => _initialLoading = false);
      _fillIfShort();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _initialLoading) return;
    setState(() => _loadingMore = true);
    try {
      await _repo.loadMoreEmails(widget.folder);
    } catch (_) {
      // Keep the current list; the next scroll will retry.
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _refresh() async {
    // Repository-level refresh: simulates the sync, leaves read/star/pin/
    // folder state and the already-loaded page untouched, never duplicates.
    await _repo.refreshEmails(widget.folder);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      _loadMore();
    }
  }

  /// Fills very short lists (e.g. when the viewport is taller than the
  /// content) so infinite scroll still kicks in.
  void _fillIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent == 0) {
        _loadMore();
      }
    });
  }

  void _onMailTap(Email email) {
    if (widget.selection.isActive) {
      widget.selection.toggle(email.id);
    } else if (email.folder == MailFolder.drafts) {
      // Drafts open in the editor with every field populated; ordinary
      // messages keep opening the read-only detail view.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComposeScreen(
            composeTitle: 'Taslağı Düzenle',
            editingDraftId: email.id,
            initialFrom: _repo.getAccount(email.accountId)?.email,
            initialTo: email.recipients.join(', '),
            initialCc: email.cc.join(', '),
            initialBcc: email.bcc.join(', '),
            initialSubject: email.subject,
            initialBody: email.bodyText,
            initialAttachments: email.attachments,
            initialThreadId: email.threadId.isEmpty ? null : email.threadId,
            inReplyToId: email.inReplyToId,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: email.id)),
      );
    }
  }

  /// A plain tap on the avatar never enters selection mode — only a long
  /// press does. While selection mode is active, tapping toggles the row.
  void _onAvatarTap(Email email) {
    if (widget.selection.isActive) widget.selection.toggle(email.id);
  }

  void _onAvatarLongPress(Email email) => widget.selection.toggle(email.id);

  /// Swiping a row moves the entire conversation: left to Trash, right to
  /// Archive. Every message's original folder is remembered so one Undo
  /// restores each of them; all other state (labels, read/star/pin,
  /// attachments, …) is preserved because only the folder is swapped.
  Future<void> _swipeMove(Email representative, {required bool archive}) {
    final ids = expandThreadIds(_repo, [representative.id]);
    if (ids.isEmpty) return Future.value();
    final previousFolders = previousFoldersOf(_repo, ids);
    final undoKey = _dismissKey(representative);
    setState(() => _dismissed.add(undoKey));
    return (archive
            ? _repo.moveToFolder(ids, MailFolder.archive)
            : _repo.moveToTrash(ids))
        .then((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${ids.length} e-posta ${archive ? 'arşivlendi' : 'silindi'}',
              ),
              action: SnackBarAction(
                label: 'Geri al',
                onPressed: () {
                  restorePreviousFolders(_repo, previousFolders);
                  if (mounted) setState(() => _dismissed.remove(undoKey));
                },
              ),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, AppSettingsController.instance]),
      builder: (context, _) {
        final emails = _repo.getEmailsInFolder(widget.folder);

        if (_error != null) {
          return _ErrorState(onRetry: _init);
        }
        if (_initialLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // One row per conversation: emails sharing a threadId collapse into a
        // single representative row (newest of the group wins). Swiped rows
        // stay hidden until the repository confirms the move.
        final grouped = _groupByThread(emails)
            .where((e) => !_dismissed.contains(_dismissKey(e)))
            .toList();
        widget.selection.syncVisibleIds(grouped.map((e) => e.id).toList());

        final threadCounts = _threadCounts();

        // In the unified mailbox each row names its originating account;
        // account-specific lists stay clean.
        final showAccount =
            _repo.activeAccountId == null && _repo.accounts.length > 1;
        final accountEmail = showAccount
            ? {for (final a in _repo.accounts) a.id: a.email}
            : const <String, String>{};

        if (grouped.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _EmptyScrollable(folder: widget.folder),
          );
        }

        final swipeEnabled = AppSettingsController.instance.swipeDeleteEnabled;
        final itemCount = grouped.length + (_loadingMore ? 1 : 0);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            key: PageStorageKey(widget.folder),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (_, _) =>
                const Divider(indent: 64, endIndent: 16),
            itemBuilder: (context, index) {
              if (index == grouped.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }
              final email = grouped[index];
              final row = MailListItem(
                key: ValueKey(email.id),
                email: email,
                selected:
                    widget.selection.isActive &&
                    widget.selection.selectedIds.contains(email.id),
                accountLabel: showAccount
                    ? accountEmail[email.accountId]
                    : null,
                threadCount: threadCounts[email.threadId],
                onTap: () => _onMailTap(email),
                onAvatarTap: () => _onAvatarTap(email),
                onAvatarLongPress: () => _onAvatarLongPress(email),
              );
              // Swipe left to delete, swipe right to archive (Kaydırarak
              // sil). Disabled while selection mode is active so the
              // horizontal gesture never fights selection, and while the
              // user turned it off in settings.
              return Dismissible(
                key: ValueKey('dismiss-${_dismissKey(email)}'),
                direction: swipeEnabled && !widget.selection.isActive
                    ? DismissDirection.horizontal
                    : DismissDirection.none,
                confirmDismiss: (direction) async {
                  await _swipeMove(
                    email,
                    archive: direction == DismissDirection.startToEnd,
                  );
                  return false;
                },
                background: Container(
                  color: const Color(0xFF9E9E9E),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.archive, size: 20, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Arşivle',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                secondaryBackground: Container(
                  color: const Color(0xFFE57373),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Sil',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      SizedBox(width: 8),
                      Icon(LucideIcons.trash2, size: 20, color: Colors.white),
                    ],
                  ),
                ),
                child: row,
              );
            },
          ),
        );
      },
    );
  }

  /// Drops every mail whose thread already appeared earlier in the (newest
  /// first) list, so a conversation occupies exactly one row.
  List<Email> _groupByThread(List<Email> emails) {
    final seen = <String>{};
    final reps = <Email>[];
    for (final email in emails) {
      if (email.threadId.isNotEmpty && !seen.add(email.threadId)) continue;
      reps.add(email);
    }
    return reps;
  }

  /// Messages per conversation in the current mailbox scope (account or
  /// unified), across folders — so an inbox row can say its thread holds
  /// messages that also live in Sent.
  Map<String, int> _threadCounts() {
    final active = _repo.activeAccountId;
    final all = active == null
        ? _repo.getAllEmails()
        : _repo.getAllEmails().where((e) => e.accountId == active).toList();
    final counts = <String, int>{};
    for (final email in all) {
      if (email.threadId.isEmpty) continue;
      counts[email.threadId] = (counts[email.threadId] ?? 0) + 1;
    }
    return counts;
  }
}

/// Scrollable wrapper around the empty state so pull-to-refresh keeps working
/// even when the folder has no mails (and short lists stay pullable).
class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.folder});

  final MailFolder folder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: _EmptyState(folder: folder),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.folder});

  final MailFolder folder;

  String get _subtitle => switch (folder) {
    MailFolder.inbox => 'Yeni e-postalar geldiğinde burada görünür.',
    MailFolder.sent => 'Gönderdiğiniz e-postalar burada görünür.',
    MailFolder.pinned => 'Yıldızladığınız e-postalar burada görünür.',
    MailFolder.drafts => 'Kaydettiğiniz taslaklar burada durur.',
    MailFolder.trash => 'Sildiğiniz e-postalar burada durur.',
    MailFolder.spam => 'İstenmeyen e-postalar buraya düşer.',
    MailFolder.archive => 'Arşivlediğiniz e-postalar burada durur.',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(folder.icon, size: 40, color: AppTheme.tertiaryText),
          const SizedBox(height: 12),
          Text(
            '${folder.label} boş',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.alertOctagon,
            size: 40,
            color: AppTheme.secondaryText,
          ),
          const SizedBox(height: 12),
          const Text(
            'E-postalarınız yüklenemedi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}
