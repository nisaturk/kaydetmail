import 'package:flutter/foundation.dart';

import '../services/server_address_store.dart';

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

/// App-level settings state.
///
/// Notifications, sync interval and swipe-to-delete are simulated and stored
/// only for the current session. The server base URL is the one real control
/// switch to configure the future HTTP API, so it is persisted through
/// [ServerAddressStore] and survives app restarts. Same ChangeNotifier +
/// `ListenableBuilder` pattern as everywhere else.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  bool _notificationsEnabled = true;
  SyncInterval _syncInterval = SyncInterval.manual;
  bool _swipeDeleteEnabled = true;
  String _serverBaseUrl = ServerAddressStore.defaultBaseUrl;

  bool get notificationsEnabled => _notificationsEnabled;
  SyncInterval get syncInterval => _syncInterval;

  /// Whether the inbox supports swipe-to-delete (`Kaydırarak sil`).
  bool get swipeDeleteEnabled => _swipeDeleteEnabled;

  /// Configured HTTP API base URL, normalized (no trailing slash).
  String get serverBaseUrl => _serverBaseUrl;

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

  set swipeDeleteEnabled(bool value) {
    if (_swipeDeleteEnabled == value) return;
    _swipeDeleteEnabled = value;
    notifyListeners();
  }

  /// Loads the persisted server address at app startup. Falls back to the
  /// default when nothing was saved yet.
  Future<void> loadServerAddress() async {
    final loaded = await ServerAddressStore.load();
    if (loaded == _serverBaseUrl) return;
    _serverBaseUrl = loaded;
    notifyListeners();
  }

  /// Validates, normalizes and persists a new server base URL. Throws
  /// [ArgumentError] (Turkish message) when [raw] is not a usable absolute
  /// http/https URL.
  Future<String> setServerAddress(String raw) async {
    final normalized = ServerAddressStore.normalize(raw);
    if (normalized != _serverBaseUrl) {
      await ServerAddressStore.save(normalized);
      _serverBaseUrl = normalized;
      notifyListeners();
    }
    return normalized;
  }

  /// Lets widget tests start from the default settings.
  @visibleForTesting
  static void resetForTest() {
    instance
      .._notificationsEnabled = true
      .._syncInterval = SyncInterval.manual
      .._swipeDeleteEnabled = true
      .._serverBaseUrl = ServerAddressStore.defaultBaseUrl
      ..notifyListeners();
  }
}
