import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../services/home_widget_service.dart';
import '../state/app_settings_controller.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/mail_threads.dart';
import '../widgets/mail_list_item.dart';
import '../widgets/permanent_delete_dialog.dart';
import 'compose_screen.dart';
import 'mail_detail_screen.dart';

/// What each swipe direction does for a given [MailFolder]. `none` disables
/// that direction when the operation needs a dedicated endpoint a generic
/// move/trash call can't safely stand in for (Drafts: deletion must go
/// through `deleteDraft`, one id at a time, never `moveToTrash`). Trash's
/// delete direction deletes permanently, after a confirmation.
enum _SwipeAction {
  none,
  trash,
  deleteForever,
  archive,
  restore,
  unspam,
  unarchive,
}

/// The action revealed when a row is dragged start-to-end (right in LTR).
_SwipeAction _swipeStartAction(MailFolder folder) => switch (folder) {
  MailFolder.inbox ||
  MailFolder.sent ||
  MailFolder.starred => _SwipeAction.archive,
  MailFolder.trash => _SwipeAction.restore,
  MailFolder.spam => _SwipeAction.unspam,
  MailFolder.archive => _SwipeAction.unarchive,
  MailFolder.drafts || MailFolder.snoozed => _SwipeAction.none,
};

/// The action revealed when a row is dragged end-to-start (left in LTR).
_SwipeAction _swipeEndAction(MailFolder folder) => switch (folder) {
  MailFolder.inbox ||
  MailFolder.sent ||
  MailFolder.starred ||
  MailFolder.spam ||
  MailFolder.archive => _SwipeAction.trash,
  MailFolder.trash => _SwipeAction.deleteForever,
  MailFolder.drafts || MailFolder.snoozed => _SwipeAction.none,
};

/// Label + icon for a swipe background, reused verbatim as the label of the
/// matching screen-reader custom action. Never called with [_SwipeAction.none]
/// — callers filter that out first.
({String label, IconData icon}) _swipeActionMeta(_SwipeAction action) =>
    switch (action) {
      _SwipeAction.trash => (label: 'Sil', icon: LucideIcons.trash2),
      _SwipeAction.deleteForever => (
        label: 'Kalıcı olarak sil',
        icon: LucideIcons.trash2,
      ),
      _SwipeAction.archive => (label: 'Arşivle', icon: LucideIcons.archive),
      _SwipeAction.restore => (label: 'Geri yükle', icon: LucideIcons.undo2),
      _SwipeAction.unspam => (label: 'Spam değil', icon: LucideIcons.shieldOff),
      _SwipeAction.unarchive => (
        label: 'Arşivden çıkar',
        icon: LucideIcons.archiveRestore,
      ),
      _SwipeAction.none => throw UnsupportedError(
        '_SwipeAction.none has no swipe metadata; callers must filter it out.',
      ),
    };

/// Past-tense confirmation shown in the success snackbar after [action]
/// completes.
String _swipeActionDone(_SwipeAction action) => switch (action) {
  _SwipeAction.trash => 'silindi',
  _SwipeAction.deleteForever => 'kalıcı olarak silindi',
  _SwipeAction.archive => 'arşivlendi',
  _SwipeAction.restore => 'geri yüklendi',
  _SwipeAction.unspam => 'spam değil olarak işaretlendi',
  _SwipeAction.unarchive => 'arşivden çıkarıldı',
  _SwipeAction.none => throw UnsupportedError('unreachable'),
};

/// Failure message shown when [action] can't be completed.
String _swipeActionFailed(_SwipeAction action) => switch (action) {
  _SwipeAction.trash => 'E-posta silinemedi. Tekrar deneyin.',
  _SwipeAction.deleteForever =>
    'E-posta kalıcı olarak silinemedi. Tekrar deneyin.',
  _SwipeAction.archive => 'E-posta arşivlenemedi. Tekrar deneyin.',
  _SwipeAction.restore => 'E-posta geri yüklenemedi. Tekrar deneyin.',
  _SwipeAction.unspam => 'E-posta spam dışına alınamadı. Tekrar deneyin.',
  _SwipeAction.unarchive => 'E-posta arşivden çıkarılamadı. Tekrar deneyin.',
  _SwipeAction.none => throw UnsupportedError('unreachable'),
};

