import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/server_mail_rule.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/utils/sender_block.dart';

class _RuleRepo extends MailRepository {
  final List<ServerMailRule> rules = [
    const ServerMailRule(
      id: 'other',
      name: 'Bültenler',
      enabled: true,
      priority: 5,
      logic: 'And',
      conditions: [RuleCondition('senderEquals', 'spam@corp.example')],
      actions: [RuleAction('archive')],
    ),
  ];
  var _next = 0;

  @override
  Future<List<ServerMailRule>> listRules(String accountId) async =>
      List.of(rules);

  @override
  Future<ServerMailRule> createRule(
    String accountId,
    ServerMailRule rule,
  ) async {
    final created = ServerMailRule(
      id: 'r${_next++}',
      name: rule.name,
      enabled: rule.enabled,
      priority: rule.priority,
      logic: rule.logic,
      conditions: rule.conditions,
      actions: rule.actions,
    );
    rules.add(created);
    return created;
  }

  @override
  Future<void> deleteRule(String accountId, String ruleId) async =>
      rules.removeWhere((rule) => rule.id == ruleId);

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'block creates one spam rule, is idempotent, and unblock removes it',
    () async {
      final repo = _RuleRepo();

      await blockSender(repo, 'acc', ' Spam@Corp.Example ');
      await blockSender(repo, 'acc', 'spam@corp.example');

      final blocks = await findBlockRules(repo, 'acc', 'SPAM@corp.example');
      expect(blocks, hasLength(1));
      expect(blocks.single.conditions.single.value, 'spam@corp.example');
      expect(blocks.single.actions.map((a) => a.type), [
        'spam',
        'stopProcessing',
      ]);

      await unblockSender(repo, 'acc', 'spam@corp.example');
      expect(await findBlockRules(repo, 'acc', 'spam@corp.example'), isEmpty);
      expect(repo.rules.single.id, 'other');
    },
  );
}
