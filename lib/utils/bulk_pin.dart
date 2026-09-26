import '../models/email.dart';
import '../repositories/mail_repository.dart';

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
      return 'Bir hesapta en fazla ${MailRepository.maxPinnedMails} e-posta '
          'sabitlenebilir. Şu an $pinned sabitli, $adding yeni seçildi'
          '${free > 0 ? '; en fazla $free tane daha sabitleyebilirsiniz' : ''}.'
          ' Hiçbiri sabitlenmedi.';
    }
  }
  return null;
}