/// Coarse Turkish relative time for the "Son senkronizasyon" hint on the
/// empty/error states — deliberately coarser than the mail-row timestamp
/// since only a rough sense of staleness matters here.
String _relativeSyncLabel(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  return '${diff.inDays} gün önce';
}

/// Mail list for a single folder with infinite scrolling.
///
/// Loading, empty, error and retry states are handled explicitly since the
/// backend can fail (network, auth, rate limits) — see [_SkeletonList] for
/// the initial load and [_EmptyState]/[_ErrorState] for the rest. Selection
/// mode is entered by long-pressing a mail avatar.
///
/// Swipe actions are folder-contextual (see [_swipeStartAction] and
/// [_swipeEndAction]): Inbox/Sent/Starred keep the original archive-right,
/// delete-left gesture; Trash offers restore and a confirmed permanent
/// delete (no Undo — the server expunges it); Spam swaps archive for
/// "Spam değil"; Archive swaps archive for "Arşivden çıkar"; Drafts disables
/// swipe entirely because deleting a draft needs the dedicated
/// `deleteDraft` endpoint, not a generic move/trash call. Every enabled
/// swipe action also gets a `CustomSemanticsAction` equivalent so it doesn't
/// require a gesture.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.folder,
    required this.selection,
    this.onOpenMail,
  });

  final MailFolder folder;
  final MailSelectionController selection;

  /// When set, called with the tapped mail's id instead of pushing
  /// [MailDetailScreen] — lets a wide-layout parent (master/detail) update
  /// an in-place detail pane. Null preserves the original full-screen push
  /// for every narrower layout. Never consulted for drafts, which always
  /// open the compose editor.
  final ValueChanged<String>? onOpenMail;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  MailRepository get _repo => AppConfig.mailRepository;

  final ScrollController _scrollController = ScrollController();
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _error;
  Object? _loadMoreError;

  /// Drives a gentle opacity pulse on the initial-load skeleton rows so the
  /// screen doesn't look frozen while the first page loads. Static shapes
  /// alone are enough per the audit; the pulse is a cheap extra.
  late final AnimationController _skeletonController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  late final Animation<double> _skeletonPulse = CurvedAnimation(
    parent: _skeletonController,
    curve: Curves.easeInOut,
  ).drive(Tween(begin: 0.4, end: 1));

  /// Conversations removed from the local list right after a swipe, before the
  /// async trash move lands. Keyed by thread id (see [_dismissKey]).
  final Set<String> _dismissed = {};
  final Set<String> _moving = {};

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
    _skeletonController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _skeletonController.repeat(reverse: true);
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
    } finally {
      if (mounted) _skeletonController.stop();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        _initialLoading ||
        !_repo.hasMoreEmails(widget.folder)) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      await _repo.loadMoreEmails(widget.folder);
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    try {
      await _repo.syncFolder(widget.folder);
      await _repo.refreshEmails(widget.folder);
      unawaited(HomeWidgetService.refreshFromInbox(_repo));
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException && error.status == 404
          ? 'Eşitleme durumu bulunamadı. Tekrar deneyin.'
          : friendlyErrorMessage(error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
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
      openDraftEditor(context, email);
    } else if (widget.onOpenMail != null) {
      widget.onOpenMail!(email.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: email.id)),
      );
    }
  }

  /// A long press anywhere on the row enters selection mode (the row's
  /// InkWell owns the gesture; the avatar is purely visual).

  /// Moves (or restores) an entire conversation according to [action].
  /// Every message's original folder is captured first so Undo can put each
  /// of them back exactly where they were — only the folder changes, every
  /// other bit of state (labels, read/star/pin, attachments, …) survives.
  Future<void> _swipeMove(Email representative, _SwipeAction action) async {
    if (action == _SwipeAction.none) return;
    final threadIds = expandThreadIds(_repo, [representative.id]);
    final ids = switch (action) {
      _SwipeAction.restore ||
      _SwipeAction.unspam ||
      _SwipeAction.unarchive ||
      _SwipeAction.deleteForever => idsInFolder(
        _repo,
        threadIds,
        widget.folder,
      ),
      _ => threadIds,
    };
    if (action == _SwipeAction.deleteForever) {
      if (ids.isEmpty) return;
      final confirmed = await confirmPermanentDelete(context, ids.length);
      if (!confirmed || !mounted) return;
    }
    if (ids.isEmpty) return;
    final previousFolders = previousFoldersOf(_repo, ids);
    final undoKey = _dismissKey(representative);
    if (_moving.contains(undoKey)) return;
    setState(() {
      _moving.add(undoKey);
      _dismissed.add(undoKey);
    });
    try {
      // restore/unspam/unarchive all resolve through moveToFolder: for ids
      // currently in Trash/Spam the repository automatically calls the
      // backend `restore` action (back to each mail's real original folder,
      // ignoring the Inbox target below); Archive has no such special case,
      // so that one is a plain move to Inbox.
      final op = switch (action) {
        _SwipeAction.trash => _repo.moveToTrash(ids),
        _SwipeAction.deleteForever => _repo.deletePermanently(ids),
        _SwipeAction.archive => _repo.moveToFolder(ids, MailFolder.archive),
        _SwipeAction.restore ||
        _SwipeAction.unspam ||
        _SwipeAction.unarchive => _repo.moveToFolder(ids, MailFolder.inbox),
        _SwipeAction.none => Future<void>.value(),
      };
      await op;
      if (!mounted) return;
      setState(() => _moving.remove(undoKey));
      if (action == _SwipeAction.deleteForever) {
        // Expunged server-side: nothing to undo.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${ids.length} e-posta ${_swipeActionDone(action)}'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ids.length} e-posta ${_swipeActionDone(action)}'),
          // A SnackBar with an action persists by default; Undo is only
          // offered for a short window.
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () {
              restorePreviousFolders(_repo, previousFolders);
              if (mounted) setState(() => _dismissed.remove(undoKey));
            },
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _moving.remove(undoKey);
        _dismissed.remove(undoKey);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_swipeActionFailed(action))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, AppSettingsController.instance]),
      builder: (context, _) {
        final emails = _repo.getEmailsInFolder(widget.folder);

        if (_error != null) {
          return _ErrorState(onRetry: _init, folder: widget.folder);
        }
        if (_initialLoading) {
          return _SkeletonList(pulse: _skeletonPulse);
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
        final labelsById = {for (final l in _repo.getLabels()) l.id: l};

        if (grouped.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _EmptyScrollable(folder: widget.folder, onRefresh: _refresh),
          );
        }

        final swipeEnabled = AppSettingsController.instance.swipeDeleteEnabled;
        final startAction = _swipeStartAction(widget.folder);
        final endAction = _swipeEndAction(widget.folder);
        final colors = AppTheme.colors(context);
        final showFooter = _loadingMore || _loadMoreError != null;
        final itemCount = grouped.length + (showFooter ? 1 : 0);
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
                if (_loadMoreError != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: _loadMore,
                        icon: const Icon(LucideIcons.refreshCw, size: 18),
                        label: const Text('Daha fazlasını tekrar yükle'),
                      ),
                    ),
                  );
                }
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
                labels: [
                  for (final id in email.labelIds)
                    if (labelsById[id] != null) labelsById[id]!,
                ],
                threadCount: max(
                  threadCounts[email.threadId] ?? 0,
                  _repo.serverThreadSize(email.threadId),
                ),
                onTap: () => _onMailTap(email),
                onLongPress: () => widget.selection.toggle(email.id),
              );

              final dismissKey = _dismissKey(email);
              final canSwipe =
                  swipeEnabled &&
                  !widget.selection.isActive &&
                  !_moving.contains(dismissKey);
              final hasStart = canSwipe && startAction != _SwipeAction.none;
              final hasEnd = canSwipe && endAction != _SwipeAction.none;
              final direction = hasStart && hasEnd
                  ? DismissDirection.horizontal
                  : hasStart
                  ? DismissDirection.startToEnd
                  : hasEnd
                  ? DismissDirection.endToStart
                  : DismissDirection.none;

              Widget dismissible = Dismissible(
                key: ValueKey('dismiss-$dismissKey'),
                direction: direction,
                confirmDismiss: (swipeDirection) async {
                  await _swipeMove(
                    email,
                    swipeDirection == DismissDirection.startToEnd
                        ? startAction
                        : endAction,
                  );
                  return false;
                },
                background: _SwipeBackground(
                  action: startAction,
                  colors: colors,
                  alignStart: true,
                ),
                secondaryBackground: _SwipeBackground(
                  action: endAction,
                  colors: colors,
                  alignStart: false,
                ),
                child: row,
              );

              // Screen readers can't swipe, so every folder-contextual swipe
              // action also gets a matching custom semantics action —
              // reachable from the accessibility actions rotor instead of a
              // gesture (audit: "swipe aksiyonlarının erişilebilir
              // alternatifi görünür değil").
              final customActions = <CustomSemanticsAction, VoidCallback>{
                if (startAction != _SwipeAction.none)
                  CustomSemanticsAction(
                    label: _swipeActionMeta(startAction).label,
                  ): () =>
                      _swipeMove(email, startAction),
                if (endAction != _SwipeAction.none)
                  CustomSemanticsAction(
                    label: _swipeActionMeta(endAction).label,
                  ): () =>
                      _swipeMove(email, endAction),
              };
              if (customActions.isNotEmpty) {
                dismissible = Semantics(
                  customSemanticsActions: customActions,
                  child: dismissible,
                );
              }
              return dismissible;
            },
          ),
        );
      },
    );
  }

  /// Drops every mail whose thread already appeared earlier in the (newest
  /// first) list, so a conversation occupies exactly one row. The
  /// representative's reply/forward badges are aggregated across the whole
  /// thread — the newest message may not be the one the user replied to.
  List<Email> _groupByThread(List<Email> emails) {
    final seen = <String>{};
    final reps = <Email>[];
    for (final email in emails) {
      if (email.threadId.isNotEmpty && !seen.add(email.threadId)) continue;
      reps.add(_repo.threadStatusOf(email));
    }
    return reps;
  }

  /// Messages per conversation in the current mailbox scope (account or
  /// unified), across folders — so an inbox row can say its thread holds
  /// messages that also live in Sent.
  List<Email>? _countsSource;
  String? _countsAccount;
  Map<String, int> _counts = const {};

  Map<String, int> _threadCounts() {
    final active = _repo.activeAccountId;
    final source = _repo.getScopedEmails();
    // The repository hands back the same list until something changes.
    if (identical(source, _countsSource) && active == _countsAccount) {
      return _counts;
    }
    final counts = <String, int>{};
    for (final email in source) {
      if (email.threadId.isEmpty) continue;
      counts[email.threadId] = (counts[email.threadId] ?? 0) + 1;
    }
    _countsSource = source;
    _countsAccount = active;
    return _counts = counts;
  }
}

