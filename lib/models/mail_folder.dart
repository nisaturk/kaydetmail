import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/l10n.dart';

/// Logical mail folders shown in the app drawer.
///
/// [starred] is not a real folder on the server — it groups every starred
/// mail regardless of the folder it actually lives in.
enum MailFolder {
  inbox,
  all,
  sent,
  starred,
  snoozed,
  drafts,
  trash,
  spam,
  archive;

  String get label => switch (this) {
    MailFolder.inbox => l10nNow.inbox,
    MailFolder.all => l10nNow.allMail,
    MailFolder.sent => l10nNow.outbox,
    MailFolder.starred => l10nNow.starred,
    MailFolder.snoozed => l10nNow.snoozed,
    MailFolder.drafts => l10nNow.drafts,
    MailFolder.trash => l10nNow.trash,
    MailFolder.spam => 'Spam',
    MailFolder.archive => l10nNow.archive,
  };

  IconData get icon => switch (this) {
    MailFolder.inbox => LucideIcons.inbox,
    MailFolder.all => LucideIcons.mail,
    MailFolder.sent => LucideIcons.send,
    MailFolder.starred => LucideIcons.star,
    MailFolder.snoozed => LucideIcons.clock,
    MailFolder.drafts => LucideIcons.fileText,
    MailFolder.trash => LucideIcons.trash2,
    MailFolder.spam => LucideIcons.shieldAlert,
    MailFolder.archive => LucideIcons.archive,
  };
}
