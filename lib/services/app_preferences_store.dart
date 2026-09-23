import 'package:shared_preferences/shared_preferences.dart';

/// Cross-platform persistence for UI behavior preferences.
///
/// SharedPreferences is used instead of the native SQLite mail cache so the
/// same settings contract also works on web.
class AppPreferencesStore {
  AppPreferencesStore._();

  static const _syncIntervalKey = 'kaydet.sync.interval';
  static const _swipeDeleteKey = 'kaydet.swipe.deleteEnabled';
  static const _themeModeKey = 'kaydet.theme.mode';

  static Future<String?> loadSyncInterval() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_syncIntervalKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSyncInterval(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_syncIntervalKey, value);
  }

  static Future<bool> loadSwipeDeleteEnabled() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_swipeDeleteKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveSwipeDeleteEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_swipeDeleteKey, value);
  }

  static Future<String?> loadThemeMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_themeModeKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveThemeMode(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themeModeKey, value);
  }
}
