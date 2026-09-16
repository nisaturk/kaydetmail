import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/email.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'mail_avatar.dart';

/// One row in the mail list: avatar on the left, sender + subject + preview
/// on the right.
///
/// Unread mails use stronger typography over a very slightly darker
/// background; the row structure is identical either way. Pinned mails show
/// a pin icon and mails with attachments show a paperclip. While [selected]
/// the row gets a light background in addition to the avatar check.
class MailListItem extends StatelessWidget {
  const MailListItem({
    super.key,
    required this.email,
    this.onTap,
    this.onAvatarTap,
    this.selected = false,
    this.accountLabel,
  });

  final Email email;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;
  final bool selected;

  /// Originating mailbox shown as a tiny tertiary line (unified inbox only).
  /// Null hides the line so single-account lists stay exactly as before.
  final String? accountLabel;

  @override
  Widget build(BuildContext context) {
    final time = formatMailTime(email.timestamp);

    return Container(
      color: selected
          ? const Color(0xFFF3F4F6)
          : (email.isRead ? null : AppTheme.unreadBackground),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onAvatarTap,
                behavior: HitTestBehavior.opaque,
                child: MailAvatar(
                  identity: email.senderEmail,
                  displayName: email.senderName,
                  selected: selected,
                ),
              ),
              const SizedBox(width: 12),
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
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: email.isRead
                                  ? FontWeight.w400
                                  : FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (email.isPinned) ...[
                          Icon(
                            LucideIcons.pin,
                            size: 14,
                            color: AppTheme.tertiaryText,
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (email.attachments.isNotEmpty) ...[
                          Icon(
                            LucideIcons.paperclip,
                            size: 13,
                            color: AppTheme.tertiaryText,
                          ),
                          const SizedBox(width: 6),
                        ],
                        _StatusIcons(email: email),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: email.isRead
                                ? FontWeight.w400
                                : FontWeight.w700,
                            color: email.isRead
                                ? AppTheme.secondaryText
                                : Colors.black,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (accountLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          accountLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.tertiaryText,
                          ),
                        ),
                      ),
                    Text(
                      email.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: email.isRead
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: email.isRead
                            ? AppTheme.secondaryText
                            : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact secondary status icons: read/unread + replied + forwarded.
///
/// All small, tertiary (except unread), never dominating sender/subject.
/// Read and unread variants share the same size so rows stay aligned.
class _StatusIcons extends StatelessWidget {
  const _StatusIcons({required this.email});

  final Email email;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          email.isRead ? LucideIcons.mailOpen : LucideIcons.mail,
          size: 13,
          color: email.isRead ? AppTheme.tertiaryText : Colors.black,
        ),
        if (email.isReplied) ...[
          const SizedBox(width: 5),
          const Icon(LucideIcons.reply, size: 13, color: AppTheme.tertiaryText),
        ],
        if (email.isForwarded) ...[
          const SizedBox(width: 5),
          const Icon(
            LucideIcons.forward,
            size: 13,
            color: AppTheme.tertiaryText,
          ),
        ],
        const SizedBox(width: 6),
      ],
    );
  }
}
