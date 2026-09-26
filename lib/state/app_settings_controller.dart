import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../services/app_preferences_store.dart';
import '../services/notification_settings_store.dart';
import '../services/server_address_store.dart';

/// How often the mailbox refreshes itself in the background while the app
/// is open. `manual` ([duration] null) means only pull-to-refresh, push
/// notifications and app-open trigger a refresh.
enum AttachmentAutoDownloadMode {
  off('Kapalı'),
  wifiOnly('Yalnız Wi-Fi'),
  wifiAndMobile('Wi-Fi ve mobil veri');

  const AttachmentAutoDownloadMode(this.label);

  final String label;
}

enum AttachmentAutoDownloadLimit {
  oneMb('1 MB', 1024 * 1024),
  fiveMb('5 MB', 5 * 1024 * 1024),
  tenMb('10 MB', 10 * 1024 * 1024);

  const AttachmentAutoDownloadLimit(this.label, this.bytes);

  final String label;
  final int bytes;
}

enum UndoSendDelay {
  off('Kapalı', null),
  seconds5('5 saniye', Duration(seconds: 5)),
  seconds10('10 saniye', Duration(seconds: 10)),
  seconds20('20 saniye', Duration(seconds: 20)),
  seconds30('30 saniye', Duration(seconds: 30));

  const UndoSendDelay(this.label, this.duration);

  final String label;

  final Duration? duration;
}

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

enum BiometricLockTimeout {
  immediately('Hemen', Duration.zero),
  oneMinute('1 dakika sonra', Duration(minutes: 1)),
  fiveMinutes('5 dakika sonra', Duration(minutes: 5)),
  fifteenMinutes('15 dakika sonra', Duration(minutes: 15));

  const BiometricLockTimeout(this.label, this.duration);

  final String label;
  final Duration duration;
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
  SyncInterval _syncInterval = SyncInterval.every5Minutes;
  bool _swipeDeleteEnabled = true;
  String _serverBaseUrl = ServerAddressStore.defaultBaseUrl;
  ThemeMode _themeMode = ThemeMode.system;
  bool _biometricLockEnabled = false;
  BiometricLockTimeout _biometricLockTimeout = BiometricLockTimeout.immediately;
  AttachmentAutoDownloadMode _attachmentAutoDownloadMode =
      AttachmentAutoDownloadMode.off;
  UndoSendDelay _undoSendDelay = UndoSendDelay.seconds5;
  AttachmentAutoDownloadLimit _attachmentAutoDownloadLimit =
      AttachmentAutoDownloadLimit.fiveMb;
  bool get notificationsEnabled => _notificationsEnabled;
  SyncInterval get syncInterval => _syncInterval;

  /// Whether the inbox supports swipe-to-delete (`Kaydırarak sil`).
  bool get swipeDeleteEnabled => _swipeDeleteEnabled;

  /// Whether the app requires a biometric/device-credential check on cold
  /// start and on returning from the background. See `BiometricLockGate`.
  bool get biometricLockEnabled => _biometricLockEnabled;
  BiometricLockTimeout get biometricLockTimeout => _biometricLockTimeout;

  /// Configured HTTP API base URL, normalized (no trailing slash).
  String get serverBaseUrl => _serverBaseUrl;

  /// `system` follows the device's light/dark setting; `light`/`dark`
  /// override it. Defaults to `system` — the palette itself never changes
  /// (grayscale by design), only which end of it is the background.
  ThemeMode get themeMode => _themeMode;

  AttachmentAutoDownloadMode get attachmentAutoDownloadMode =>
      _attachmentAutoDownloadMode;
  AttachmentAutoDownloadLimit get attachmentAutoDownloadLimit =>
      _attachmentAutoDownloadLimit;

  UndoSendDelay get undoSendDelay => _undoSendDelay;

  set attachmentAutoDownloadMode(AttachmentAutoDownloadMode value) {
    if (_attachmentAutoDownloadMode == value) return;
    _attachmentAutoDownloadMode = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveAttachmentAutoDownloadMode(value.name));
  }

  set undoSendDelay(UndoSendDelay value) {
    if (_undoSendDelay == value) return;
    _undoSendDelay = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveUndoSendDelay(value.name));
  }

  set attachmentAutoDownloadLimit(AttachmentAutoDownloadLimit value) {
    if (_attachmentAutoDownloadLimit == value) return;
    _attachmentAutoDownloadLimit = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveAttachmentAutoDownloadLimit(value.name));
  }

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

  set biometricLockEnabled(bool value) {
    if (_biometricLockEnabled == value) return;
    _biometricLockEnabled = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveBiometricLockEnabled(value));
  }

  set biometricLockTimeout(BiometricLockTimeout value) {
    if (_biometricLockTimeout == value) return;
    _biometricLockTimeout = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveBiometricLockTimeout(value.name));
  }

  set themeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveThemeMode(value.name));
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
    final biometricLock = await AppPreferencesStore.loadBiometricLockEnabled();
    final timeoutName = await AppPreferencesStore.loadBiometricLockTimeout();
    final biometricTimeout = BiometricLockTimeout.values
        .where((value) => value.name == timeoutName)
        .firstOrNull;
    if (sync == null &&
        swipe == _swipeDeleteEnabled &&
        biometricLock == _biometricLockEnabled &&
        (biometricTimeout == null ||
            biometricTimeout == _biometricLockTimeout)) {
      return;
    }
    _syncInterval = sync ?? SyncInterval.every5Minutes;
    _swipeDeleteEnabled = swipe;
    _biometricLockEnabled = biometricLock;
    _biometricLockTimeout =
        biometricTimeout ?? BiometricLockTimeout.immediately;
    notifyListeners();
  }

  Future<void> loadAttachmentPreferences() async {
    final modeName = await AppPreferencesStore.loadAttachmentAutoDownloadMode();
    final limitName =
        await AppPreferencesStore.loadAttachmentAutoDownloadLimit();
    _attachmentAutoDownloadMode =
        AttachmentAutoDownloadMode.values
            .where((value) => value.name == modeName)
            .firstOrNull ??
        AttachmentAutoDownloadMode.off;
    _attachmentAutoDownloadLimit =
        AttachmentAutoDownloadLimit.values
            .where((value) => value.name == limitName)
            .firstOrNull ??
        AttachmentAutoDownloadLimit.fiveMb;
    notifyListeners();
  }

  Future<void> loadUndoSendDelay() async {
    final name = await AppPreferencesStore.loadUndoSendDelay();
    _undoSendDelay =
        UndoSendDelay.values.where((v) => v.name == name).firstOrNull ??
        UndoSendDelay.seconds5;
    notifyListeners();
  }

  /// Loads the persisted theme mode. Awaited before `runApp` in `main()` so
  /// the very first frame already uses the right mode — no light-then-dark
  /// flash.
  Future<void> loadThemeMode() async {
    final saved = await AppPreferencesStore.loadThemeMode();
    final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
    if (mode == null || mode == _themeMode) return;
    _themeMode = mode;
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
      .._syncInterval = SyncInterval.every5Minutes
      .._swipeDeleteEnabled = true
      .._serverBaseUrl = ServerAddressStore.defaultBaseUrl
      .._themeMode = ThemeMode.system
      .._biometricLockEnabled = false
      .._biometricLockTimeout = BiometricLockTimeout.immediately
      .._attachmentAutoDownloadMode = AttachmentAutoDownloadMode.off
      .._attachmentAutoDownloadLimit = AttachmentAutoDownloadLimit.fiveMb
      .._undoSendDelay = UndoSendDelay.seconds5
      ..notifyListeners();
  }
}
