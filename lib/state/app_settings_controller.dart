import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/app_preferences_store.dart';
import '../services/notification_settings_store.dart';
import '../services/server_address_store.dart';

/// How often the mailbox refreshes itself in the background while the app
/// is open. `manual` ([duration] null) means only pull-to-refresh, push
/// notifications and app-open trigger a refresh.
enum SyncInterval {
  manual('Manuel', null),
  every5Minutes('Her 5 dakikada bir', Duration(minutes: 5)),
  every15Minutes('Her 15 dakikada bir', Duration(minutes: 15)),
  every30Minutes('Her 30 dakikada bir', Duration(minutes: 30)),
  everyHour('Her saat', Duration(hours: 1));

  const SyncInterval(this.label, this.duration);

  final String label;

  /// Background refresh period, or null for [manual].
  final Duration? duration;
}

/// App-level settings state.
///
/// Swipe-to-delete and sync interval directly gate real inbox/refresh
/// behavior (see [InboxScreen] and `_AuthGateState._rescheduleSync`).
/// Notifications persists through [NotificationSettingsStore] and gates
/// this device's push registration (see `PushService`). The server base
/// URL is persisted through [ServerAddressStore]. Same ChangeNotifier +
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
    unawaited(NotificationSettingsStore.save(value));
  }

  set syncInterval(SyncInterval value) {
    if (_syncInterval == value) return;
    _syncInterval = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSyncInterval(value.name));
  }

  set swipeDeleteEnabled(bool value) {
    if (_swipeDeleteEnabled == value) return;
    _swipeDeleteEnabled = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSwipeDeleteEnabled(value));
  }

  /// Loads the persisted server address at app startup. Falls back to the
  /// default when nothing was saved yet.
  Future<void> loadServerAddress() async {
    final loaded = await ServerAddressStore.load();
    if (loaded == _serverBaseUrl) return;
    _serverBaseUrl = loaded;
    notifyListeners();
  }

  /// Loads the persisted notifications preference at app startup, before
  /// `PushService` decides whether to register this device for push.
  Future<void> loadNotificationsEnabled() async {
    final loaded = await NotificationSettingsStore.load();
    if (loaded == _notificationsEnabled) return;
    _notificationsEnabled = loaded;
    notifyListeners();
  }

  /// Loads sync and gesture preferences before authentication completes, so
  /// the first mailbox frame and sync timer use the persisted values.
  Future<void> loadBehaviorPreferences() async {
    final syncName = await AppPreferencesStore.loadSyncInterval();
    final sync = SyncInterval.values
        .where((value) => value.name == syncName)
        .firstOrNull;
    final swipe = await AppPreferencesStore.loadSwipeDeleteEnabled();
    if (sync == null && swipe == _swipeDeleteEnabled) return;
    _syncInterval = sync ?? SyncInterval.manual;
    _swipeDeleteEnabled = swipe;
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
