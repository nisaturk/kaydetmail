import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_custom_folder.dart';
import '../models/mail_folder.dart';
import '../models/mail_list_view.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../services/home_widget_service.dart';
import '../state/app_settings_controller.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/mail_threads.dart';
import '../utils/mail_ordering.dart';
import '../widgets/mail_list_item.dart';
import '../widgets/horizontal_mail_dismissible.dart';
import '../widgets/mail_list_view_bar.dart';
import '../widgets/permanent_delete_dialog.dart';
import '../widgets/snooze_picker.dart';
import 'compose_screen.dart';
import 'mail_detail_screen.dart';
import '../l10n/l10n.dart';

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
  toggleRead,
  star,
  snooze,
}

_SwipeAction _fromGesture(SwipeGesture gesture) => switch (gesture) {
  SwipeGesture.archive => _SwipeAction.archive,
  SwipeGesture.trash => _SwipeAction.trash,
  SwipeGesture.toggleRead => _SwipeAction.toggleRead,
  SwipeGesture.star => _SwipeAction.star,
  SwipeGesture.snooze => _SwipeAction.snooze,
  SwipeGesture.none => _SwipeAction.none,
};

/// The action revealed when a row is dragged start-to-end (right in LTR).
_SwipeAction _swipeStartAction(MailFolder folder) => switch (folder) {
  MailFolder.inbox ||
  MailFolder.all ||
  MailFolder.sent ||
  MailFolder.starred => _fromGesture(AppSettingsController.instance.swipeRight),
  MailFolder.trash => _SwipeAction.restore,
  MailFolder.spam => _SwipeAction.unspam,
  MailFolder.archive => _SwipeAction.unarchive,
  MailFolder.drafts || MailFolder.snoozed => _SwipeAction.none,
};

/// The action revealed when a row is dragged end-to-start (left in LTR).
_SwipeAction _swipeEndAction(MailFolder folder) => switch (folder) {
  MailFolder.inbox ||
  MailFolder.all ||
  MailFolder.sent ||
  MailFolder.starred => _fromGesture(AppSettingsController.instance.swipeLeft),
  MailFolder.spam || MailFolder.archive => _SwipeAction.trash,
  MailFolder.trash => _SwipeAction.deleteForever,
  MailFolder.drafts || MailFolder.snoozed => _SwipeAction.none,
};

/// Label + icon for a swipe background, reused verbatim as the label of the
/// matching screen-reader custom action. Never called with [_SwipeAction.none]
/// — callers filter that out first.
({String label, IconData icon}) _swipeActionMeta(
  _SwipeAction action,
) => switch (action) {
  _SwipeAction.trash => (label: l10nNow.delete, icon: LucideIcons.trash2),
  _SwipeAction.deleteForever => (
    label: l10nNow.deletePermanently,
    icon: LucideIcons.trash2,
  ),
  _SwipeAction.archive => (label: l10nNow.archive2, icon: LucideIcons.archive),
  _SwipeAction.restore => (label: l10nNow.restore2, icon: LucideIcons.undo2),
  _SwipeAction.unspam => (label: l10nNow.notSpam, icon: LucideIcons.shieldOff),
  _SwipeAction.unarchive => (
    label: l10nNow.unarchive,
    icon: LucideIcons.archiveRestore,
  ),
  _SwipeAction.toggleRead => (
    label: l10nNow.readUnread,
    icon: LucideIcons.mailOpen,
  ),
  _SwipeAction.star => (label: l10nNow.star2, icon: LucideIcons.star),
  _SwipeAction.snooze => (label: l10nNow.snooze, icon: LucideIcons.clock),
  _SwipeAction.none => throw UnsupportedError(
    '_SwipeAction.none has no swipe metadata; callers must filter it out.',
  ),
};

/// Past-tense confirmation shown in the success snackbar after [action]
/// completes for [count] mails.
String _swipeActionDone(_SwipeAction action, int count) => switch (action) {
  _SwipeAction.trash => l10nNow.emailsDeleted(count),
  _SwipeAction.deleteForever => l10nNow.emailsPermanentlyDeleted(count),
  _SwipeAction.archive => l10nNow.emailsArchived(count),
  _SwipeAction.restore => l10nNow.emailsRestored(count),
  _SwipeAction.unspam => l10nNow.emailsMarkedAsNotSpam(count),
  _SwipeAction.unarchive => l10nNow.emailsUnarchived(count),
  _SwipeAction.toggleRead ||
  _SwipeAction.star ||
  _SwipeAction.snooze ||
  _SwipeAction.none => throw UnsupportedError('unreachable'),
};

