import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../services/app_preferences_store.dart';
import '../services/notification_settings_store.dart';
import '../services/screen_protection_service.dart';
import '../services/server_address_store.dart';
import '../l10n/l10n.dart';

/// How often the mailbox refreshes itself in the background while the app
/// is open. `manual` ([duration] null) means only pull-to-refresh, push
/// notifications and app-open trigger a refresh.
enum AttachmentAutoDownloadMode {
  off,
  wifiOnly,
  wifiAndMobile;

  String get label => switch (this) {
    AttachmentAutoDownloadMode.off => l10nNow.off,
    AttachmentAutoDownloadMode.wifiOnly => l10nNow.wiFiOnly,
    AttachmentAutoDownloadMode.wifiAndMobile => l10nNow.wiFiAndMobileData,
  };
}

enum AttachmentAutoDownloadLimit {
  oneMb(1024 * 1024),
  fiveMb(5 * 1024 * 1024),
  tenMb(10 * 1024 * 1024);

  const AttachmentAutoDownloadLimit(this.bytes);

  final int bytes;

  String get label => switch (this) {
    AttachmentAutoDownloadLimit.oneMb => l10nNow.n1Mb,
    AttachmentAutoDownloadLimit.fiveMb => l10nNow.n5Mb,
    AttachmentAutoDownloadLimit.tenMb => l10nNow.n10Mb,
  };
}

enum UndoSendDelay {
  off(null),
  seconds5(Duration(seconds: 5)),
  seconds10(Duration(seconds: 10)),
  seconds20(Duration(seconds: 20)),
  seconds30(Duration(seconds: 30));

  const UndoSendDelay(this.duration);

  final Duration? duration;

  String get label => switch (this) {
    UndoSendDelay.off => l10nNow.off,
    UndoSendDelay.seconds5 => l10nNow.n5Seconds,
    UndoSendDelay.seconds10 => l10nNow.n10Seconds,
    UndoSendDelay.seconds20 => l10nNow.n20Seconds,
    UndoSendDelay.seconds30 => l10nNow.n30Seconds,
  };
}

enum SwipeGesture {
  archive,
  trash,
  toggleRead,
  star,
  snooze,
  none;

  String get label => switch (this) {
    SwipeGesture.archive => l10nNow.archive2,
    SwipeGesture.trash => l10nNow.delete,
    SwipeGesture.toggleRead => l10nNow.readUnread,
    SwipeGesture.star => l10nNow.starRemoveStar,
    SwipeGesture.snooze => l10nNow.snooze,
    SwipeGesture.none => l10nNow.off,
  };
}

enum SwipeSensitivity {
  low,
  normal,
  high;

  double get threshold => switch (this) {
    SwipeSensitivity.low => 0.70,
    SwipeSensitivity.normal => 0.55,
    SwipeSensitivity.high => 0.40,
  };

  String get label => switch (this) {
    SwipeSensitivity.low => l10nNow.swipeSensitivityLow,
    SwipeSensitivity.normal => l10nNow.swipeSensitivityNormal,
    SwipeSensitivity.high => l10nNow.swipeSensitivityHigh,
  };
}

enum SyncNetworkPolicy {
  wifiAndMobile,
  wifiOnly;

  String get label => switch (this) {
    SyncNetworkPolicy.wifiAndMobile => l10nNow.wiFiAndMobileData,
    SyncNetworkPolicy.wifiOnly => l10nNow.wiFiOnly,
  };
}

enum SyncInterval {
  manual(null),
  every5Minutes(Duration(minutes: 5)),
  every15Minutes(Duration(minutes: 15)),
  every30Minutes(Duration(minutes: 30)),
  everyHour(Duration(hours: 1));

  const SyncInterval(this.duration);

  /// Background refresh period, or null for [manual].
  final Duration? duration;

  String get label => switch (this) {
    SyncInterval.manual => l10nNow.manual,
    SyncInterval.every5Minutes => l10nNow.every5Minutes,
    SyncInterval.every15Minutes => l10nNow.every15Minutes,
    SyncInterval.every30Minutes => l10nNow.every30Minutes,
    SyncInterval.everyHour => l10nNow.everyHour,
  };
}

