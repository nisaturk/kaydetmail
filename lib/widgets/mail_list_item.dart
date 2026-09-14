import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/email.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'mail_avatar.dart';

/// One row in the mail list: avatar on the left, sender + subject + preview
/// on the right.
///
/// Unread mails use stronger typography, pinned mails show a pin icon.
class MailListItem extends StatelessWidget {
  const MailListItem({
    super.key,
    required this.email,
    this.onTap,
    this.onAvatarTap,
    this.selected = false,
  });

  final Email email;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final time = formatMailTime(email.timestamp);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!email.isRead)
              const Padding(
                padding: EdgeInsets.only(top: 14, right: 8),
                child: _UnreadDot(),
              ),
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
                        Icon(LucideIcons.pin,
                            size: 14, color: AppTheme.tertiaryText),
                        const SizedBox(width: 6),
                      ],
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
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
      ),
      margin: const EdgeInsets.only(top: 7),
    );
  }
}