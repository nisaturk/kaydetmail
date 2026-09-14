import 'package:flutter/foundation.dart';

/// Simulated synchronization interval.
enum SyncInterval {
  manual('Manual'),
  every5Minutes('Every 5 minutes'),
  every15Minutes('Every 15 minutes'),
  every30Minutes('Every 30 minutes'),
  everyHour('Every hour');

  const SyncInterval(this.label);

  final String label;
}

/// App-level settings state (notifications, sync interval).
///
/// Values are simulated and stored only for the current session. Screens
/// listen to this controller so toggles rebuild immediately.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  bool _notificationsEnabled = true;
  SyncInterval _syncInterval = SyncInterval.manual;

  bool get notificationsEnabled => _notificationsEnabled;
  SyncInterval get syncInterval => _syncInterval;

  set notificationsEnabled(bool value) {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    notifyListeners();
  }

  set syncInterval(SyncInterval value) {
    if (_syncInterval == value) return;
    _syncInterval = value;
    notifyListeners();
  }

  /// Lets widget tests start from the default settings.
  @visibleForTesting
  static void resetForTest() {
    instance
      .._notificationsEnabled = true
      .._syncInterval = SyncInterval.manual
      ..notifyListeners();
  }
}