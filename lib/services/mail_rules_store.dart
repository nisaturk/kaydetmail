import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_rule.dart';

/// Persists client-side mail rules ([MailRule]) per account, in
/// SharedPreferences as a JSON-encoded list — same storage mechanism and
/// per-account scoping as `AppPreferencesStore`/`LocalMailFlagsStore`.
///
/// Rules are a purely client-side feature (no backend endpoint exists for
/// them, same rationale documented on `LocalMailFlagsStore`): they only
/// ever apply while this app is open and syncing. Scoped per account,
/// like labels, because an `addLabel` action's `labelId` is only
/// meaningful within the account that owns it
/// (`MailRepository.getLabelsForAccount`).
class MailRulesStore {
  MailRulesStore._();

  static const _keyPrefix = 'kaydet.rules.';

  static String _keyFor(String accountId) => '$_keyPrefix$accountId';

  /// Every rule stored for [accountId], in creation order. Corrupt/missing
  /// storage reads as an empty list rather than throwing.
  static Future<List<MailRule>> readRules(String accountId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_keyFor(accountId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return [
        for (final entry in decoded)
          MailRule.fromJson(Map<String, dynamic>.from(entry as Map)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> writeRules(
    String accountId,
    List<MailRule> rules,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _keyFor(accountId),
      jsonEncode([for (final rule in rules) rule.toJson()]),
    );
  }

  /// Creates and persists a new rule for [accountId], returning it.
  static Future<MailRule> addRule({
    required String accountId,
    required MailRuleCondition condition,
    required MailRuleAction action,
  }) async {
    final rules = await readRules(accountId);
    final rule = MailRule(id: _generateId(), condition: condition, action: action);
    await writeRules(accountId, [...rules, rule]);
    return rule;
  }

  /// Replaces the stored rule sharing [rule.id]; a no-op if it no longer
  /// exists.
  static Future<void> updateRule(String accountId, MailRule rule) async {
    final rules = await readRules(accountId);
    await writeRules(accountId, [
      for (final existing in rules) existing.id == rule.id ? rule : existing,
    ]);
  }

  /// Removes a rule by id. Unknown ids are ignored.
  static Future<void> deleteRule(String accountId, String ruleId) async {
    final rules = await readRules(accountId);
    await writeRules(
      accountId,
      rules.where((rule) => rule.id != ruleId).toList(),
    );
  }

  static final _random = Random();

  static String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_random.nextInt(1 << 32).toRadixString(36)}';
}
