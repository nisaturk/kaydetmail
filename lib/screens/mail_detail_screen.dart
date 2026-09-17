import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
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
  bool _threadInit = false;
  bool _loading = true;
  bool _opened = false;

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

  Future<void> _reload() async {
    final email = await _repo.getEmail(widget.emailId);
    final thread = email == null ? const <Email>[] : _threadFor(email);
    if (!mounted) return;
    setState(() {
      _email = email;
      _thread = thread;
      _loading = false;
    });
    _initCollapsed();

    // A freshly opened mail becomes read — but only on the very first load.
    // Later reloads (pin, mark-as-unread) must not silently flip it back.
    if (email != null && !_opened) {
      _opened = true;
      if (!email.isRead) {
        await _repo.markAsRead([email.id]);
      }
    }
  }

  /// The conversation sorted oldest-first. Data is fetched from the
  /// repository, not just reconstructed, so shared [threadId]s (even across
  /// folders) join up; single threads are just themselves.
  List<Email> _threadFor(Email email) => _repo.getThreadEmails(email.threadId);

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
    setState(() {
      if (!_collapsed.remove(id)) _collapsed.add(id);
    });
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
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final email = _email;
    if (email == null) {
      return const Center(
        child: Text(
          'Bu e-posta artık mevcut değil.',
          style: TextStyle(fontSize: 15, color: AppTheme.secondaryText),
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
            _AttachmentTile(attachment: attachment),
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
                  _AttachmentTile(attachment: attachment),
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

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${attachment.name} indiriliyor (simülasyon)…'),
          ),
        );
      },
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
