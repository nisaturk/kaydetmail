import '../repositories/mail_repository.dart';

/// Client-side filter/rule engine: "mail from X -> move to folder / apply
/// label", evaluated against newly-synced mail. Runs whenever the app is
/// open and syncing (background timer, pull-to-refresh, a push-triggered
/// refresh) — see the call site in `app.dart`'s `_syncLoadedFolders`.
///
/// There is no server-side equivalent (same rationale as labels — see
/// `LocalMailFlagsStore`): rules only fire while this app is running.
///
/// Placeholder: currently a no-op. Rule storage/CRUD and evaluation logic
/// are implemented in a follow-up change; wired here so the hook point in
/// `app.dart` never needs to move again.
class MailRulesEngine {
  MailRulesEngine._();

  static final MailRulesEngine instance = MailRulesEngine._();

  Future<void> evaluateNewMail(MailRepository repo) async {}
}
