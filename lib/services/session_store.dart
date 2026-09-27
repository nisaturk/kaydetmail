import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists accounts logged in, in connection order, so [restoreSession]
/// knows what to restore at app launch and auth gate knows login state.
class SessionStore {
  SessionStore._();

  static const String _key = 'kaydet.session.emails';
  static const String _accountIdsKey = 'kaydet.session.accountIds';

  // Pre-multi-account key, migrated into list below first time emails read.
  static const String _legacyKey = 'kaydet.session.email';

  static Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final legacy = prefs.getString(_legacyKey);
    if (legacy == null || legacy.trim().isEmpty) return;
    await prefs.remove(_legacyKey);
    final existing = prefs.getStringList(_key) ?? const <String>[];
    if (!existing.contains(legacy)) {
      await prefs.setStringList(_key, [...existing, legacy]);
    }
  }

  /// Every account email, in connection order.
  static Future<List<String>> loadEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs);
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Remembers one more logged-in account without duplicate.
  static Future<void> addEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    if (!existing.contains(email)) {
      await prefs.setStringList(_key, [...existing, email]);
    }
  }

  /// Associates [email] with stable backend [accountId] for session restore.
  static Future<void> saveAccountId(String email, String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final accountIds = _loadAccountIds(prefs)..[email] = accountId;
    await prefs.setString(_accountIdsKey, jsonEncode(accountIds));
  }

  static Future<String?> loadAccountId(String email) async {
    try {
      return _loadAccountIds(await SharedPreferences.getInstance())[email];
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _loadAccountIds(SharedPreferences prefs) {
    final raw = prefs.getString(_accountIdsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (email, accountId) => MapEntry(email, accountId as String),
      );
    } catch (_) {
      return {};
    }
  }

  /// Forgets one account without touching others.
  static Future<void> removeEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getStringList(_key) ?? const <String>[]).toList()
      ..remove(email);
    final accountIds = _loadAccountIds(prefs)..remove(email);
    await Future.wait([
      prefs.setStringList(_key, existing),
      prefs.setString(_accountIdsKey, jsonEncode(accountIds)),
    ]);
  }

  /// Forgets every logged-in account.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove(_key),
        prefs.remove(_accountIdsKey),
        prefs.remove(_legacyKey),
      ]);
    } catch (_) {
      // No session to clear in tests / unsupported platforms.
    }
  }

  /// Synchronous test helper: wipes mock prefs.
  static void resetForTest() {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
    } catch (_) {
      // Not in test environment.
    }
  }
}
