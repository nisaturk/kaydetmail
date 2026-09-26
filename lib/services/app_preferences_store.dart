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
  static const _biometricLockKey = 'kaydet.security.biometricLockEnabled';
  static const _biometricLockTimeoutKey = 'kaydet.security.biometricLockTimeout';

  static const _undoSendDelayKey = 'kaydet.compose.undoSendDelay';
  static const _syncNetworkPolicyKey = 'kaydet.sync.networkPolicy';
  static const _swipeRightKey = 'kaydet.swipe.right';
  static const _swipeLeftKey = 'kaydet.swipe.left';
  static const _pauseSyncOnBatterySaverKey = 'kaydet.sync.pauseOnBatterySaver';

  static const _attachmentAutoDownloadModeKey =
      'kaydet.attachments.autoDownloadMode';
  static const _attachmentAutoDownloadLimitKey =
      'kaydet.attachments.autoDownloadLimit';

  static Future<String?> loadSwipeGesture({required bool right}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(right ? _swipeRightKey : _swipeLeftKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSwipeGesture(
    String value, {
    required bool right,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(right ? _swipeRightKey : _swipeLeftKey, value);
  }

  static Future<String?> loadSyncNetworkPolicy() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_syncNetworkPolicyKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSyncNetworkPolicy(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_syncNetworkPolicyKey, value);
  }

  static Future<bool> loadPauseSyncOnBatterySaver() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_pauseSyncOnBatterySaverKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> savePauseSyncOnBatterySaver(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_pauseSyncOnBatterySaverKey, value);
  }

  static Future<String?> loadUndoSendDelay() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_undoSendDelayKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUndoSendDelay(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_undoSendDelayKey, value);
  }

  static Future<String?> loadAttachmentAutoDownloadMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_attachmentAutoDownloadModeKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAttachmentAutoDownloadMode(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_attachmentAutoDownloadModeKey, value);
  }

  static Future<String?> loadAttachmentAutoDownloadLimit() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_attachmentAutoDownloadLimitKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAttachmentAutoDownloadLimit(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_attachmentAutoDownloadLimitKey, value);
  }

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

  static Future<bool> loadBiometricLockEnabled() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_biometricLockKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveBiometricLockEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_biometricLockKey, value);
  }

  static Future<String?> loadBiometricLockTimeout() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_biometricLockTimeoutKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveBiometricLockTimeout(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_biometricLockTimeoutKey, value);
  }
}
