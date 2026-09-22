import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../repositories/mail_repository.dart';
import '../state/app_settings_controller.dart';

/// Routes an FCM `data` payload to the matching API call.
///
/// The payload never carries mail content or previews — only ids — so every
/// branch re-fetches through the API (`GET /api/mails/{id}`) instead of
/// reading a body out of the notification (spec §7).
Future<void> handlePushData(
  Map<String, String> data, {
  required Future<void> Function(String mailId) fetchMail,
  Future<void> Function()? onAccountReauth,
  Future<void> Function()? onSyncError,
}) async {
  switch (data['type']) {
    case 'new_mail':
    case 'mail_state_changed':
      final mailId = data['mailId'];
      if (mailId != null && mailId.isNotEmpty) await fetchMail(mailId);
    case 'account_reauthentication_required':
      await onAccountReauth?.call();
    case 'sync_error':
      await onSyncError?.call();
  }
}

/// Firebase Cloud Messaging wiring: registers the device token on launch and
/// on every refresh, routes foreground data messages through
/// [handlePushData], and turns a notification tap (or a cold start from one)
/// into a mail id on [onMailTapped] for the UI layer to navigate with.
///
/// Everything Firebase-flavored is best-effort and swallowed: without
/// `google-services.json`/`GoogleService-Info.plist` (or with push disabled)
/// the app still runs — it just doesn't receive pushes. Registration itself
/// is an upsert, so calling it on every launch is safe (spec §7).
class PushService {
  const PushService._();

  static final StreamController<String> _mailTapped =
      StreamController<String>.broadcast();

  static FirebaseMessaging? _messaging;
  static MailRepository? _repository;
  static bool _settingsListenerAttached = false;

  /// Emits a mail id whenever the user taps a push notification, or once on
  /// launch if the app was cold-started from one. `new_mail` and
  /// `mail_state_changed` are the only types that carry a `mailId`; taps on
  /// the other two just foreground the app — no navigation needed since
  /// account status is re-checked when the relevant screen reloads.
  static Stream<String> get onMailTapped => _mailTapped.stream;

  /// Initializes Firebase and routes a cold-start notification tap first —
  /// that is the path a user is actively staring at, so it must not wait on
  /// permission prompts or the device-registration network call. Foreground
  /// message handling is wired next; permission + FCM token registration
  /// (and its refresh listener) run last, fire-and-forget, in [_setUpToken].
  /// Never throws — callers (e.g. `main`) don't need their own guard.
  static Future<void> initialize(MailRepository repository) async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      _repository = repository;

      FirebaseMessaging.onMessageOpenedApp.listen(_routeTap);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _routeTap(initial);

      FirebaseMessaging.onMessage.listen(
        (message) => handlePushData(
          message.data.map((key, value) => MapEntry(key, '$value')),
          fetchMail: (id) async {
            try {
              await repository.getEmail(id);
            } catch (_) {
              // A failed refresh never crashes the foreground listener.
            }
          },
        ),
      );

      // The persisted "Bildirimler" toggle (Settings) must be known before
      // deciding whether to register — otherwise a user who turned
      // notifications off would get silently re-registered on every launch.
      await AppSettingsController.instance.loadNotificationsEnabled();
      if (!_settingsListenerAttached) {
        AppSettingsController.instance.addListener(_onSettingsChanged);
        _settingsListenerAttached = true;
      }

      unawaited(_setUpToken(messaging, repository));
    } catch (_) {
      debugPrint('PushService: push unavailable, running without FCM.');
    }
  }

  /// Requests notification permission, then registers the current FCM token
  /// unless the user has turned notifications off in Settings. Keeps
  /// registering on every token refresh. Runs detached from [initialize] so
  /// a slow permission prompt or `/api/devices` round trip never delays
  /// routing a tapped notification.
  static Future<void> _setUpToken(
    FirebaseMessaging messaging,
    MailRepository repository,
  ) async {
    try {
      await messaging.requestPermission();
      if (AppSettingsController.instance.notificationsEnabled) {
        await _register(messaging, repository);
      }
      messaging.onTokenRefresh.listen((_) {
        if (AppSettingsController.instance.notificationsEnabled) {
          _register(messaging, repository);
        }
      });
    } catch (_) {
      debugPrint('PushService: push unavailable, running without FCM.');
    }
  }

  /// Reacts to the Settings screen's "Bildirimler" toggle: turning it off
  /// unregisters this device (the server then stops sending it pushes);
  /// turning it back on re-registers with a fresh token.
  static void _onSettingsChanged() {
    final messaging = _messaging;
    final repository = _repository;
    if (messaging == null || repository == null) return;
    if (AppSettingsController.instance.notificationsEnabled) {
      unawaited(_register(messaging, repository));
    } else {
      unawaited(repository.unregisterDevice());
    }
  }

  static void _routeTap(RemoteMessage message) {
    final mailId = message.data['mailId'];
    if (mailId != null && mailId.isNotEmpty) _mailTapped.add(mailId);
  }

  static Future<void> _register(
    FirebaseMessaging messaging,
    MailRepository repository,
  ) async {
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      final package = await PackageInfo.fromPlatform();
      await repository.registerCurrentDevice(
        fcmToken: token,
        appVersion: package.version,
        locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      );
    } catch (_) {
      // Registration races (e.g. logged out mid-launch) retry next launch.
      debugPrint('PushService: device registration skipped.');
    }
  }
}

/// Handles a push delivered while the app is backgrounded or terminated.
///
/// Runs in its own isolate — re-initializing Firebase here is required per
/// the `firebase_messaging` contract, even though the app's own [Firebase]
/// instance already did it. `new_mail`/`account_reauthentication_required`/
/// `sync_error` all carry a `notification` block (see backend
/// `FirebasePushNotificationService`), so Android's FCM SDK shows the system
/// tray entry on its own; nothing else needs to happen here today.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
}
