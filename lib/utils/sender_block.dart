import '../models/server_mail_rule.dart';
import '../repositories/mail_repository.dart';

bool isBlockRuleFor(ServerMailRule rule, String sender) {
  final normalized = sender.trim().toLowerCase();
  return rule.conditions.length == 1 &&
      rule.conditions.single.type == 'senderEquals' &&
      rule.conditions.single.value?.trim().toLowerCase() == normalized &&
      rule.actions.any((action) => action.type == 'spam');
}

Future<List<ServerMailRule>> findBlockRules(
  MailRepository repo,
  String accountId,
  String sender,
) async => [
  for (final rule in await repo.listRules(accountId))
    if (isBlockRuleFor(rule, sender)) rule,
];

Future<void> blockSender(
  MailRepository repo,
  String accountId,
  String sender,
) async {
  final normalized = sender.trim().toLowerCase();
  if ((await findBlockRules(repo, accountId, normalized)).isNotEmpty) return;
  await repo.createRule(
    accountId,
    ServerMailRule(
      id: '',
      name: 'Engellendi: $normalized',
      enabled: true,
      priority: 0,
      logic: 'And',
      conditions: [RuleCondition('senderEquals', normalized)],
      actions: const [RuleAction('spam'), RuleAction('stopProcessing')],
    ),
  );
}

Future<void> unblockSender(
  MailRepository repo,
  String accountId,
  String sender,
) async {
  for (final rule in await findBlockRules(repo, accountId, sender)) {
    await repo.deleteRule(accountId, rule.id);
  }
}
