import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../l10n/l10n.dart';

String? bulkPinLimitError(Iterable<Email> all, Iterable<String> selectedIds) {
  final selected = selectedIds.toSet();
  final pinnedPerAccount = <String, int>{};
  final addingPerAccount = <String, int>{};
  for (final email in all) {
    if (email.isPinned) {
      pinnedPerAccount[email.accountId] =
          (pinnedPerAccount[email.accountId] ?? 0) + 1;
    } else if (selected.contains(email.id)) {
      addingPerAccount[email.accountId] =
          (addingPerAccount[email.accountId] ?? 0) + 1;
    }
  }
  for (final MapEntry(key: account, value: adding)
      in addingPerAccount.entries) {
    final pinned = pinnedPerAccount[account] ?? 0;
    if (pinned + adding > MailRepository.maxPinnedMails) {
      final free = MailRepository.maxPinnedMails - pinned;
      return l10nNow.youCanPinAtMostEmailsPerAccount(
        MailRepository.maxPinnedMails,
        pinned,
        adding,
        free > 0 ? l10nNow.youCanPinMore(free) : '',
      );
    }
  }
  return null;
}
