import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_rule.dart';
import 'package:kaydetmail/services/mail_rules_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy label action survives remapping and remains account-local',
    () async {
      final first = MailRule(
        id: 'old-rule',
        condition: MailRuleCondition(
          type: MailRuleConditionType.senderContains,
          value: 'news',
        ),
        action: MailRuleAction.addLabel('old-label'),
      );
      final other = MailRule(
        id: 'other-rule',
        condition: MailRuleCondition(
          type: MailRuleConditionType.senderContains,
          value: 'news',
        ),
        action: MailRuleAction.addLabel('old-label'),
      );
      await MailRulesStore.writeRules('account-a', [first]);
      await MailRulesStore.writeRules('account-b', [other]);

      await MailRulesStore.remapLabelIds('account-a', {
        'old-label': 'backend-label',
      });

      expect(
        (await MailRulesStore.readRules('account-a')).single.action.labelId,
        'backend-label',
      );
      expect(
        (await MailRulesStore.readRules('account-b')).single.action.labelId,
        'old-label',
      );
      await MailRulesStore.deleteRule('account-a', first.id);
      expect(await MailRulesStore.readRules('account-a'), isEmpty);
      expect(await MailRulesStore.readRules('account-b'), [other]);
    },
  );

  test(
    'corrupt legacy storage is not silently discarded during migration',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('kaydet.rules.account-a', '{broken');

      await expectLater(
        MailRulesStore.readRules('account-a'),
        throwsFormatException,
      );
      await expectLater(
        MailRulesStore.remapLabelIds('account-a', {'old': 'new'}),
        throwsFormatException,
      );
      expect(prefs.getString('kaydet.rules.account-a'), '{broken');
    },
  );

  test('legacy rules from persisted JSON retain their migration ids', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'kaydet.rules.account-a',
      jsonEncode([
        {
          'id': 'legacy-id',
          'condition': {'type': 'senderContains', 'value': 'notice'},
          'action': {'type': 'moveToFolder', 'folder': 'archive'},
        },
      ]),
    );
    final rule = (await MailRulesStore.readRules('account-a')).single;
    expect(rule.id, 'legacy-id');
    expect(rule.action.folder?.name, 'archive');
  });
}
