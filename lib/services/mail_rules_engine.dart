import '../models/email.dart';
import '../models/mail_folder.dart';
import '../models/mail_rule.dart';
import '../repositories/mail_repository.dart';
import 'home_widget_service.dart';
import 'mail_rules_store.dart';

/// Client-side filter/rule engine: "mail from X -> move to folder / apply
/// label", evaluated against newly-synced mail. Runs whenever the app is
/// open and syncing (background timer, pull-to-refresh, a push-triggered
/// refresh) — every one of those paths funnels through [runAfterSync]
/// rather than calling [evaluateNewMail] directly, so there is exactly one
/// evaluation point to reason about (see `app.dart`, `inbox_screen.dart`,
/// `push_service.dart`).
///
/// There is no server-side equivalent (same rationale as labels — see
/// `LocalMailFlagsStore`): rules only fire while this app is running.
///
/// Rules apply in list order (oldest-created first — see
/// [MailRulesStore.readRules]/`addRule`). When two `moveToFolder` rules
/// both match the same mail, each runs in turn against the same
/// pre-evaluation snapshot, so the LAST matching rule's destination is the
/// one that sticks (it moves the mail after the earlier one already did).
/// `addLabel` rules don't have this conflict — every matching rule's label
/// is additive. Reorder rules (delete + recreate, since there is no
/// priority field) if a specific precedence matters.
///
/// Only Inbox is ever scanned, which makes re-running this on every sync
/// tick safe without any extra "already processed" bookkeeping: once a
/// `moveToFolder` rule moves a mail out of Inbox it naturally never comes
/// up again, and an `addLabel` rule is skipped for mail that already
/// carries the target label.
class MailRulesEngine {
  MailRulesEngine._();

  static final MailRulesEngine instance = MailRulesEngine._();

  /// Single call site every refresh path should use instead of calling
  /// [evaluateNewMail] directly: applies rules across every connected
  /// account's inbox, then refreshes the Android home-screen widget so it
  /// never sits stale between pushes.
  static Future<void> runAfterSync(MailRepository repo) async {
    await instance.evaluateNewMail(repo);
    await HomeWidgetService.refreshFromInbox(repo);
  }

  /// Scans EVERY connected account's Inbox — not just [MailRepository.
  /// activeAccountId]'s — since rules are configured per account, not per
  /// view scope. [MailRepository.getAllEmails] is unscoped by the active
  /// account for exactly this reason.
  Future<void> evaluateNewMail(MailRepository repo) async {
    final inbox = repo
        .getAllEmails()
        .where((e) => e.folder == MailFolder.inbox)
        .toList();
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
