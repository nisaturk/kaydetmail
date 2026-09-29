import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/compose_prefill.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../utils/mail_pdf_export.dart';
import '../utils/mail_threads.dart';
import '../utils/mail_unsubscribe.dart';
import '../widgets/move_folder_sheet.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/mail_avatar.dart';
import '../widgets/mail_authentication_row.dart';
import '../widgets/permanent_delete_dialog.dart';
import '../widgets/snooze_picker.dart';
import 'compose_screen.dart';
import 'mail_inspection_screen.dart';
import 'mail_detail/message_body.dart';
import 'mail_detail/quick_reply.dart';
import 'mail_detail/message_parts.dart';


/// Full view of the opened mail followed by older messages in its conversation.
/// Opening marks the selected mail as read; enrichment appends older history
/// without moving the reader's scroll position.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.emailId,
    this.seed,
    this.openReplyOnLoad = false,
    this.currentCustomFolderId,
    this.showAppBar = true,
  });

  final String emailId;

  /// Mail list snapshot shown synchronously while full detail revalidates.
  final Email? seed;
  final bool openReplyOnLoad;

  final String? currentCustomFolderId;

  /// Wide mailbox layouts provide their own app bar.
  final bool showAppBar;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  Email? _email;
  List<Email> _thread = const [];

  /// Last server conversation fetch. Kept apart from [_thread] so a reload
  /// rebuilds from server + current cache: a local send echo the cache has
  /// since replaced with the real Sent copy must not linger as a duplicate.
  List<Email> _fetchedThread = const [];
  final _scroll = ScrollController();

  /// Enrichment adds history below the opened mail; never reset scroll.
  bool _loading = true;
  bool _opened = false;

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

  void _watchBackgroundMutation(
    Future<void> operation, {
    String? successMessage,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    unawaited(() async {
      try {
        await operation;
        if (successMessage != null && messenger.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(successMessage)));
        }
      } catch (error) {
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
            ),
          );
        }
      }
    }());
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null && seed.id == widget.emailId) {
      _email = seed;
      _thread = _mergeThread(seed, _repo.getThreadEmails(seed.threadId));
      _loading = false;
    }
    _repo.addListener(_syncCachedMail);
    _reload();
  }

  @override
  void dispose() {
    _repo.removeListener(_syncCachedMail);
    _scroll.dispose();
    super.dispose();
  }

  /// Repository notifications already carry local optimistic state; fetching
  /// detail on every flag change would trigger an avoidable IMAP round trip.
  void _syncCachedMail() {
    if (!mounted || _email == null) return;
    for (final email in _repo.getAllEmails()) {
      if (email.id != widget.emailId) continue;
      // Other messages may have changed star/read state even if opened mail
      // itself is identical; rebuild history from the repository snapshot.
      setState(() {
        _email = email;
        _thread = _mergeThread(email, [
          ..._fetchedThread.where((e) => e.threadId == email.threadId),
          ..._repo.getThreadEmails(email.threadId),
        ]);
      });
      return;
    }
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
          ..._fetchedThread.where((e) => e.threadId == loaded.threadId),
          ..._repo.getThreadEmails(loaded.threadId),
        ]);
        _loading = false;
        _loadError = null;
      });

      // A freshly opened mail becomes read — but only on the very first
      // load. Later reloads (pin, mark-as-unread) must not silently flip
      // it back.
      if (first) {
        _opened = true;
        if (widget.openReplyOnLoad) unawaited(_reply());
        if (!loaded.isRead) {
          _watchBackgroundMutation(_repo.markAsRead([loaded.id]));
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

  /// Server conversation order breaks timestamp ties; until enrichment,
  /// equal-time cache entries cannot safely be identified as older.
  List<Email> _mergeThread(Email email, List<Email> others) {
    final positions = <String, int>{
      for (var i = 0; i < _fetchedThread.length; i++) _fetchedThread[i].id: i,
    };
    final openedIndex = positions[email.id];
    final byId = {for (final message in others) message.id: message}
      ..remove(email.id);
    final older =
        byId.values.where((message) {
          final index = positions[message.id];
          if (openedIndex != null && index != null) return index < openedIndex;
          return message.timestamp.isBefore(email.timestamp);
        }).toList()..sort((a, b) {
          final byDate = b.timestamp.compareTo(a.timestamp);
          if (byDate != 0) return byDate;
          return (positions[b.id] ?? -1).compareTo(positions[a.id] ?? -1);
        });
    return List.unmodifiable([email, ...older]);
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
      _fetchedThread = fetched;
      final merged = _mergeThread(email, [
        ...fetched,
        ..._repo.getThreadEmails(email.threadId),
      ]);
      debugPrint('Thread ${email.threadId}: ${merged.length} messages');
      if (!_sameIds(merged, _thread)) {
        setState(() => _thread = merged);
      }
      _enrichedKey = key;
    } catch (e) {
      debugPrint('Thread enrichment failed for ${email.threadId}: $e');
    } finally {
      if (_enrichingKey == key) _enrichingKey = null;
    }
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
    _watchBackgroundMutation(_repo.setPinned([email.id], !email.isPinned));
  }

  Future<void> _toggleStar() async {
    final email = _email;
    if (email == null) return;
    // Star and pin are independent flags: starring never pins, unstarring
    // never unpins. Starring consumes no pin slot.
    _watchBackgroundMutation(_repo.setStarred([email.id], !email.isStarred));
  }

  /// Snoozed mail is hidden from normal folder views until its backend-owned
  /// deadline. State changes locally immediately while the backend request
  /// continues in the background.
  Future<void> _toggleSnooze() async {
    final email = _email;
    if (email == null) return;
    if (_repo.snoozedUntilOf(email.id) != null) {
      _watchBackgroundMutation(_repo.setSnoozed([email.id], null));
      return;
    }
    final until = await showSnoozePicker(context);
    if (until == null || !mounted) return;
    _watchBackgroundMutation(_repo.setSnoozed([email.id], until));
    unawaited(Navigator.of(context).maybePop().then<void>((_) {}));
  }

  Future<void> _moveMail() async {
    final email = _email;
    if (email == null) return;
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
    final custom = target.customFolder;
    final operation = custom != null
        ? _repo.moveToCustomFolder(
            [email.id],
            accountId: custom.accountId,
            folderId: custom.folderId,
          )
        : target.folder == MailFolder.trash
        ? _repo.moveToTrash([email.id])
        : _repo.moveToFolder([email.id], target.folder!);
    _watchBackgroundMutation(
      operation,
      successMessage: 'E-posta ${target.label} klasörüne taşındı.',
    );
    unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
  }

  /// Moves the open mail back to the inbox. For a mail whose current
  /// folder is Trash or Spam, `MailRepository.moveToFolder` resolves this
  /// to the backend's restore action (the mail's original pre-trash/spam
  /// folder), not a literal move to Inbox — see the repository doc
  /// comment. Restore / "Spam değil" / "Arşivden çıkar" all reduce to
  /// this one call.
  Future<void> _moveToInbox(String successMessage) async {
    final email = _email;
    if (email == null) return;
    _watchBackgroundMutation(
      _repo.moveToFolder([email.id], MailFolder.inbox),
      successMessage: successMessage,
    );
    unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
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
          onPressed: () => _moveToInbox('E-posta geri yüklendi.'),
          tooltip: 'Geri yükle',
          icon: const Icon(LucideIcons.rotateCcw),
        );
      case MailFolder.spam:
        return IconButton(
          onPressed: () =>
              _moveToInbox('E-posta spam değil olarak işaretlendi.'),
          tooltip: 'Spam değil',
          icon: const Icon(LucideIcons.shieldOff),
        );
      case MailFolder.archive:
        return IconButton(
          onPressed: () => _moveToInbox('E-posta arşivden çıkarıldı.'),
          tooltip: 'Arşivden çıkar',
          icon: const Icon(LucideIcons.archiveRestore),
        );
      default:
        return null;
    }
  }

  /// The address a reply/forward is sent from: the originating account, so a
  /// mail received on account B is never answered from account A.
  String? _originatingFrom([Email? target]) {
    final email = target ?? _email;
    if (email == null || email.accountId.isEmpty) return null;
    return _repo.getAccount(email.accountId)?.email;
  }

  /// Opens `ComposeScreen` prefilled from the backend's compose context
  /// (`GET /api/mails/{id}/compose/{mode}`) instead of recomputing
  /// recipients/subject/threading client-side — see docs-dev spec §4.
  /// [mode] is `'reply'`, `'reply-all'` or `'forward'`.
  Future<void> _openComposePrefill(
    String mode, {
    required String title,
    Email? target,
  }) async {
    final email = target ?? _email;
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
    final sender = prefill.originalFrom ?? email.senderEmail;
    final subject = prefill.originalSubject ?? email.subject;
    final formattedDate = prefill.originalDate == null
        ? null
        : formatMailDateFull(prefill.originalDate!);
    final originalHtml = email.bodyHtml?.trim().isNotEmpty == true
        ? email.bodyHtml!
        : htmlEscape.convert(email.bodyText).replaceAll('\n', '<br>');
    var initialBody = '';
    String? initialBodyHtml;
    var initialAttachments = const <Attachment>[];
    if (isForward) {
      final dateLine = formattedDate == null ? '' : 'Tarih: $formattedDate\n';
      initialBody =
          '\n\n--- İletilen mesaj ---\n'
          'Kimden: $sender\n'
          '$dateLine'
          'Konu: $subject\n\n'
          '${email.bodyText}';
      initialBodyHtml =
          '<p><br></p><p>--- İletilen mesaj ---<br>'
          '<strong>Kimden:</strong> ${htmlEscape.convert(sender)}<br>'
          '${formattedDate == null ? '' : '<strong>Tarih:</strong> ${htmlEscape.convert(formattedDate)}<br>'}'
          '<strong>Konu:</strong> ${htmlEscape.convert(subject)}</p>'
          '$originalHtml';
      initialAttachments = prefill.attachments;
    } else {
      final attribution =
          '${formattedDate == null ? '' : '$formattedDate tarihinde '}'
          '$sender yazdı:';
      initialBody =
          '\n\n$attribution\n> ${email.bodyText.replaceAll('\n', '\n> ')}';
      initialBodyHtml =
          '<p><br></p><p>${htmlEscape.convert(attribution)}</p>'
          '<blockquote>$originalHtml</blockquote>';
    }

    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: title,
          initialFrom: _originatingFrom(email),
          initialTo: prefill.to.join(', '),
          initialCc: prefill.cc.join(', '),
          initialSubject: prefill.suggestedSubject,
          initialBody: initialBody,
          initialBodyHtml: initialBodyHtml,
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
      appBar: widget.showAppBar ? AppBar(actions: _appBarActions()) : null,
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
      if (email.folder != MailFolder.archive &&
          email.folder != MailFolder.trash &&
          email.folder != MailFolder.spam)
        IconButton(
          onPressed: () {
            _watchBackgroundMutation(
              _repo.moveToFolder([email.id], MailFolder.archive),
            );
            unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
          },
          tooltip: 'Arşivle',
          icon: const Icon(LucideIcons.archive),
        ),
      if (email.folder != MailFolder.trash)
        IconButton(
          onPressed: () {
            _watchBackgroundMutation(_repo.moveToTrash([email.id]));
            unawaited(Navigator.of(context).maybePop(true).then<void>((_) {}));
          },
          tooltip: 'Sil',
          icon: const Icon(LucideIcons.trash2),
        ),
      IconButton(
        onPressed: () => _watchBackgroundMutation(
          email.isRead
              ? _repo.markAsUnread([email.id])
              : _repo.markAsRead([email.id]),
        ),
        tooltip: email.isRead
            ? 'Okunmadı olarak işaretle'
            : 'Okundu olarak işaretle',
        icon: Icon(email.isRead ? LucideIcons.mail : LucideIcons.mailOpen),
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
            value: 'reply',
            enabled: !_composeActionBusy,
            child: const Text('Yanıtla'),
          ),
          PopupMenuItem(
            value: 'forward',
            enabled: !_composeActionBusy,
            child: const Text('İlet'),
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
          PopupMenuItem(
            value: 'snooze',
            child: Text(
              _repo.snoozedUntilOf(email.id) != null
                  ? 'Ertelemeyi kaldır'
                  : 'Ertele',
            ),
          ),
          if (email.folder != MailFolder.drafts)
            const PopupMenuItem(value: 'move', child: Text('Move to')),
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
          const PopupMenuItem(
            value: 'all_headers',
            child: Text('Tüm başlıkları göster'),
          ),
          const PopupMenuItem(
            value: 'raw_mime',
            child: Text('Ham MIME göster'),
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
    if (action == 'reply') {
      await _reply();
    } else if (action == 'forward') {
      await _forward();
    } else if (action == 'reply_all') {
      await _replyAll();
    } else if (action == 'read') {
      _watchBackgroundMutation(_repo.markAsRead([widget.emailId]));
    } else if (action == 'unread') {
      _watchBackgroundMutation(_repo.markAsUnread([widget.emailId]));
    } else if (action == 'pin') {
      await _togglePin();
    } else if (action == 'star') {
      await _toggleStar();
    } else if (action == 'snooze') {
      await _toggleSnooze();
    } else if (action == 'label') {
      await showLabelPicker(context, emailIds: _conversationIds);
    } else if (action == 'unlabel') {
      _watchBackgroundMutation(removeAllLabels(_repo, _conversationIds));
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
    } else if (action == 'all_headers' || action == 'raw_mime') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MailInspectionScreen(
            mailId: widget.emailId,
            mode: action == 'all_headers'
                ? MailInspectionMode.headers
                : MailInspectionMode.source,
            repository: _repo,
          ),
        ),
      );
    }
  }

  /// Expunge stays visible until server confirms deletion.
  Future<void> _deleteForever() async {
    final ids = idsInFolder(_repo, _conversationIds, MailFolder.trash);
    if (ids.isEmpty) return;
    final confirmed = await confirmPermanentDelete(context, ids.length);
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.deletePermanently(ids);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('E-posta kalıcı olarak silindi.')),
      );
      await Navigator.of(context).maybePop();
    } catch (error) {
      if (messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('İşlem başarısız: ${friendlyErrorMessage(error)}'),
          ),
        );
      }
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

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _thread.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              email.subject,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.2,
              ),
            ),
          );
        }
        if (index == 2) {
          return email.folder == MailFolder.drafts
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: QuickReply(
                    email: email,
                    from: _originatingFrom(email),
                  ),
                );
        }
        final message = index == 1 ? _thread.first : _thread[index - 2];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 2)
              Divider(height: 24, thickness: 0.5, color: colors.border),
            _SingleMessage(
              email: message,
              ownAddress: _originatingFrom(message),
              labels: _labelsFor(message),
              collapseQuoted: _thread.length > 1,
              onCompose: (mode, title) =>
                  _openComposePrefill(mode, title: title, target: message),
              onStar: () => _watchBackgroundMutation(
                _repo.setStarred([message.id], !message.isStarred),
              ),
            ),
          ],
        );
      },
    );
  }

  List<MailLabel> _labelsFor(Email email) =>
      _repo.getLabels().where((l) => email.labelIds.contains(l.id)).toList();
}

