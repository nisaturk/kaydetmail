import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_rule.dart';

class MailRulesStore {
  MailRulesStore._();

  static const _keyPrefix = 'kaydet.rules.';

  static String _keyFor(String accountId) => '$_keyPrefix$accountId';

  static Future<List<MailRule>> readRules(String accountId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_keyFor(accountId));
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return [
      for (final entry in decoded)
        MailRule.fromJson(Map<String, dynamic>.from(entry as Map)),
    ];
  }

  static Future<void> writeRules(String accountId, List<MailRule> rules) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keyFor(accountId),
      jsonEncode([for (final rule in rules) rule.toJson()]),
    );
  }

  /// Removes a rule by id. Unknown ids are ignored.
  static Future<void> deleteRule(String accountId, String ruleId) async {
    final rules = await readRules(accountId);
    await writeRules(
      accountId,
      rules.where((rule) => rule.id != ruleId).toList(),
    );
  }

  static Future<void> remapLabelIds(
    String accountId,
    Map<String, String> idRemap,
  ) async {
    if (idRemap.isEmpty) return;
    final rules = await readRules(accountId);
    if (!rules.any(
      (rule) =>
          rule.action.type == MailRuleActionType.addLabel &&
          idRemap[rule.action.labelId] != null &&
          idRemap[rule.action.labelId] != rule.action.labelId,
    )) {
      return;
    }
    await writeRules(accountId, [
      for (final rule in rules)
        if (rule.action.type == MailRuleActionType.addLabel &&
            idRemap.containsKey(rule.action.labelId))
          rule.copyWith(
            action: MailRuleAction.addLabel(idRemap[rule.action.labelId]!),
          )
        else
          rule,
    ]);
  }
}
