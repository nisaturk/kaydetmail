import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/email.dart';
import '../screens/attachment_preview_screen.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_preview.dart';
import 'mail_avatar.dart';

/// A conversation as chat bubbles, oldest first: own messages on the right,
/// the other side's on the left. Consecutive messages from the same sender on
/// the same day are grouped (one avatar/name, tighter spacing) and days are
/// separated by a date pill. Tapping a bubble calls [onOpen] for the full mail.
class ChatThread extends StatelessWidget {
  const ChatThread({
    super.key,
    required this.messages,
    required this.isOwn,
    required this.onOpen,
  });

  final List<Email> messages;
  final bool Function(Email) isOwn;
  final void Function(Email) onOpen;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final previous = i > 0 ? messages[i - 1] : null;
      final newDay =
          previous == null || !_sameDay(previous.timestamp, message.timestamp);
      final startsGroup =
          newDay ||
          previous.senderEmail.toLowerCase() !=
              message.senderEmail.toLowerCase();
      if (newDay) children.add(_DaySeparator(message.timestamp));
      children.add(
        Padding(
          padding: EdgeInsets.only(top: startsGroup && !newDay ? 14 : 3),
          child: _Bubble(
            email: message,
            own: isOwn(message),
            showSender: startsGroup,
            onTap: () => onOpen(message),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

class _DaySeparator extends StatelessWidget {
  const _DaySeparator(this.day);

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.border,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${_two(day.day)}.${_two(day.month)}.${day.year}',
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.email,
    required this.own,
    required this.showSender,
    required this.onTap,
  });

  final Email email;
  final bool own;
  final bool showSender;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = email.timestamp;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: own
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!own && showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MailAvatar(
                      identity: email.senderEmail,
                      displayName: email.senderName,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        email.senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Material(
              color: own ? scheme.primaryContainer : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  // Shrink-wrap to the content so short messages get small
                  // bubbles; the time then right-aligns within that width.
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stripQuotedReply(email.bodyText),
                          maxLines: 12,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: AppTheme.bodyText,
                          ),
                        ),
                        for (final attachment in email.attachments)
                          _AttachmentChip(
                            mailId: email.id,
                            attachment: attachment,
                          ),
                        const SizedBox(height: 2),
                        Text(
                          '${_two(time.hour)}:${_two(time.minute)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.mailId, required this.attachment});

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
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.paperclip,
              size: 15,
              color: AppTheme.secondaryText,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  color: AppTheme.bodyText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
