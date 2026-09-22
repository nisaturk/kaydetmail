import 'package:shared_preferences/shared_preferences.dart';

/// Persists which accounts are logged in — just their emails, in connection
/// order — so [restoreSession] knows what to restore at app launch, and the
/// auth gate knows whether to show the login screen at all.
///
/// UI never touches SharedPreferences directly — it goes through here, and
/// the repository itself never knows about this class.
class SessionStore {
  SessionStore._();

  static const String _key = 'kaydet.session.emails';

  // Pre-multi-account key, migrated into the list below the first time
  // emails are read, then removed.
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

  /// Every account currently logged in, in the order they were connected —
  /// also the order [MailRepository.restoreSession] should be called in at
  /// app launch.
  static Future<List<String>> loadEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _migrateLegacy(prefs);
      return prefs.getStringList(_key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Remembers one more logged-in account. Safe to call for an email that's
  /// already recorded — it never duplicates.
  static Future<void> addEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const <String>[];
    if (!existing.contains(email)) {
      await prefs.setStringList(_key, [...existing, email]);
    }
  }

  /// Forgets one account (e.g. after [MailRepository.removeAccount]) without
  /// touching the others.
  static Future<void> removeEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getStringList(_key) ?? const <String>[]).toList()
      ..remove(email);
    await prefs.setStringList(_key, existing);
  }

  /// Forgets every logged-in account (full sign-out).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      await prefs.remove(_legacyKey);
    } catch (_) {
      // No session to clear in tests / unsupported platforms.
    }
  }

  /// Synchronous test helper: wipes the mock prefs so each widget test
  /// boots to Login even after a previous test logged in.
  static void resetForTest() {
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
    } catch (_) {
      // Not in a test environment — nothing to reset.
    }
  }
}