/// Solid-fill swipe background for one [_SwipeAction] direction. Destructive
/// actions (trash) use [AppColors.destructive]; every other action shares a
/// muted secondary tone since none of them are destructive (archive/restore/
/// spam-out are all reversible moves, not deletions).
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.action,
    required this.colors,
    required this.alignStart,
  });

  final _SwipeAction action;
  final AppColors colors;

  /// True when this background is revealed by a start-to-end (right in LTR)
  /// drag and should therefore align its content to the left edge.
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    if (action == _SwipeAction.none) return const SizedBox.shrink();
    final meta = _swipeActionMeta(action);
    final fill =
        action == _SwipeAction.trash || action == _SwipeAction.deleteForever
        ? colors.destructive
        : colors.secondaryText;
    final icon = Icon(
      meta.icon,
      size: AppTheme.iconSizeLarge,
      color: Colors.white,
    );
    final label = Text(
      meta.label,
      style: const TextStyle(color: Colors.white, fontSize: 14),
    );
    return Container(
      color: fill,
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.only(
        left: alignStart ? 24 : 0,
        right: alignStart ? 0 : 24,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: alignStart
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: alignStart
            ? [icon, const SizedBox(width: 8), label]
            : [label, const SizedBox(width: 8), icon],
      ),
    );
  }
}

