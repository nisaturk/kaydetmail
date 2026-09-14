import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/mail_avatar.dart';

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

    // A freshly opened mail becomes read.
    if (email != null && !email.isRead) {
      await _repo.markAsRead([email.id]);
    }
  }

  Future<void> _togglePin() async {
    final email = _email;
    if (email == null) return;
    await _repo.setPinned([email.id], !email.isPinned);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mail'),
        actions: [
          if (_email != null)
            IconButton(
              onPressed: _togglePin,
              tooltip: _email!.isPinned ? 'Unpin' : 'Pin',
              icon: Icon(
                _email!.isPinned ? LucideIcons.star : LucideIcons.pin,
              ),
            ),
          if (_email != null)
            PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical),
              onSelected: (action) => _handleMenu(action),
              itemBuilder: (context) => [
                if (_email!.isRead)
                  const PopupMenuItem(
                    value: 'unread',
                    child: Text('Mark as unread'),
                  )
                else
                  const PopupMenuItem(
                    value: 'read',
                    child: Text('Mark as read'),
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
          'This mail is no longer available.',
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
                    const SizedBox(height: 2),
                    Text(
                      _recipientLabel(email),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.secondaryText,
                      ),
                    ),
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
              'Attachments',
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
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  String _recipientLabel(Email email) {
    final to = email.recipients.join(', ');
    return 'To: $to';
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
            content: Text('Downloading ${attachment.name} (simulated)…'),
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Icon(LucideIcons.fileText,
                size: 20, color: AppTheme.secondaryText),
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