/// Full message, never a collapsible conversation card.
class _SingleMessage extends StatefulWidget {
  const _SingleMessage({
    required this.email,
    required this.ownAddress,
    required this.labels,
    required this.onCompose,
    required this.onStar,
    this.collapseQuoted = false,
  });

  final Email email;
  final String? ownAddress;
  final List<MailLabel> labels;
  final bool collapseQuoted;
  final Future<void> Function(String mode, String title) onCompose;
  final VoidCallback onStar;

  @override
  State<_SingleMessage> createState() => _SingleMessageState();
}

class _SingleMessageState extends State<_SingleMessage> {
  bool _detailsVisible = false;

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final labels = widget.labels;
    final collapseQuoted = widget.collapseQuoted;
    final colors = AppTheme.colors(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            MailAvatar(
              identity: email.senderEmail,
              displayName: email.senderName,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  TextButton.icon(
                    key: Key('message-recipients-${email.id}'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: colors.secondaryText,
                    ),
                    onPressed: () =>
                        setState(() => _detailsVisible = !_detailsVisible),
                    iconAlignment: IconAlignment.end,
                    icon: Icon(
                      _detailsVisible
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 12,
                    ),
                    label: Text(
                      _recipientSummary(email.recipients, widget.ownAddress),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text(
                formatMailTime(email.timestamp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.secondaryText),
              ),
            ),
            IconButton(
              onPressed: widget.onStar,
              tooltip: email.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: Icon(
                email.isStarred ? Icons.star : Icons.star_outline,
                color: email.isStarred ? Colors.amber : null,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'İleti işlemleri',
              iconSize: 20,
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (mode) => widget.onCompose(
                mode,
                mode == 'forward'
                    ? 'İlet'
                    : mode == 'reply-all'
                    ? 'Tümünü Yanıtla'
                    : 'Yanıtla',
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reply', child: Text('Yanıtla')),
                PopupMenuItem(
                  value: 'reply-all',
                  child: Text('Tümünü Yanıtla'),
                ),
                PopupMenuItem(value: 'forward', child: Text('İlet')),
              ],
            ),
          ],
        ),
        if (_detailsVisible)
          Padding(
            padding: const EdgeInsets.only(left: 46, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecipientLine(label: 'Kimden: ', addresses: email.senderEmail),
                if (email.recipients.isNotEmpty)
                  RecipientLine(
                    label: 'Alıcı: ',
                    addresses: email.recipients.join(', '),
                  ),
                if (email.cc.isNotEmpty)
                  RecipientLine(label: 'Cc: ', addresses: email.cc.join(', ')),
                if (email.bcc.isNotEmpty)
                  RecipientLine(
                    label: 'Bcc: ',
                    addresses: email.bcc.join(', '),
                  ),
                RecipientLine(
                  label: 'Tarih: ',
                  addresses: formatMailDateFull(email.timestamp),
                ),
              ],
            ),
          ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          LabelChips(labels: labels),
        ],
        if (email.authentication case final authentication?) ...[
          const SizedBox(height: 8),
          MailAuthenticationRow(authentication: authentication),
        ],
        if (email.security case final security?) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(LucideIcons.lock, size: 20),
            title: Text(
              [
                if (security.signed case final signed?)
                  '${signed == 'SMime' ? 'S/MIME' : 'OpenPGP'} imzalı (doğrulanmadı)',
                if (security.encrypted case final encrypted?)
                  '${encrypted == 'SMime' ? 'S/MIME' : 'OpenPGP'} şifreli (açılamıyor)',
              ].join(' · '),
            ),
            onTap: security.signed == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MailInspectionScreen(
                        mailId: email.id,
                        mode: MailInspectionMode.signature,
                        repository: AppConfig.mailRepository,
                      ),
                    ),
                  ),
          ),
        ],
        const SizedBox(height: 2),
        if (email.trackingPixelHosts.isNotEmpty) ...[
          Row(
            children: [
              const Icon(LucideIcons.eyeOff, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Takip içeriği engellendi')),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (email.remoteImageHosts.isNotEmpty &&
            !email.remoteImagesAllowed) ...[
          RemoteContentBanner(email: email),
          const SizedBox(height: 12),
        ],
        MessageBody(email: email, collapseQuoted: collapseQuoted),
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
          AttachmentList(email: email),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              TextButton.icon(
                key: Key('message-reply-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () => widget.onCompose('reply', 'Yanıtla'),
                icon: const Icon(LucideIcons.reply, size: 16),
                label: const Text('Yanıtla'),
              ),
              TextButton.icon(
                key: Key('message-reply-all-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () =>
                    widget.onCompose('reply-all', 'Tümünü Yanıtla'),
                icon: const Icon(LucideIcons.replyAll, size: 16),
                label: const Text('Tümünü yanıtla'),
              ),
              TextButton.icon(
                key: Key('message-forward-${email.id}'),
                style: _actionStyle(colors),
                onPressed: () => widget.onCompose('forward', 'İlet'),
                icon: const Icon(LucideIcons.forward, size: 16),
                label: const Text('İlet'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ButtonStyle _actionStyle(AppColors colors) => TextButton.styleFrom(
    foregroundColor: colors.secondaryText,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    minimumSize: const Size(0, 40),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
  );

  String _recipientSummary(List<String> recipients, String? ownAddress) {
    if (recipients.isEmpty) return 'alıcı yok';
    if (ownAddress != null &&
        recipients.any((recipient) {
          final address = recipient.contains('<')
              ? recipient.split('<').last.split('>').first.trim()
              : recipient.trim();
          return address.toLowerCase() == ownAddress.toLowerCase();
        })) {
      return 'bana';
    }
    final first = recipients.first;
    final name = first.contains('<')
        ? first.substring(0, first.indexOf('<')).trim().replaceAll('"', '')
        : first.split('@').first;
    return name.isEmpty ? first : "$name'ye";
  }
}
