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

/// Full view of a single mail: header, subject, labels, attachments and body.
///
/// Opening a mail marks it as read. Pin and read/unread state change through
/// the repository and are reflected immediately because the screen listens to
/// it.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({super.key, required this.emailId});

  final String emailId;

  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  Email? _email;
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
    if (!mounted) return;
    setState(() {
      _email = email;
      _loading = false;
    });

    // A freshly opened mail becomes read — but only on the very first load.
    // Later reloads (pin, mark-as-unread) must not silently flip it back.
    if (email != null && !_opened) {
      _opened = true;
      if (!email.isRead) {
        await _repo.markAsRead([email.id]);
      }
    }
  }

  /// Shows the pin-limit notice when no slot is left. Returns true when the
  /// caller may proceed with pinning/starring.
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
    // Star and pin are independent: starring consumes no pin slot.
    final starred = email.isStarred || email.isPinned;
    await _repo.setStarred([email.id], !starred);
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
                    (_email!.isStarred || _email!.isPinned)
                        ? 'Yıldızı kaldır'
                        : 'Yıldızla',
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

    final labels = _repo
        .getLabels()
        .where((l) => email.labelIds.contains(l.id))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        addresses: _recipientText(email.recipients),
                      ),
                    ],
                    if (email.cc.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      _RecipientLine(
                        label: 'Cc: ',
                        addresses: _recipientText(email.cc),
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
          const SizedBox(height: 20),
          Text(
            email.subject,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.25,
            ),
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
      ),
    );
  }

  String _recipientText(List<String> recipients) => recipients.join(', ');
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
