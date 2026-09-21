import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/chat_thread.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/mail_avatar.dart';
import 'attachment_preview_screen.dart';
import 'compose_screen.dart';

/// Full view of a mail — and, when it belongs to a conversation, the whole
/// thread as chat bubbles, oldest first.
///
/// Opening a mail marks it as read. Pin and read/unread state change through
/// the repository and are reflected immediately because the screen listens to
/// it. A single-message thread renders the plain detail view; a multi-message
/// conversation renders a chat, and tapping a bubble opens that full mail.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({super.key, required this.emailId});

  final String emailId;

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
        _thread = _mergeThread(loaded, _thread);
        _loading = false;
        _loadError = null;
      });
      _scrollToNewest();

      // A freshly opened mail becomes read — but only on the very first
      // load. Later reloads (pin, mark-as-unread) must not silently flip
      // it back.
      if (first) {
        _opened = true;
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
  /// and sorted oldest-first. The opened mail is always present, so a
  /// thread fetch can never remove what the user opened.
  static List<Email> _mergeThread(Email email, List<Email> others) {
    final byId = {for (final message in others) message.id: message};
    byId[email.id] = email;
    final merged = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
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
      final merged = _mergeThread(email, fetched);
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

  /// The conversation reads oldest-first like a chat, so land on the newest
  /// message whenever the thread grows.
  void _scrollToNewest() {
    if (_thread.length < 2 || _thread.length == _scrolledCount) return;
    _scrolledCount = _thread.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool _isOwn(Email email) => _repo.accounts.any(
    (a) => a.email.toLowerCase() == email.senderEmail.toLowerCase(),
  );

  void _openMessage(Email email) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          child: _SingleMessage(email: email, labels: _labelsFor(email)),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    await _reload();
  }

  /// Shows the pin-limit notice when no slot is left. Returns true when the
  /// caller may proceed with pinning.
  bool _ensurePinSlot() {
    if (_repo.getEmailsInFolder(MailFolder.pinned).length >=
        MailRepository.maxPinnedMails) {
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
    if (!email.isPinned && !_ensurePinSlot()) return;
    await _repo.setPinned([email.id], !email.isPinned);
  }

  Future<void> _toggleStar() async {
    final email = _email;
    if (email == null) return;
    // Star and pin are independent flags: starring never pins, unstarring
    // never unpins. Starring consumes no pin slot.
    await _repo.setStarred([email.id], !email.isStarred);
  }

  /// The address a reply/forward is sent from: the originating account, so a
  /// mail received on account B is never answered from account A.
  String? _originatingFrom() {
    final email = _email;
    if (email == null || email.accountId.isEmpty) return null;
    return _repo.getAccount(email.accountId)?.email;
  }

  void _reply() {
    final email = _email;
    if (email == null) return;
    _repo.markAsReplied([email.id]);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: 'Yanıtla',
          initialFrom: _originatingFrom(),
          initialTo: email.senderEmail,
          initialSubject: _replySubject(email.subject),
          initialThreadId: email.threadId,
          inReplyToId: email.id,
        ),
      ),
    );
  }

  void _forward() {
    final email = _email;
    if (email == null) return;
    _repo.markAsForwarded([email.id]);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(
          composeTitle: 'İlet',
          initialFrom: _originatingFrom(),
          initialSubject: _forwardSubject(email.subject),
          initialBody:
              '\n\n--- İletilen mesaj ---\nKimden: ${email.senderName} <${email.senderEmail}>\nKonu: ${email.subject}\n\n${email.bodyText}',
        ),
      ),
    );
  }

  static String _replySubject(String subject) {
    final s = subject.trim();
    if (s.toLowerCase().startsWith('re:')) return subject;
    return 'Re: $subject';
  }

  static String _forwardSubject(String subject) {
    final s = subject.trim();
    if (s.toLowerCase().startsWith('fwd:') ||
        s.toLowerCase().startsWith('ilet:')) {
      return subject;
    }
    return 'Fwd: $subject';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-posta'),
        actions: [
          if (_email != null)
            IconButton(
              onPressed: _toggleStar,
              tooltip: _email!.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
              icon: Icon(
                _email!.isStarred ? Icons.star : LucideIcons.star,
                color: _email!.isStarred ? Colors.amber : null,
              ),
            ),
          if (_email != null)
            IconButton(
              onPressed: _reply,
              tooltip: 'Yanıtla',
              icon: const Icon(LucideIcons.reply),
            ),
          if (_email != null)
            IconButton(
              onPressed: _forward,
              tooltip: 'İlet',
              icon: const Icon(LucideIcons.forward),
            ),
          if (_email != null)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreHorizontal),
              tooltip: 'Daha fazla',
              onSelected: (action) => _handleMenu(action),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pin',
                  child: Text(
                    _email!.isPinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                  ),
                ),
                PopupMenuItem(
                  value: 'star',
                  child: Text(
                    _email!.isStarred ? 'Yıldızı kaldır' : 'Yıldızla',
                  ),
                ),
                if (_email!.isRead)
                  const PopupMenuItem(
                    value: 'unread',
                    child: Text('Okunmadı olarak işaretle'),
                  )
                else
                  const PopupMenuItem(
                    value: 'read',
                    child: Text('Okundu olarak işaretle'),
                  ),
                const PopupMenuItem(value: 'label', child: Text('Etiketle')),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Future<void> _handleMenu(String action) async {
    if (action == 'read') {
      await _repo.markAsRead([widget.emailId]);
    } else if (action == 'unread') {
      await _repo.markAsUnread([widget.emailId]);
    } else if (action == 'pin') {
      await _togglePin();
    } else if (action == 'star') {
      await _toggleStar();
    } else if (action == 'label') {
      await showLabelPicker(context, emailIds: [widget.emailId]);
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final email = _email;
    if (email == null) {
      // The mail genuinely isn't there (null without an error), or the
      // detail request itself failed — the two get different messages and
      // only a failure offers a retry.
      final error = _loadError;
      if (error == null) {
        return const Center(
          child: Text(
            'Bu e-posta artık mevcut değil.',
            style: TextStyle(fontSize: 15, color: AppTheme.secondaryText),
          ),
        );
      }
      final message = error is ApiException
          ? error.userMessage
          : 'E-posta yüklenemedi. Lütfen tekrar deneyin.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.cloudOff,
                size: 40,
                color: AppTheme.secondaryText,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.black),
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
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          if (_thread.length > 1)
            ChatThread(messages: _thread, isOwn: _isOwn, onOpen: _openMessage)
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email.senderEmail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryText,
                    ),
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
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.secondaryText,
                    ),
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
          const Text(
            'Ekler',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          for (final attachment in email.attachments)
            _AttachmentTile(mailId: email.id, attachment: attachment),
        ],
        const Divider(height: 32),
        const SizedBox(height: 4),
        SelectableText(
          email.bodyText,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: AppTheme.bodyText,
          ),
        ),
      ],
    );
  }

  String recipientText(List<String> recipients) => recipients.join(', ');
}

class _RecipientLine extends StatelessWidget {
  const _RecipientLine({required this.label, required this.addresses});

  final String label;
  final String addresses;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 13, color: AppTheme.secondaryText),
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

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.mailId, required this.attachment});

  final String mailId;
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
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
        child: Row(
          children: [
            const Icon(
              LucideIcons.fileText,
              size: 20,
              color: AppTheme.secondaryText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
            Text(
              attachment.sizeLabel,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