/// Coarse relative time for the "Son senkronizasyon" hint on the
/// empty/error states — deliberately coarser than the mail-row timestamp
/// since only a rough sense of staleness matters here.
String _relativeSyncLabel(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return l10nNow.justNow;
  if (diff.inMinutes < 60) return l10nNow.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10nNow.hoursAgo(diff.inHours);
  return l10nNow.daysAgo(diff.inDays);
}

/// Mail list for a single folder with infinite scrolling.
///
/// Loading, empty, error and retry states are handled explicitly since the
/// backend can fail (network, auth, rate limits) — see [_SkeletonList] for
/// the initial load and [_EmptyState]/[_ErrorState] for the rest. Selection
/// mode is entered by long-pressing a mail avatar.
///
/// Swipe actions are folder-contextual (see [_swipeStartAction] and
/// [_swipeEndAction]): Inbox/Sent/Starred use the user's configured
/// right/left gestures (archive-right, delete-left by default); Trash offers restore and a confirmed permanent
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
    this.customFolder,
    this.onOpenMail,
  });

  final MailFolder folder;
  final MailCustomFolder? customFolder;
  final MailSelectionController selection;

  /// When set, called with the tapped mail instead of pushing
  /// [MailDetailScreen] — lets a wide-layout parent (master/detail) update
  /// an in-place detail pane. Null preserves the original full-screen push
  /// for every narrower layout. Never consulted for drafts, which always
  /// open the compose editor.
  final ValueChanged<Email>? onOpenMail;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  MailRepository get _repo => AppConfig.mailRepository;

  final ScrollController _scrollController = ScrollController();
  MailListFilter _filter = MailListFilter.all;
  MailListSort _sort = MailListSort.newest;
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

  /// Messages hidden immediately after a swipe, before the async move lands.
  final Set<String> _dismissed = {};
  final Set<String> _moving = {};

  /// Each row and swipe retain the selected message's own identity.
  static String _dismissKey(Email e) => e.id;

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
      final custom = widget.customFolder;
      if (custom != null) {
        await _repo.getCustomFolderMails(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
      } else if (_repo.getEmailsInFolder(widget.folder).isEmpty) {
        await _repo.loadMoreEmails(widget.folder);
      }
      _fillIfShort();
      unawaited(_syncOnOpen());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _initialLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _initialLoading = false);
        _skeletonController.stop();
      }
    }
  }

  /// Folders outside the backend's default background sync (custom folders,
  /// Drafts, Trash, Junk, Archive) only hold what was fetched before, so a
  /// freshly opened one would look empty or stale. After the cached list is
  /// painted, ask the server to sync it and re-read. Best-effort and silent:
  /// pull-to-refresh remains the place where failures are reported.
  Future<void> _syncOnOpen() async {
    final custom = widget.customFolder;
    try {
      if (custom != null) {
        await _repo.syncCustomFolder(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
        if (!mounted) return;
        await _repo.getCustomFolderMails(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
        return;
      }
      const synced = {
        MailFolder.inbox,
        MailFolder.sent,
        MailFolder.all,
        MailFolder.starred,
        MailFolder.snoozed,
      };
      if (synced.contains(widget.folder)) return;
      await _repo.syncFolder(widget.folder);
      if (!mounted) return;
      await _repo.refreshEmails(widget.folder);
    } catch (_) {
      // Offline or queue full: keep showing the cached list.
    }
  }

  Future<void> _loadMore() async {
    final custom = widget.customFolder;
    if (_loadingMore ||
        _initialLoading ||
        (custom == null
            ? !_repo.hasMoreEmails(widget.folder)
            : !_repo.hasMoreCustomFolderMails(
                custom.accountId,
                custom.folderId,
              ))) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      if (custom != null) {
        await _repo.loadMoreCustomFolderMails(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
      } else {
        await _repo.loadMoreEmails(widget.folder);
      }
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    final custom = widget.customFolder;
    if (custom != null) {
      try {
        await _repo.syncCustomFolder(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
        await _repo.getCustomFolderMails(
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
        }
      }
      return;
    }
    try {
      if (widget.folder == MailFolder.all) {
        await _repo.syncFolder(MailFolder.all);
        await _repo.refreshEmails(MailFolder.all);
      } else {
        // Starred and snoozed are client-side virtual views, not server folders.
        if (widget.folder != MailFolder.starred &&
            widget.folder != MailFolder.snoozed) {
          await _repo.syncFolder(widget.folder);
        }
        await _repo.refreshEmails(widget.folder);
      }
      unawaited(HomeWidgetService.refreshFromInbox(_repo));
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException && error.status == 404
          ? l10nNow.syncStatusNotFoundTry
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
      widget.onOpenMail!(email);
    } else {
      final custom = widget.customFolder;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MailDetailScreen(
            emailId: email.id,
            seed: email,
            currentCustomFolderId: custom?.folderId,
          ),
        ),
      );
    }
  }

  /// A long press anywhere on the row enters selection mode (the row's
  /// InkWell owns the gesture; the avatar is purely visual).

  /// Applies a flag change only to the swiped message.
  Future<void> _swipeToggle(Email representative, _SwipeAction action) async {
    final ids = [representative.id];
    final key = _dismissKey(representative);
    if (_moving.contains(key)) return;
    setState(() => _moving.add(key));
    try {
      switch (action) {
        case _SwipeAction.toggleRead:
          representative.isRead
              ? await _repo.markAsUnread(ids)
              : await _repo.markAsRead(ids);
        case _SwipeAction.star:
          await _repo.setStarred(ids, !representative.isStarred);
        case _SwipeAction.snooze:
          final until = await showSnoozePicker(context);
          if (until == null || !mounted) return;
          await _repo.setSnoozed(ids, until);
        default:
          return;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _moving.remove(key));
    }
  }

  Future<void> _swipeMove(Email representative, _SwipeAction action) async {
    if (action == _SwipeAction.none) return;
    if (action == _SwipeAction.toggleRead ||
        action == _SwipeAction.star ||
        action == _SwipeAction.snooze) {
      return _swipeToggle(representative, action);
    }
    final ids = [representative.id];
    if (action == _SwipeAction.deleteForever) {
      final confirmed = await confirmPermanentDelete(context, ids.length);
      if (!confirmed || !mounted) return;
    }
    final custom = widget.customFolder;
    final customIds = custom == null
        ? const <String>[]
        : _repo
              .cachedCustomFolderMails(custom.accountId, custom.folderId)
              .where((mail) => ids.contains(mail.id))
              .map((mail) => mail.id)
              .toList();
    final previousFolders = previousFoldersOf(_repo, ids)
      ..removeWhere((id, _) => customIds.contains(id));
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
        _SwipeAction.toggleRead ||
        _SwipeAction.star ||
        _SwipeAction.snooze ||
        _SwipeAction.none => Future<void>.value(),
      };
      await op;
      if (!mounted) return;
      setState(() => _moving.remove(undoKey));
      if (action == _SwipeAction.deleteForever) {
        // Expunged server-side: nothing to undo.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_swipeActionDone(action, ids.length))),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_swipeActionDone(action, ids.length)),
          // A SnackBar with an action persists by default; Undo is only
          // offered for a short window.
          persist: false,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: l10nNow.undo2,
            onPressed: () {
              if (custom != null && customIds.isNotEmpty) {
                unawaited(
                  _repo.moveToCustomFolder(
                    customIds,
                    accountId: custom.accountId,
                    folderId: custom.folderId,
                  ),
                );
              }
              restorePreviousFolders(_repo, previousFolders);
              if (mounted) setState(() => _dismissed.remove(undoKey));
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _moving.remove(undoKey);
        _dismissed.remove(undoKey);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, AppSettingsController.instance]),
      builder: (context, _) {
        final custom = widget.customFolder;
        final emails = custom == null
            ? _repo.getEmailsInFolder(widget.folder)
            : pinnedFirst(
                _repo.cachedCustomFolderMails(
                  custom.accountId,
                  custom.folderId,
                ),
              );

        if (_error != null) {
          return _ErrorState(onRetry: _init, folder: widget.folder);
        }
        if (_initialLoading) {
          return _SkeletonList(pulse: _skeletonPulse);
        }

        // Every message gets its own row. Swiped messages stay hidden until
        // the repository confirms their move.
        final visible = sortMailList(
          applyMailListFilter(
            emails,
            _filter,
          ).where((e) => !_dismissed.contains(_dismissKey(e))).toList(),
          _sort,
        );
        widget.selection.syncVisibleIds(visible.map((e) => e.id).toList());

        // In the unified mailbox each row names its originating account;
        // account-specific lists stay clean.
        final showAccount =
            _repo.activeAccountId == null && _repo.accounts.length > 1;
        final accountEmail = showAccount
            ? {for (final a in _repo.accounts) a.id: a.email}
            : const <String, String>{};
        final labelsById = {for (final l in _repo.getLabels()) l.id: l};

        if (visible.isEmpty) {
          if (_filter != MailListFilter.all) {
            return _withViewBar(
              _NoMatches(
                onClear: () => setState(() => _filter = MailListFilter.all),
              ),
            );
          }
          return _withViewBar(
            RefreshIndicator(
              onRefresh: _refresh,
              child: _EmptyScrollable(
                folder: widget.folder,
                onRefresh: _refresh,
              ),
            ),
          );
        }

        final swipeEnabled = AppSettingsController.instance.swipeDeleteEnabled;
        final startAction = _swipeStartAction(widget.folder);
        final endAction = _swipeEndAction(widget.folder);
        final colors = AppTheme.colors(context);
        final showFooter = _loadingMore || _loadMoreError != null;
        final itemCount = visible.length + (showFooter ? 1 : 0);
        return _withViewBar(
          RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              key: PageStorageKey(custom?.folderId ?? widget.folder),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: itemCount,
              separatorBuilder: (_, _) =>
                  const Divider(indent: 64, endIndent: 16),
              itemBuilder: (context, index) {
                if (index == visible.length) {
                  if (_loadMoreError != null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(LucideIcons.refreshCw, size: 18),
                          label: Text(l10nNow.tryLoadingMoreAgain),
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
                final email = visible[index];
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

                Widget dismissible = HorizontalMailDismissible(
                  key: ValueKey('dismiss-$dismissKey'),
                  direction: direction,
                  threshold:
                      AppSettingsController.instance.swipeSensitivity.threshold,
                  onAction: (swipeDirection) async {
                    await _swipeMove(
                      email,
                      swipeDirection == DismissDirection.startToEnd
                          ? startAction
                          : endAction,
                    );
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
          ),
        );
      },
    );
  }

  /// Filter chips and sort menu on top of [body]. Both are per-screen
  /// (per folder) session state: switching folders starts from "all, newest".
  Widget _withViewBar(Widget body) => Column(
    children: [
      MailListViewBar(
        filter: _filter,
        sort: _sort,
        onFilterChanged: (value) => setState(() => _filter = value),
        onSortChanged: (value) => setState(() => _sort = value),
      ),
      Expanded(child: body),
    ],
  );
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
    final label = Flexible(
      child: Text(
        meta.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
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
class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10nNow.noMailMatchesThisFilter),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('mail-filter-clear'),
            onPressed: onClear,
            child: Text(l10nNow.clearFilter),
          ),
        ],
      ),
    );
  }
}

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
            // Short landscape + large text can exceed the viewport — scroll
            // the centered content instead of overflowing.
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: _EmptyState(folder: folder, onRefresh: onRefresh),
              ),
            ),
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
    MailFolder.inbox => l10nNow.newEmailsWillAppearHere,
    MailFolder.all => l10nNow.emailsFromYourConnectedAccounts,
    MailFolder.sent => l10nNow.emailsYouSendAppearHere,
    MailFolder.starred => l10nNow.emailsYouStarAppearHere,
    MailFolder.snoozed => l10nNow.emailsYouSnoozeAppearHere,
    MailFolder.drafts => l10nNow.draftsYouSaveAreKept,
    MailFolder.trash => l10nNow.emailsYouDeleteAreKept,
    MailFolder.spam => l10nNow.unwantedEmailsEndUpHere,
    MailFolder.archive => l10nNow.emailsYouArchiveAreKept,
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
            offline ? l10nNow.offline : l10nNow.isEmpty(folder.label),
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
              offline ? l10nNow.noInternetConnectionNewMail : _subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.secondaryText),
            ),
          ),
          if (lastSynced != null) ...[
            const SizedBox(height: 8),
            Text(
              l10nNow.lastSync(_relativeSyncLabel(lastSynced)),
              style: TextStyle(fontSize: 12, color: colors.tertiaryText),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: Text(l10nNow.refresh),
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
    // Same short-viewport treatment as [_EmptyState]: center when it fits,
    // scroll when it doesn't.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
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
                  offline
                      ? l10nNow.youreOffline
                      : l10nNow.yourEmailsCouldntBeLoaded,
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
                      l10nNow.noInternetConnectionItWill,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  label: Text(l10nNow.tryAgain),
                ),
                if (lastSynced != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10nNow.lastSync(_relativeSyncLabel(lastSynced)),
                    style: TextStyle(fontSize: 12, color: colors.tertiaryText),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
