import 'package:shared_preferences/shared_preferences.dart';

/// Persists the login session (just the user email).
///
/// UI never touches SharedPreferences directly — it goes through here,
/// and the repository itself never knows about this class.
class SessionStore {
  SessionStore._();

  static const String _key = 'kaydet.session.email';

  static Future<String?> loadEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_key);
      if (email == null || email.trim().isEmpty) return null;
      return email;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, email);
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
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
