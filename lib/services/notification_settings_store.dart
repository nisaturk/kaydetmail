import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the user wants push notifications shown on this device.
///
/// UI never touches SharedPreferences directly — it goes through this store,
/// same pattern as [ServerAddressStore].
class NotificationSettingsStore {
  NotificationSettingsStore._();

  static const String _key = 'kaydet.notifications.enabled';

  /// Loads the persisted preference. Defaults to `true` (notifications on)
  /// when nothing was saved yet.
  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
