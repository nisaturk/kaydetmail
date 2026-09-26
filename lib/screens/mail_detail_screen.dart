import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/compose_prefill.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../models/attachment_download_state.dart';
import '../services/attachment_auto_download_policy.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_preview.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../utils/mail_pdf_export.dart';
import '../utils/mail_threads.dart';
import '../utils/mail_unsubscribe.dart';
import '../widgets/move_folder_sheet.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/mail_avatar.dart';
import '../widgets/mail_link_handler.dart';
import '../widgets/permanent_delete_dialog.dart';
import '../widgets/snooze_picker.dart';
import '../widgets/reply_reminder_picker.dart';
import 'attachment_preview_screen.dart';
import 'compose_screen.dart';

/// Full view of a mail — and, when it belongs to a conversation, the whole
/// thread as stacked, collapsible cards (Gmail-style), newest first.
///
/// Opening a mail marks it as read. Pin and read/unread state change through
/// the repository and are reflected immediately because the screen listens to
/// it. A single-message thread renders the plain detail view; a multi-message
/// conversation renders a card stack; tapping a card expands/collapses it.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.emailId,
    this.openReplyOnLoad = false,
    this.currentCustomFolderId,
  });

  final String emailId;
  final bool openReplyOnLoad;

  final String? currentCustomFolderId;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  Email? _email;
  List<Email> _thread = const [];
  final _scroll = ScrollController();

  /// Thread length last scrolled to, so the chat jumps to the newest message
  /// only when messages were added — not on every pin/read notification.
  int _scrolledCount = 0;
  bool _loading = true;
  bool _opened = false;

  /// Set while a folder-move action (restore / "spam değil" / "arşivden
  /// çıkar") is in flight, so the triggering button disables itself —
  /// mirrors the busy-flag shape of `_runBulkMove` in HomeScreen.
  bool _folderActionBusy = false;

  /// Set while a reply/reply-all/forward compose context request is in
  /// flight — disables the triggering action so a slow/offline fetch
  /// can't be tapped twice or race a second mode's response into the
  /// wrong `ComposeScreen`.
  bool _composeActionBusy = false;

  /// Why the main mail load failed, when it did and nothing is shown yet.
  /// Null means "not found" rather than a transport error.
  Object? _loadError;

  /// Guards thread enrichment: `<mailId>@<threadId>` currently loading vs.
  /// already loaded, so listener re-runs never stack or repeat fetches.
  String? _enrichingKey;
  String? _enrichedKey;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _repo.removeListener(_reload);
    _scroll.dispose();
    super.dispose();
  }

  /// Mail-first loading: the opened mail renders as soon as its own detail
  /// response arrives. Thread enrichment follows asynchronously and can only
  /// *add* messages — it never replaces or blanks the loaded mail.
  ///
  /// Listener-safe: a failed refresh keeps the already-shown mail instead
  /// of clearing it; the spinner only shows on the very first load and on
  /// explicit retry.
  Future<void> _reload() async {
    Email? email;
    Object? error;
    try {
      email = await _repo.getEmail(widget.emailId);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    if (email != null) {
      final loaded = email;
      final first = !_opened;
      setState(() {
        _email = loaded;
        _thread = _mergeThread(loaded, [
          ..._thread,
          ..._repo.getThreadEmails(loaded.threadId),
        ]);
        _loading = false;
        _loadError = null;
      });
      _scrollToNewest();

      // A freshly opened mail becomes read — but only on the very first
      // load. Later reloads (pin, mark-as-unread) must not silently flip
      // it back.
      if (first) {
        _opened = true;
        if (widget.openReplyOnLoad) unawaited(_reply());
        if (!loaded.isRead) {
          await _repo.markAsRead([loaded.id]);
        }
      }
      _maybeEnrichThread(loaded);
    } else if (_email == null) {
      // Nothing shown yet: surface not-found vs. transport error.
      if (error != null) debugPrint('Mail detail load failed: $error');
      setState(() {
        _loading = false;
        _loadError = error;
      });
    } else if (error != null) {
      // Refresh failed but the loaded mail stays on screen.
      debugPrint('Mail detail refresh failed: $error');
    }
  }

  /// The opened mail plus the already-known thread messages, deduplicated
  /// and sorted newest-first. The opened mail is always present, so a
  /// thread fetch can never remove what the user opened.
  static List<Email> _mergeThread(Email email, List<Email> others) {
    final byId = {for (final message in others) message.id: message};
    byId[email.id] = email;
    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(merged);
  }

  static bool _sameIds(List<Email> a, List<Email> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// Kicks off conversation enrichment once per mail+thread. A failure only
  /// keeps the already-rendered single mail — the screen never blanks and
  /// the spinner never returns.
  void _maybeEnrichThread(Email email) {
    if (email.threadId.isEmpty) return;
    final key = '${email.id}@${email.threadId}';
    if (key == _enrichedKey || key == _enrichingKey) return;
    _enrichingKey = key;
    unawaited(_enrichThread(email, key));
  }

  Future<void> _enrichThread(Email email, String key) async {
    try {
      final fetched = await _repo.fetchThreadEmails(email.threadId);
      if (!mounted) return;
      // The user may have navigated to another mail meanwhile — only merge
      // into the mail this fetch started for.
      if (_email?.id != email.id) return;
      // The server conversation can lag behind replies sent from this app
      // (only a local copy exists until the next sync), so keep those too.
      final merged = _mergeThread(email, [
        ...fetched,
        ..._repo.getThreadEmails(email.threadId),
      ]);
      debugPrint('Thread ${email.threadId}: ${merged.length} messages');
      if (!_sameIds(merged, _thread)) {
        setState(() => _thread = merged);
        _scrollToNewest();
      }
      _enrichedKey = key;
    } catch (e) {
      debugPrint('Thread enrichment failed for ${email.threadId}: $e');
    } finally {
      if (_enrichingKey == key) _enrichingKey = null;
    }
  }

  /// The conversation reads newest-first, so land on the newest message
  /// (the top) whenever the thread grows.
  void _scrollToNewest() {
    if (_thread.length < 2 || _thread.length == _scrolledCount) return;
    _scrolledCount = _thread.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.minScrollExtent);
      }
    });
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await _reload();
  }

  /// Shows the pin-limit notice when no slot is left in [accountId]'s own
  /// cap (each account gets its own 3 slots — matches the backend's
  /// per-account enforcement). Returns true when the caller may proceed.
  bool _ensurePinSlot(String accountId) {
    final pinnedInAccount = _repo
        .getAllEmails()
        .where((email) => email.isPinned && email.accountId == accountId)
        .length;
    if (pinnedInAccount >= MailRepository.maxPinnedMails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En fazla 3 mail sabitlenebilir.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _togglePin() async {
    final email = _email;
    if (email == null) return;
    if (!email.isPinned && !_ensurePinSlot(email.accountId)) return;
    await _repo.setPinned([email.id], !email.isPinned);
  }

  Future<void> _toggleStar() async {
    final email = _email;
    if (email == null) return;
    // Star and pin are independent flags: starring never pins, unstarring
    // never unpins. Starring consumes no pin slot.
    await _repo.setStarred([email.id], !email.isStarred);
  }

  /// Snoozed mail is hidden from every normal folder view until [until]
  /// (see `ApiMailRepository._buildFolderView`) — purely client-side, no
  /// backend involved (see `LocalMailFlagsStore`).
  Future<void> _toggleSnooze() async {
    final email = _email;
    if (email == null) return;
    if (_repo.snoozedUntilOf(email.id) != null) {
      await _repo.setSnoozed([email.id], null);
      return;
    }
    final until = await showSnoozePicker(context);
    if (until == null || !mounted) return;
    await _repo.setSnoozed([email.id], until);
    if (mounted) await Navigator.of(context).maybePop();
  }

  Future<void> _toggleWatchReply() async {
    final email = _email;
    if (email == null) return;
    if (_repo.getReplyReminders().any((r) => r.mailId == email.id)) {
      try {
        await _repo.cancelReplyReminder(email.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Yanıt takibi kaldırıldı.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kaldırılamadı: ${friendlyErrorMessage(e)}')),
          );
        }
      }
      return;
    }
    final dueAt = await showReplyReminderPicker(context);
    if (dueAt == null || !mounted) return;
    try {
      await _repo.setReplyReminder(email.id, dueAt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Yanıt gelmezse ${formatMailDateFull(dueAt)} tarihinde hatırlatılacak.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kurulamadı: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _moveMail() async {
    final email = _email;
    if (email == null || _folderActionBusy) return;
    final target = await showMoveFolderSheet(
      context,
      repository: _repo,
      accountIds: {email.accountId},
      currentFolders: widget.currentCustomFolderId == null
          ? {email.folder}
          : const {},
      currentCustomFolderId: widget.currentCustomFolderId,
    );
    if (target == null || !mounted) return;
    setState(() => _folderActionBusy = true);
    try {
      final custom = target.customFolder;
      if (custom != null) {
        await _repo.moveToCustomFolder(
          [email.id],
          accountId: custom.accountId,
          folderId: custom.folderId,
        );
      } else if (target.folder == MailFolder.trash) {
        await _repo.moveToTrash([email.id]);
      } else {
        await _repo.moveToFolder([email.id], target.folder!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-posta ${target.label} klasörüne taşındı.')),
      );
      await Navigator.of(context).maybePop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _folderActionBusy = false);
    }
  }

  /// Moves the open mail back to the inbox. For a mail whose current
  /// folder is Trash or Spam, `MailRepository.moveToFolder` resolves this
  /// to the backend's restore action (the mail's original pre-trash/spam
  /// folder), not a literal move to Inbox — see the repository doc
  /// comment. Restore / "Spam değil" / "Arşivden çıkar" all reduce to
  /// this one call.
  Future<void> _moveToInbox(String successMessage) async {
    final email = _email;
    if (email == null || _folderActionBusy) return;
    setState(() => _folderActionBusy = true);
    try {
      await _repo.moveToFolder([email.id], MailFolder.inbox);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _folderActionBusy = false);
    }
  }

  /// Folder-specific primary action for the open mail, when its current
  /// folder has one: Trash → restore, Spam → not spam, Archive →
  /// unarchive. Drafts open `ComposeScreen` instead of this screen (see
  /// `_onMailTap` in inbox/search screens), so `MailFolder.drafts` is not
  /// expected here — the `default` branch still returns null instead of
  /// assuming, so a draft opened by some future path degrades gracefully
  /// rather than crashing.
  IconButton? _folderAction(Email email) {
    switch (email.folder) {
      case MailFolder.trash:
        return IconButton(
          onPressed: _folderActionBusy
              ? null
              : () => _moveToInbox('E-posta geri yüklendi.'),
          tooltip: 'Geri yükle',
          icon: const Icon(LucideIcons.rotateCcw),
        );
      case MailFolder.spam:
        return IconButton(
          onPressed: _folderActionBusy
              ? null
              : () => _moveToInbox('E-posta spam değil olarak işaretlendi.'),
          tooltip: 'Spam değil',
          icon: const Icon(LucideIcons.shieldOff),
        );
      case MailFolder.archive:
        return IconButton(
          onPressed: _folderActionBusy
              ? null
              : () => _moveToInbox('E-posta arşivden çıkarıldı.'),
          tooltip: 'Arşivden çıkar',
          icon: const Icon(LucideIcons.archiveRestore),
        );
      default:
        return null;
    }
  }

  /// The address a reply/forward is sent from: the originating account, so a
  /// mail received on account B is never answered from account A.
  String? _originatingFrom() {
    final email = _email;
    if (email == null || email.accountId.isEmpty) return null;
    return _repo.getAccount(email.accountId)?.email;
  }

  /// Opens `ComposeScreen` prefilled from the backend's compose context
  /// (`GET /api/mails/{id}/compose/{mode}`) instead of recomputing
  /// recipients/subject/threading client-side — see docs-dev spec §4.
  /// [mode] is `'reply'`, `'reply-all'` or `'forward'`.
  Future<void> _openComposePrefill(String mode, {required String title}) async {
    final email = _email;
    if (email == null || _composeActionBusy) return;
    setState(() => _composeActionBusy = true);
    final ComposePrefill prefill;
    try {
      prefill = await _repo.getComposePrefill(email.id, mode);
    } catch (error) {
      if (mounted) {
        setState(() => _composeActionBusy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Yanıt hazırlanamadı: ${friendlyErrorMessage(error)}',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _composeActionBusy = false);

    final isForward = mode == 'forward';
    var initialBody = '';
    var initialAttachments = const <Attachment>[];
    if (isForward) {
      final dateLine = prefill.originalDate == null
          ? ''
          : 'Tarih: ${formatMailDateFull(prefill.originalDate!)}\n';
      initialBody =
          '\n\n--- İletilen mesaj ---\n'
          'Kimden: ${prefill.originalFrom ?? email.senderEmail}\n'
          '$dateLine'
          'Konu: ${prefill.originalSubject ?? email.subject}\n\n'
          '${email.bodyText}';
      // Metadata only (no bytes yet) — ComposeScreen downloads each one
      // itself and blocks Send until every attachment is ready, so a
      // forwarded attachment is never silently dropped (spec §5/§6).
      initialAttachments = prefill.attachments;
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: title,
          initialFrom: _originatingFrom(),
          initialTo: prefill.to.join(', '),
          initialCc: prefill.cc.join(', '),
          initialSubject: prefill.suggestedSubject,
          initialBody: initialBody,
          initialAttachments: initialAttachments,
          attachmentSourceMailId: isForward ? email.id : null,
          initialThreadId: isForward ? null : email.threadId,
          inReplyToId: isForward ? null : email.id,
        ),
      ),
    );
    if (sent != true || !mounted) return;
    if (isForward) {
      await _repo.markAsForwarded([email.id]);
    } else {
      await _repo.markAsReplied([email.id]);
    }
  }

  Future<void> _reply() => _openComposePrefill('reply', title: 'Yanıtla');

  Future<void> _replyAll() =>
      _openComposePrefill('reply-all', title: 'Tümünü Yanıtla');

  Future<void> _forward() => _openComposePrefill('forward', title: 'İlet');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('E-posta'), actions: _appBarActions()),
      body: SafeArea(child: _buildBody()),
    );
  }

  /// Reply/Forward stay available regardless of folder, including Trash —
  /// replying to or forwarding a trashed mail is still a meaningful action,
  /// and hiding them would only cost the user a round-trip through Geri
  /// Yükle first.
  List<Widget> _appBarActions() {
    final email = _email;
    if (email == null) return const [];
    final folderAction = _folderAction(email);
    return [
      ?folderAction,
      IconButton(
        onPressed: _toggleStar,
        tooltip: email.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
        icon: Icon(
          LucideIcons.star,
          color: email.isStarred ? Colors.amber : null,
        ),
      ),
      IconButton(
        onPressed: _composeActionBusy ? null : _reply,
        tooltip: 'Yanıtla',
        icon: const Icon(LucideIcons.reply),
      ),
      IconButton(
        onPressed: _composeActionBusy ? null : _forward,
        tooltip: 'İlet',
        icon: const Icon(LucideIcons.forward),
      ),
      PopupMenuButton<String>(
        icon: const Icon(LucideIcons.moreHorizontal),
        tooltip: 'Daha fazla',
        onSelected: (action) => _handleMenu(action),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'reply_all',
            enabled: !_composeActionBusy,
            child: const Text('Tümünü Yanıtla'),
          ),
          PopupMenuItem(
            value: 'pin',
            child: Text(email.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle'),
          ),
          PopupMenuItem(
            value: 'star',
            child: Text(email.isStarred ? 'Yıldızı kaldır' : 'Yıldızla'),
          ),
          if (email.isRead)
            const PopupMenuItem(
              value: 'unread',
              child: Text('Okunmadı olarak işaretle'),
            )
          else
            const PopupMenuItem(
              value: 'read',
              child: Text('Okundu olarak işaretle'),
            ),
          if (email.folder == MailFolder.sent)
            PopupMenuItem(
              value: 'watch_reply',
              child: Text(
                _repo.getReplyReminders().any((r) => r.mailId == email.id)
                    ? 'Yanıt takibini kaldır'
                    : 'Yanıt gelmezse hatırlat',
              ),
            ),
          PopupMenuItem(
            value: 'snooze',
            child: Text(
              _repo.snoozedUntilOf(email.id) != null
                  ? 'Ertelemeyi kaldır'
                  : 'Ertele',
            ),
          ),
          if (email.folder != MailFolder.drafts)
            const PopupMenuItem(value: 'move', child: Text('Taşı')),
          if (email.folder == MailFolder.trash)
            const PopupMenuItem(
              value: 'delete_forever',
              child: Text('Kalıcı olarak sil'),
            ),
          if (anyLabeled(_repo, _conversationIds))
            const PopupMenuItem(value: 'unlabel', child: Text('Etiketi kaldır'))
          else
            const PopupMenuItem(value: 'label', child: Text('Etiketle')),
          const PopupMenuItem(value: 'print', child: Text('Yazdır')),
          const PopupMenuItem(
            value: 'share_pdf',
            child: Text('PDF olarak paylaş'),
          ),
          if (parseUnsubscribeHeaders(email.headers)?.hasAction ?? false)
            const PopupMenuItem(
              value: 'unsubscribe',
              child: Text('Abonelikten Çık'),
            ),
        ],
      ),
    ];
  }

  /// Labels apply to the whole conversation, the same unit a list row and
  /// the bulk "Etiketle" act on — labeling only the opened message would
  /// leave the row's representative (often another message) unchanged.
  List<String> get _conversationIds {
    final ids = expandThreadIds(_repo, [widget.emailId]);
    return ids.isEmpty ? [widget.emailId] : ids;
  }

  Future<void> _handleMenu(String action) async {
    if (action == 'reply_all') {
      await _replyAll();
    } else if (action == 'read') {
      await _repo.markAsRead([widget.emailId]);
    } else if (action == 'unread') {
      await _repo.markAsUnread([widget.emailId]);
    } else if (action == 'pin') {
      await _togglePin();
    } else if (action == 'star') {
      await _toggleStar();
    } else if (action == 'snooze') {
      await _toggleSnooze();
    } else if (action == 'watch_reply') {
      await _toggleWatchReply();
    } else if (action == 'label') {
      await showLabelPicker(context, emailIds: _conversationIds);
    } else if (action == 'unlabel') {
      await removeAllLabels(_repo, _conversationIds);
    } else if (action == 'delete_forever') {
      await _deleteForever();
    } else if (action == 'move') {
      await _moveMail();
    } else if (action == 'print') {
      await _printMail();
    } else if (action == 'share_pdf') {
      await _sharePdf();
    } else if (action == 'unsubscribe') {
      await _unsubscribe();
    }
  }

  /// Expunges the conversation's Trash messages after a confirmation, then
  /// leaves the screen — there is nothing left to show.
  Future<void> _deleteForever() async {
    final ids = idsInFolder(_repo, _conversationIds, MailFolder.trash);
    if (ids.isEmpty || _folderActionBusy) return;
    final confirmed = await confirmPermanentDelete(context, ids.length);
    if (!confirmed || !mounted) return;
    setState(() => _folderActionBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.deletePermanently(ids);
      messenger.showSnackBar(
        const SnackBar(content: Text('E-posta kalıcı olarak silindi.')),
      );
      if (mounted) await Navigator.of(context).maybePop();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _folderActionBusy = false);
    }
  }

  /// Fires the header-driven unsubscribe action for the open mail. A
  /// one-click (RFC 8058) request asks for confirmation first — it's a
  /// real POST to the sender's server and, unlike opening a browser tab,
  /// can't be walked back by just closing the page.
  Future<void> _unsubscribe() async {
    final email = _email;
    if (email == null) return;
    final info = parseUnsubscribeHeaders(email.headers);
    if (info == null || !info.hasAction) return;

    if (info.oneClick) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Abonelikten çıkılsın mı?'),
          content: const Text(
            'Bu gönderenden e-posta almayı durdurmak için bir istek '
            'gönderilecek. Bu işlem geri alınamaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Abonelikten Çık'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final success = await performUnsubscribe(info);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (info.oneClick
                      ? 'Abonelik iptal edildi.'
                      : 'Abonelikten çıkma işlemi açıldı.')
                : 'Abonelikten çıkma işlemi başarısız oldu.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    }
  }

  /// Opens the OS print dialog for the open mail's PDF rendering.
  Future<void> _printMail() async {
    final email = _email;
    if (email == null) return;
    try {
      await printMailPdf(email);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yazdırma başarısız: ${friendlyErrorMessage(error)}'),
        ),
      );
    }
  }

  /// Opens the OS share sheet with the open mail's PDF rendering.
  Future<void> _sharePdf() async {
    final email = _email;
    if (email == null) return;
    try {
      await shareMailPdf(email);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'PDF paylaşma başarısız: ${friendlyErrorMessage(error)}',
          ),
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = AppTheme.colors(context);
    final email = _email;
    if (email == null) {
      // The mail genuinely isn't there (null without an error), or the
      // detail request itself failed — the two get different messages and
      // only a failure offers a retry.
      final error = _loadError;
      if (error == null) {
        return Center(
          child: Text(
            'Bu e-posta artık mevcut değil.',
            style: TextStyle(fontSize: 15, color: colors.secondaryText),
          ),
        );
      }
      final message = friendlyErrorMessage(error);
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.cloudOff, size: 40, color: colors.secondaryText),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Tekrar dene'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            email.subject,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          if (_thread.length > 1)
            _ThreadStack(
              messages: _thread,
              openedId: email.id,
              labelsFor: _labelsFor,
            )
          else
            _SingleMessage(email: email, labels: _labelsFor(email)),
        ],
      ),
    );
  }

  List<MailLabel> _labelsFor(Email email) =>
      _repo.getLabels().where((l) => email.labelIds.contains(l.id)).toList();
}

