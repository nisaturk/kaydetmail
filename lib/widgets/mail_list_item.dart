import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/email.dart';
import '../models/mail_label.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import 'mail_avatar.dart';

/// One row in the mail list: avatar on the left, sender + subject + preview
/// on the right.
///
/// A tap anywhere on the row opens the mail; a long press anywhere on the
/// row enters selection mode. The avatar is purely visual (it shows a check
/// while [selected]) — there is deliberately no separate avatar gesture, so
/// the two never compete in the gesture arena.
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
    this.onLongPress,
    this.selected = false,
    this.accountLabel,
    this.folderLabel,
    this.threadCount,
    this.labels = const [],
  });

  final Email email;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  /// Originating mailbox shown as a tiny tertiary line (unified inbox only).
  /// Null hides the line so single-account lists stay exactly as before.
  final String? accountLabel;

  /// Folder the mail lives in, shown alongside [accountLabel] on the same
  /// tertiary line. Null hides it — folder-scoped lists (a single inbox
  /// screen) already know their folder from context.
  final String? folderLabel;

  /// Messages in the conversation this row represents. When > 1 the row
  /// aggregates the whole thread and a small `(n)` indicator appears.
  final int? threadCount;

  /// Labels attached to this mail, shown as small colored chips so a
  /// labeled mail is obvious without opening it.
  final List<MailLabel> labels;

  @override
  Widget build(BuildContext context) {
    final time = formatMailTime(email.timestamp);
    final meta = [?folderLabel, ?accountLabel].join(' · ');

    return Container(
      color: selected
          ? const Color(0xFFF3F4F6)
          : (email.isRead ? null : AppTheme.unreadBackground),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MailAvatar(
                identity: email.senderEmail,
                displayName: email.senderName,
                selected: selected,
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
                        if (email.isStarred) ...[
                          const Icon(
                            LucideIcons.star,
                            size: 14,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (email.isPinned) ...[
                          Icon(
                            LucideIcons.pin,
                            size: 14,
                            color: AppTheme.tertiaryText,
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (email.attachments.isNotEmpty ||
                            email.hasAttachments) ...[
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
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.tertiaryText,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        if (threadCount != null && threadCount! > 1) ...[
                          const SizedBox(width: 6),
                          Text(
                            '($threadCount)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.tertiaryText,
                            ),
                          ),
                        ],
                      ],
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
                    if (labels.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final label in labels)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: label.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                label.name,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: label.color,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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