/// Static content-shaped placeholder shown while the first page of a folder
/// loads, instead of a bare spinner that hides the eventual layout (audit:
/// "Loading tasarımının jenerik olması"). [pulse] drives a subtle opacity
/// pulse so the screen still feels alive; the row shapes themselves never
/// move.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({required this.pulse});

  final Animation<double> pulse;

  static const _rowCount = 7;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return FadeTransition(
      opacity: pulse,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _rowCount,
        separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
        itemBuilder: (_, _) => _SkeletonRow(colors: colors),
      ),
    );
  }
}

/// One placeholder row: avatar circle + three bars roughly matching
/// [MailListItem]'s sender/subject/preview lines.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.colors});

  final AppColors colors;

  Widget _bar(double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 20, backgroundColor: colors.surfaceAlt),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(120, 13),
                const SizedBox(height: 8),
                _bar(double.infinity, 12),
                const SizedBox(height: 8),
                _bar(180, 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable wrapper around the empty state so pull-to-refresh keeps working
/// even when the folder has no mails (and short lists stay pullable).
class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.folder, required this.onRefresh});

  final MailFolder folder;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: _EmptyState(folder: folder, onRefresh: onRefresh),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.folder, required this.onRefresh});

  final MailFolder folder;

  /// Pull-to-refresh isn't discoverable by every user, so this wires the
  /// same refresh path to a visible button (audit: Faz 4 item 5).
  final Future<void> Function() onRefresh;

  String get _subtitle => switch (folder) {
    MailFolder.inbox => 'Yeni e-postalar geldiğinde burada görünür.',
    MailFolder.sent => 'Gönderdiğiniz e-postalar burada görünür.',
    MailFolder.starred => 'Yıldızladığınız e-postalar burada görünür.',
    MailFolder.snoozed => 'Ertelediğiniz e-postalar burada görünür.',
    MailFolder.drafts => 'Kaydettiğiniz taslaklar burada durur.',
    MailFolder.trash => 'Sildiğiniz e-postalar burada durur.',
    MailFolder.spam => 'İstenmeyen e-postalar buraya düşer.',
    MailFolder.archive => 'Arşivlediğiniz e-postalar burada durur.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final offline = AppConfig.mailRepository.isOffline;
    final lastSynced = AppConfig.mailRepository.lastSyncedAt(folder);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            offline ? LucideIcons.cloudOff : folder.icon,
            size: 40,
            color: offline ? colors.warning : colors.tertiaryText,
          ),
          const SizedBox(height: 12),
          Text(
            offline ? 'Çevrimdışı' : '${folder.label} boş',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              offline
                  ? 'İnternet bağlantısı yok. Bağlantı sağlanınca yeni postalar görünür.'
                  : _subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.secondaryText),
            ),
          ),
          if (lastSynced != null) ...[
            const SizedBox(height: 8),
            Text(
              'Son senkronizasyon: ${_relativeSyncLabel(lastSynced)}',
              style: TextStyle(fontSize: 12, color: colors.tertiaryText),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Yenile'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.folder});

  final VoidCallback onRetry;
  final MailFolder folder;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final offline = AppConfig.mailRepository.isOffline;
    final lastSynced = AppConfig.mailRepository.lastSyncedAt(folder);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            offline ? LucideIcons.cloudOff : LucideIcons.alertOctagon,
            size: 40,
            color: offline ? colors.warning : colors.secondaryText,
          ),
          const SizedBox(height: 12),
          Text(
            offline ? 'Çevrimdışısınız' : 'E-postalarınız yüklenemedi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          if (offline) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'İnternet bağlantısı yok. Bağlantı sağlanınca otomatik güncellenir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: colors.secondaryText),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Tekrar dene'),
          ),
          if (lastSynced != null) ...[
            const SizedBox(height: 8),
            Text(
              'Son senkronizasyon: ${_relativeSyncLabel(lastSynced)}',
              style: TextStyle(fontSize: 12, color: colors.tertiaryText),
            ),
          ],
        ],
      ),
    );
  }
}
