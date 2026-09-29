import '../models/email.dart';
import '../models/mail_list_view.dart';

/// Moves pinned mail to the top of an already newest-first list, keeping the
/// newest-first order inside both the pinned and the unpinned group (stable).
///
/// Pinning is per mail and per account (at most three per account), so in the
/// unified mailbox the pinned block simply holds every account's pins.
List<Email> pinnedFirst(Iterable<Email> newestFirst) {
  final pinned = <Email>[];
  final rest = <Email>[];
  for (final email in newestFirst) {
    (email.isPinned ? pinned : rest).add(email);
  }
  return pinned.isEmpty ? rest : [...pinned, ...rest];
}

/// Keeps only the mails [filter] accepts.
List<Email> applyMailListFilter(List<Email> mails, MailListFilter filter) =>
    filter == MailListFilter.all ? mails : mails.where(filter.matches).toList();

/// Orders [newestFirst] (the repository's default order) by [sort], with
/// pinned mail first in every mode. Ties keep the incoming newest-first
/// order because the sort is stable.
List<Email> sortMailList(List<Email> newestFirst, MailListSort sort) {
  if (sort == MailListSort.newest) return pinnedFirst(newestFirst);
  final indexed = [
    for (var i = 0; i < newestFirst.length; i++) (i, newestFirst[i]),
  ];
  int compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
  int byOrder(Email a, Email b) => switch (sort) {
    MailListSort.newest => 0,
    MailListSort.oldest => a.timestamp.compareTo(b.timestamp),
    MailListSort.unreadFirst => (a.isRead ? 1 : 0).compareTo(b.isRead ? 1 : 0),
    MailListSort.sender => compareText(
      a.senderName.isEmpty ? a.senderEmail : a.senderName,
      b.senderName.isEmpty ? b.senderEmail : b.senderName,
    ),
    MailListSort.subject => compareText(a.subject, b.subject),
  };
  indexed.sort((x, y) {
    if (x.$2.isPinned != y.$2.isPinned) return x.$2.isPinned ? -1 : 1;
    final byKey = byOrder(x.$2, y.$2);
    return byKey != 0 ? byKey : x.$1.compareTo(y.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
