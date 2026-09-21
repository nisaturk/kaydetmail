import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/label_picker_sheet.dart';
import '../widgets/mail_avatar.dart';
import 'compose_screen.dart';

/// Full view of a mail — and, when it belongs to a conversation, the whole
/// thread stacked oldest-first with collapsible messages.
///
/// Opening a mail marks it as read. Pin and read/unread state change through
/// the repository and are reflected immediately because the screen listens to
/// it. A single-message thread renders the plain detail view; a multi-message
/// conversation renders one row per message, older ones collapsed.
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
  final Set<String> _collapsed = {};

  /// Messages the user explicitly expanded/collapsed — thread enrichment
  /// never overrides those choices when it merges in more messages.
  final Set<String> _userToggled = {};
  bool _threadInit = false;
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
      _initCollapsed();

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
        _collapseAllButNewest();
      }
      _enrichedKey = key;
    } catch (e) {
      debugPrint('Thread enrichment failed for ${email.threadId}: $e');
    } finally {
      if (_enrichingKey == key) _enrichingKey = null;
    }
  }

  /// Older messages collapse on first load; the newest stays expanded. Mails
  /// that arrive later (e.g. a reply created from this thread) are naturally
  /// expanded because they were never collapsed.
  void _initCollapsed() {
    if (_threadInit) return;
    _threadInit = true;
    if (_thread.length < 2) return;
    setState(() {
      _collapsed.addAll(
        _thread.sublist(0, _thread.length - 1).map((e) => e.id),
      );
    });
  }

  void _toggleMessage(String id) {
    _userToggled.add(id);
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
    });
  }

  /// Collapses every message but the newest, leaving messages the user
  /// explicitly toggled alone. Used when enrichment merges in messages
  /// that arrived after the first render.
  void _collapseAllButNewest() {
    if (_thread.length < 2) return;
    final newest = _thread.last.id;
    setState(() {
      _collapsed.addAll(
        _thread
            .map((e) => e.id)
            .where((id) => id != newest && !_userToggled.contains(id)),
      );
    });
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
          if (_thread.length > 1) ...[
            for (final message in _thread.reversed)
              _ThreadMessage(
                email: message,
                labels: _labelsFor(message),
                expanded: !_collapsed.contains(message.id),
                onToggle: () => _toggleMessage(message.id),
              ),
          ] else
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

/// One collapsible message inside a conversation stack.
///
/// The header always shows the sender, address, timestamp and recipients; a
/// compact preview appears while collapsed. Expanded, the full body, labels
/// and attachments follow under a divider.
class _ThreadMessage extends StatelessWidget {
  const _ThreadMessage({
    required this.email,
    required this.labels,
    required this.expanded,
    required this.onToggle,
  });

  final Email email;
  final List<MailLabel> labels;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    String recipientText(List<String> recipients) => recipients.join(', ');
    return InkWell(
      onTap: onToggle,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              email.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            expanded
                                ? LucideIcons.chevronUp
                                : LucideIcons.chevronDown,
                            size: 16,
                            color: AppTheme.tertiaryText,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email.senderEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                      if (email.recipients.isNotEmpty) ...[
                        const SizedBox(height: 4),
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
                      const SizedBox(height: 4),
                      Text(
                        formatMailDateFull(email.timestamp),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                      if (!expanded) ...[
                        const SizedBox(height: 6),
                        Text(
                          email.preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.secondaryText,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 12),
              if (labels.isNotEmpty) ...[
                _LabelChips(labels: labels),
                const SizedBox(height: 10),
              ],
              if (email.attachments.isNotEmpty) ...[
                const Text(
                  'Ekler',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                for (final attachment in email.attachments)
                  _AttachmentTile(mailId: email.id, attachment: attachment),
                const SizedBox(height: 4),
              ],
              SelectableText(
                email.bodyText,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  color: AppTheme.bodyText,
                ),
              ),
            ],
          ],
        ),
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

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({required this.mailId, required this.attachment});

  final String mailId;
  final Attachment attachment;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _downloading = false;

  Future<void> _downloadAndShare() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await AppConfig.mailRepository.downloadAttachment(
        widget.mailId,
        widget.attachment,
      );
      if (!mounted) return;
      if (bytes.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Ek indirilemedi.')));
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: widget.attachment.name,
              mimeType: widget.attachment.mimeType,
            ),
          ],
          text: widget.attachment.name,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.status == 404 ? 'Ek bulunamadı.' : error.userMessage,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ek indirilemedi.')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _downloadAndShare,
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
                widget.attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
            if (_downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                widget.attachment.sizeLabel,
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
