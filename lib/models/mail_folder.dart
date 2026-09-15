import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Logical mail folders shown in the app drawer.
///
/// [pinned] is not a real folder on the server — it groups every pinned mail
/// regardless of the folder it actually lives in.
enum MailFolder {
  inbox,
  sent,
  pinned,
  drafts,
  trash,
  spam,
  archive;

  String get label => switch (this) {
        MailFolder.inbox => 'Gelen Kutusu',
        MailFolder.sent => 'Gönderilenler',
        MailFolder.pinned => 'Yıldızlılar',
        MailFolder.drafts => 'Taslaklar',
        MailFolder.trash => 'Çöp Kutusu',
        MailFolder.spam => 'Spam',
        MailFolder.archive => 'Arşiv',
      };

  IconData get icon => switch (this) {
        MailFolder.inbox => LucideIcons.inbox,
        MailFolder.sent => LucideIcons.send,
        MailFolder.pinned => LucideIcons.star,
        MailFolder.drafts => LucideIcons.fileText,
        MailFolder.trash => LucideIcons.trash2,
        MailFolder.spam => LucideIcons.shieldAlert,
        MailFolder.archive => LucideIcons.archive,
      };
}