/// One mail in the classic detail layout (single-message conversations stay
/// simple — no collapsible header).
class _SingleMessage extends StatelessWidget {
  const _SingleMessage({required this.email, required this.labels});

  final Email email;
  final List<MailLabel> labels;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MailAvatar(
              identity: email.senderEmail,
              displayName: email.senderName,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.senderName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email.senderEmail,
                    style: TextStyle(fontSize: 13, color: colors.secondaryText),
                  ),
                  if (email.recipients.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _RecipientLine(
                      label: 'Alıcı: ',
                      addresses: recipientText(email.recipients),
                    ),
                  ],
                  if (email.cc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    _RecipientLine(
                      label: 'Cc: ',
                      addresses: recipientText(email.cc),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    formatMailDateFull(email.timestamp),
                    style: TextStyle(fontSize: 13, color: colors.secondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          _LabelChips(labels: labels),
        ],
        if (email.attachments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Ekler',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          _AttachmentList(email: email),
        ],
        const Divider(height: 32),
        const SizedBox(height: 4),
        if (email.remoteImageHosts.isNotEmpty &&
            !email.remoteImagesAllowed) ...[
          _RemoteContentBanner(email: email),
          const SizedBox(height: 12),
        ],
        _MessageBody(email: email),
      ],
    );
  }

  String recipientText(List<String> recipients) => recipients.join(', ');
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.email});

  final Email email;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final style = TextStyle(fontSize: 15, height: 1.6, color: colors.bodyText);
    final html = email.bodyHtml;
    if (html == null || html.trim().isEmpty) {
      return SelectableText(email.bodyText, style: style);
    }
    return SelectionArea(
      child: HtmlWidget(
        html,
        textStyle: style,
        factoryBuilder: () => MailLinkWidgetFactory(
          onLinkTap: (href, text) =>
              unawaited(MailLinkOpener.open(context, href, displayText: text)),
        ),
        customWidgetBuilder: (element) {
          if (element.localName != 'img') return null;
          final src = element.attributes['src'] ?? '';
          if (src.startsWith('data:')) return null;
          if (email.remoteImagesAllowed &&
              (src.startsWith('https://') || src.startsWith('http://'))) {
            return null;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _RemoteContentBanner extends StatefulWidget {
  const _RemoteContentBanner({required this.email});

  final Email email;

  @override
  State<_RemoteContentBanner> createState() => _RemoteContentBannerState();
}

class _RemoteContentBannerState extends State<_RemoteContentBanner> {
  bool _loading = false;
  Object? _error;

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppConfig.mailRepository.loadRemoteImages(widget.email.id);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      key: Key('remote-content-${widget.email.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bu mesaj uzaktaki görselleri içeriyor.'),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              friendlyErrorMessage(_error!),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            key: Key('load-remote-content-${widget.email.id}'),
            onPressed: _loading ? null : _load,
            child: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_error == null ? 'Görselleri yükle' : 'Tekrar dene'),
          ),
        ],
      ),
    );
  }
}

