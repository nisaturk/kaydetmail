import 'email.dart';

/// Which mails a list shows. Applied on top of the folder's own contents.
enum MailListFilter {
  all,
  unread,
  starred,
  attachments;

  bool matches(Email email) => switch (this) {
    MailListFilter.all => true,
    MailListFilter.unread => !email.isRead,
    MailListFilter.starred => email.isStarred,
    MailListFilter.attachments => email.hasAttachments,
  };
}

/// How a list is ordered. Pinned mail always stays on top, whatever the sort.
enum MailListSort { newest, oldest, unreadFirst, sender, subject }
