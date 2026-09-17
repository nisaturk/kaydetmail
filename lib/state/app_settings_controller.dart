import 'package:flutter/foundation.dart';

/// Simulated synchronization interval.
enum SyncInterval {
  manual('Manuel'),
  every5Minutes('Her 5 dakikada bir'),
  every15Minutes('Her 15 dakikada bir'),
  every30Minutes('Her 30 dakikada bir'),
  everyHour('Her saat');

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