class _RecipientLine extends StatelessWidget {
  const _RecipientLine({required this.label, required this.addresses});

  final String label;
  final String addresses;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 13, color: colors.secondaryText),
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: addresses),
        ],
      ),
    );
  }
}

class _LabelChips extends StatelessWidget {
  const _LabelChips({required this.labels});

  final List<MailLabel> labels;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: label.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: label.color,
              ),
            ),
          ),
      ],
    );
  }
}

class _AttachmentList extends StatefulWidget {
  const _AttachmentList({required this.email});

  final Email email;

  @override
  State<_AttachmentList> createState() => _AttachmentListState();
}

class _AttachmentListState extends State<_AttachmentList> {
  @override
  void initState() {
    super.initState();
    _autoDownload();
  }

  @override
  void didUpdateWidget(covariant _AttachmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.email.id != widget.email.id ||
        oldWidget.email.attachments != widget.email.attachments) {
      _autoDownload();
    }
  }

  void _autoDownload() {
    unawaited(
      AttachmentAutoDownloader().onMailOpened(
        AppConfig.mailRepository,
        widget.email,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final attachment in widget.email.attachments)
        _AttachmentTile(mailId: widget.email.id, attachment: attachment),
    ],
  );
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.mailId, required this.attachment});

  final String mailId;
  final Attachment attachment;

  Future<void> _download(BuildContext context) async {
    try {
      await AppConfig.mailRepository.ensureAttachmentFile(mailId, attachment);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ek indirilemedi. Tekrar deneyin.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final repository = AppConfig.mailRepository;
    final content = Row(
      children: [
        Icon(LucideIcons.fileText, size: 20, color: colors.secondaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          attachment.sizeLabel,
          style: TextStyle(fontSize: 13, color: colors.secondaryText),
        ),
      ],
    );
    Widget tile(AttachmentDownloadState state) {
      Widget status = const SizedBox.shrink();
      Widget? action;
      if (state is AttachmentDownloading) {
        final percent = state.progress;
        status = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: percent),
            const SizedBox(height: 4),
            Text(
              percent == null ? 'İndiriliyor…' : '%${(percent * 100).round()}',
            ),
          ],
        );
        action = IconButton(
          tooltip: 'İndirmeyi iptal et',
          onPressed: () =>
              repository.cancelAttachmentDownload(mailId, attachment),
          icon: const Icon(LucideIcons.x, size: 18),
        );
      } else if (state is AttachmentCompleted) {
        status = const Text('Hazır');
      } else if (state is AttachmentFailed) {
        status = Text(
          state.message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
        if (state.retryable) {
          action = IconButton(
            tooltip: 'Tekrar dene',
            onPressed: () => _download(context),
            icon: const Icon(LucideIcons.rotateCw, size: 18),
          );
        }
      } else if (state is AttachmentCancelled) {
        status = const Text('İndirme iptal edildi.');
        action = IconButton(
          tooltip: 'Tekrar dene',
          onPressed: () => _download(context),
          icon: const Icon(LucideIcons.download, size: 18),
        );
      } else {
        action = IconButton(
          tooltip: 'Eki indir',
          onPressed: () => _download(context),
          icon: const Icon(LucideIcons.download, size: 18),
        );
      }
      return InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AttachmentPreviewScreen(mailId: mailId, attachment: attachment),
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: content),
                  ?action,
                ],
              ),
              if (state is AttachmentDownloading ||
                  state is AttachmentFailed ||
                  state is AttachmentCancelled ||
                  state is AttachmentCompleted)
                Align(alignment: Alignment.centerLeft, child: status),
            ],
          ),
        ),
      );
    }

    if (attachment.id == null) return tile(const AttachmentIdle());
    try {
      return ValueListenableBuilder<AttachmentDownloadState>(
        valueListenable: repository.attachmentDownloadState(mailId, attachment),
        builder: (context, state, _) => tile(state),
      );
    } on UnimplementedError {
      return tile(const AttachmentIdle());
    }
  }
}

