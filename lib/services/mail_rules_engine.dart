import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_rule.dart';
import '../repositories/mail_repository.dart';
import 'mail_rules_store.dart';

/// Client-side filter/rule engine: "mail from X -> move to folder / apply
/// label", evaluated against newly-synced mail. Runs whenever the app is
/// open and syncing (background timer, pull-to-refresh, a push-triggered
/// refresh) — see the call site in `app.dart`'s `_syncLoadedFolders`.
///
/// There is no server-side equivalent (same rationale as labels — see
/// `LocalMailFlagsStore`): rules only fire while this app is running.
///
/// Only Inbox is ever scanned, which makes re-running this on every sync
/// tick safe without any extra "already processed" bookkeeping: once a
/// `moveToFolder` rule moves a mail out of Inbox it naturally never comes
/// up again, and an `addLabel` rule is skipped for mail that already
/// carries the target label.
class MailRulesEngine {
  MailRulesEngine._();

  static final MailRulesEngine instance = MailRulesEngine._();

  Future<void> evaluateNewMail(MailRepository repo) async {
    final inbox = repo.getEmailsInFolder(MailFolder.inbox);
    if (inbox.isEmpty) return;

    final byAccount = <String, List<Email>>{};
    for (final email in inbox) {
      if (email.accountId.isEmpty) continue;
      byAccount.putIfAbsent(email.accountId, () => []).add(email);
    }

    for (final entry in byAccount.entries) {
      final rules = await MailRulesStore.readRules(entry.key);
      if (rules.isEmpty) continue;
      for (final rule in rules) {
        await _apply(repo, rule, entry.value);
      }
    }
  }

  Future<void> _apply(
    MailRepository repo,
    MailRule rule,
    List<Email> candidates,
  ) async {
    final matched = candidates.where(rule.matches);
    switch (rule.action.type) {
      case MailRuleActionType.moveToFolder:
        final ids = [for (final email in matched) email.id];
        if (ids.isEmpty) return;
        try {
          await repo.moveToFolder(ids, rule.action.folder!);
        } catch (_) {
          // Best-effort: a bad/stale rule must never break the sync tick
          // for every other rule and account (same rationale as
          // MailRepository.unregisterDevice).
        }
      case MailRuleActionType.addLabel:
        final labelId = rule.action.labelId!;
        final ids = [
          for (final email in matched)
            if (!email.labelIds.contains(labelId)) email.id,
        ];
        if (ids.isEmpty) return;
        try {
          await repo.addLabelsToEmails(ids, [labelId]);
        } catch (_) {
          // Best-effort, same as above.
        }
    }
  }
}