enum BiometricLockTimeout {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5)),
  fifteenMinutes(Duration(minutes: 15));

  const BiometricLockTimeout(this.duration);

  final Duration duration;

  String get label => switch (this) {
    BiometricLockTimeout.immediately => l10nNow.immediately,
    BiometricLockTimeout.oneMinute => l10nNow.after1Minute,
    BiometricLockTimeout.fiveMinutes => l10nNow.after5Minutes,
    BiometricLockTimeout.fifteenMinutes => l10nNow.after15Minutes,
  };
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
  Locale _locale = defaultLocale;
  bool _biometricLockEnabled = false;
  bool _screenProtectionEnabled = false;
  BiometricLockTimeout _biometricLockTimeout = BiometricLockTimeout.immediately;
  AttachmentAutoDownloadMode _attachmentAutoDownloadMode =
      AttachmentAutoDownloadMode.off;
  UndoSendDelay _undoSendDelay = UndoSendDelay.seconds5;
  SyncNetworkPolicy _syncNetworkPolicy = SyncNetworkPolicy.wifiAndMobile;
  SwipeGesture _swipeRight = SwipeGesture.archive;
  bool _deviceContactsEnabled = false;
  SwipeGesture _swipeLeft = SwipeGesture.trash;
  SwipeSensitivity _swipeSensitivity = SwipeSensitivity.normal;
  bool _pauseSyncOnBatterySaver = true;
  AttachmentAutoDownloadLimit _attachmentAutoDownloadLimit =
      AttachmentAutoDownloadLimit.fiveMb;
  bool _cleanTrackingQueries = true;

  bool get notificationsEnabled => _notificationsEnabled;
  SyncInterval get syncInterval => _syncInterval;

  /// Whether list swipe gestures are enabled (`Kaydırma hareketleri`).
  bool get swipeDeleteEnabled => _swipeDeleteEnabled;

  /// Whether the app requires a biometric/device-credential check on cold
  /// start and on returning from the background. See `BiometricLockGate`.
  bool get biometricLockEnabled => _biometricLockEnabled;
  BiometricLockTimeout get biometricLockTimeout => _biometricLockTimeout;

  /// Whether the OS-level privacy screen is on: screenshots/recordings and the
  /// recent-apps preview are blocked (Android) or covered (iOS). Off by
  /// default; applied natively as soon as it changes and again on launch —
  /// see [ScreenProtectionService].
  bool get screenProtectionEnabled => _screenProtectionEnabled;

  /// Configured HTTP API base URL, normalized (no trailing slash).
  String get serverBaseUrl => _serverBaseUrl;

  /// `system` follows the device's light/dark setting; `light`/`dark`
  /// override it. Defaults to `system` — the palette itself never changes
  /// (grayscale by design), only which end of it is the background.
  ThemeMode get themeMode => _themeMode;

  /// Turkish is the default; English is the only other supported language.
  static const defaultLocale = Locale('tr');
  static const supportedLocales = [Locale('tr'), Locale('en')];

  /// The app's display language, chosen in Settings → Language.
  Locale get locale => _locale;

  AttachmentAutoDownloadMode get attachmentAutoDownloadMode =>
      _attachmentAutoDownloadMode;
  AttachmentAutoDownloadLimit get attachmentAutoDownloadLimit =>
      _attachmentAutoDownloadLimit;

  UndoSendDelay get undoSendDelay => _undoSendDelay;

  SyncNetworkPolicy get syncNetworkPolicy => _syncNetworkPolicy;

  SwipeGesture get swipeRight => _swipeRight;

  bool get deviceContactsEnabled => _deviceContactsEnabled;
  bool get cleanTrackingQueries => _cleanTrackingQueries;

  set cleanTrackingQueries(bool value) {
    if (_cleanTrackingQueries == value) return;
    _cleanTrackingQueries = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveCleanTrackingQueries(value));
  }

  set deviceContactsEnabled(bool value) {
    if (_deviceContactsEnabled == value) return;
    _deviceContactsEnabled = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveDeviceContactsEnabled(value));
  }

  SwipeGesture get swipeLeft => _swipeLeft;

  SwipeSensitivity get swipeSensitivity => _swipeSensitivity;

  set swipeSensitivity(SwipeSensitivity value) {
    if (_swipeSensitivity == value) return;
    _swipeSensitivity = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSwipeSensitivity(value.name));
  }

  set swipeRight(SwipeGesture value) {
    if (_swipeRight == value) return;
    _swipeRight = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSwipeGesture(right: true, value.name));
  }

  set swipeLeft(SwipeGesture value) {
    if (_swipeLeft == value) return;
    _swipeLeft = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSwipeGesture(right: false, value.name));
  }

  bool get pauseSyncOnBatterySaver => _pauseSyncOnBatterySaver;

  set syncNetworkPolicy(SyncNetworkPolicy value) {
    if (_syncNetworkPolicy == value) return;
    _syncNetworkPolicy = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveSyncNetworkPolicy(value.name));
  }

  set pauseSyncOnBatterySaver(bool value) {
    if (_pauseSyncOnBatterySaver == value) return;
    _pauseSyncOnBatterySaver = value;
    notifyListeners();
    unawaited(AppPreferencesStore.savePauseSyncOnBatterySaver(value));
  }

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

  set screenProtectionEnabled(bool value) {
    if (_screenProtectionEnabled == value) return;
    _screenProtectionEnabled = value;
    notifyListeners();
    unawaited(ScreenProtectionService.apply(value));
    unawaited(AppPreferencesStore.saveScreenProtectionEnabled(value));
  }

  set biometricLockTimeout(BiometricLockTimeout value) {
    if (_biometricLockTimeout == value) return;
    _biometricLockTimeout = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveBiometricLockTimeout(value.name));
  }

  set locale(Locale value) {
    if (_locale == value || !supportedLocales.contains(value)) return;
    _locale = value;
    notifyListeners();
    unawaited(AppPreferencesStore.saveLanguage(value.languageCode));
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

  /// Loads the persisted privacy-screen preference and applies it natively.
  Future<void> loadScreenProtection() async {
    final loaded = await AppPreferencesStore.loadScreenProtectionEnabled();
    await ScreenProtectionService.apply(loaded);
    if (loaded == _screenProtectionEnabled) return;
    _screenProtectionEnabled = loaded;
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

  Future<void> loadDeviceContactsEnabled() async {
    _deviceContactsEnabled =
        await AppPreferencesStore.loadDeviceContactsEnabled();
    notifyListeners();
  }

  Future<void> loadSwipeGestures() async {
    SwipeGesture? parse(String? name) =>
        SwipeGesture.values.where((v) => v.name == name).firstOrNull;
    _swipeRight =
        parse(await AppPreferencesStore.loadSwipeGesture(right: true)) ??
        SwipeGesture.archive;
    _swipeLeft =
        parse(await AppPreferencesStore.loadSwipeGesture(right: false)) ??
        SwipeGesture.trash;
    final sensitivity = await AppPreferencesStore.loadSwipeSensitivity();
    _swipeSensitivity =
        SwipeSensitivity.values
            .where((v) => v.name == sensitivity)
            .firstOrNull ??
        SwipeSensitivity.normal;
    notifyListeners();
  }

  Future<void> loadSyncPolicy() async {
    final name = await AppPreferencesStore.loadSyncNetworkPolicy();
    _syncNetworkPolicy =
        SyncNetworkPolicy.values.where((v) => v.name == name).firstOrNull ??
        SyncNetworkPolicy.wifiAndMobile;
    _pauseSyncOnBatterySaver =
        await AppPreferencesStore.loadPauseSyncOnBatterySaver();
    notifyListeners();
  }

  Future<void> loadUndoSendDelay() async {
    final name = await AppPreferencesStore.loadUndoSendDelay();
    _undoSendDelay =
        UndoSendDelay.values.where((v) => v.name == name).firstOrNull ??
        UndoSendDelay.seconds5;
    notifyListeners();
  }

  Future<void> loadCleanTrackingQueries() async {
    final loaded = await AppPreferencesStore.loadCleanTrackingQueries();
    if (loaded == _cleanTrackingQueries) return;
    _cleanTrackingQueries = loaded;
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

  /// Loads the persisted language. Awaited before `runApp` like the theme so
  /// the first frame is already in the right language.
  Future<void> loadLanguage() async {
    final saved = await AppPreferencesStore.loadLanguage();
    final loaded = supportedLocales
        .where((locale) => locale.languageCode == saved)
        .firstOrNull;
    if (loaded == null || loaded == _locale) return;
    _locale = loaded;
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
      .._locale = defaultLocale
      .._biometricLockEnabled = false
      .._screenProtectionEnabled = false
      .._biometricLockTimeout = BiometricLockTimeout.immediately
      .._attachmentAutoDownloadMode = AttachmentAutoDownloadMode.off
      .._attachmentAutoDownloadLimit = AttachmentAutoDownloadLimit.fiveMb
      .._undoSendDelay = UndoSendDelay.seconds5
      .._syncNetworkPolicy = SyncNetworkPolicy.wifiAndMobile
      .._pauseSyncOnBatterySaver = true
      .._swipeRight = SwipeGesture.archive
      .._deviceContactsEnabled = false
      .._swipeLeft = SwipeGesture.trash
      .._swipeSensitivity = SwipeSensitivity.normal
      .._cleanTrackingQueries = true
      ..notifyListeners();
  }
}