/// Conversation as stacked cards, newest first. The newest message and the
/// one the user opened start expanded; the rest show a one-line preview.
class _ThreadStack extends StatefulWidget {
  const _ThreadStack({
    required this.messages,
    required this.openedId,
    required this.labelsFor,
  });

  final List<Email> messages;
  final String openedId;
  final List<MailLabel> Function(Email) labelsFor;

  @override
  State<_ThreadStack> createState() => _ThreadStackState();
}

class _ThreadStackState extends State<_ThreadStack> {
  /// Ids the user toggled away from their default state.
  final _toggled = <String>{};

  bool _expanded(Email m) {
    final byDefault =
        m.id == widget.openedId || m.id == widget.messages.first.id;
    return byDefault != _toggled.contains(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Column(
      children: [
        for (final m in widget.messages)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(top: 10),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Semantics(
                  // Announces the collapsed/expanded state change on tap —
                  // without this a screen reader gives no indication that
                  // the card hides or reveals the full message body.
                  expanded: _expanded(m),
                  child: InkWell(
                    onTap: () => setState(
                      () => _toggled.contains(m.id)
                          ? _toggled.remove(m.id)
                          : _toggled.add(m.id),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          MailAvatar(
                            identity: m.senderEmail,
                            displayName: m.senderName,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.senderName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (!_expanded(m))
                                  Text(
                                    stripQuotedReply(m.bodyText)
                                        .replaceAll('\n', ' '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.secondaryText,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            formatMailDateFull(m.timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_expanded(m))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _SingleMessage(
                      email: m,
                      labels: widget.labelsFor(m),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
