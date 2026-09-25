import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../state/app_settings_controller.dart';
import 'home_widget_service.dart';
import 'mail_notifications.dart';

/// Routes an FCM `data` payload to the matching API call.
///
/// The payload carries ids plus, as the account's notification privacy
/// allows, sender/subject/short preview for display only, so every branch
/// re-fetches through the API (`GET /api/mails/{id}`) instead of reading
/// mail state out of the notification (spec §7).
Future<void> handlePushData(
  Map<String, String> data, {
  required Future<void> Function(String mailId) fetchMail,
  Future<void> Function()? onAccountReauth,
  Future<void> Function()? onSyncError,
}) async {
  switch (data['type']) {
    case 'new_mail':
    case 'snooze_expired':
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

  static final StreamController<({String mailId, bool reply})> _mailTapped =
      StreamController<({String mailId, bool reply})>.broadcast();

  static FirebaseMessaging? _messaging;
  static MailRepository? _repository;
  static bool _settingsListenerAttached = false;

  /// Accounts the device was last registered for — a newly connected
  /// account needs its own registration (see [_onRepositoryChanged]).
  static Set<String> _registeredAccountIds = {};

  /// FCM only pops up a notification by itself while the app is in the
  /// background; foreground ones are shown through this plugin instead.
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// Push needs Firebase's mobile SDKs; desktop and web builds run without.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Emits a mail id whenever the user taps a push notification, or once on
  /// launch if the app was cold-started from one; `reply` is set when the
  /// notification's "Yanıtla" action was used. `new_mail`, `snooze_expired`
  /// and `mail_state_changed` are the only types that carry a `mailId`; taps
  /// on the other two just foreground the app — no navigation needed since
  /// account status is re-checked when the relevant screen reloads.
  static Stream<({String mailId, bool reply})> get onMailTapped =>
      _mailTapped.stream;

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

      await MailNotifications.initialize(
        _local,
        onResponse: _onNotificationResponse,
      );
      final launch = await _local.getNotificationAppLaunchDetails();
      final launchResponse = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && launchResponse != null) {
        _onNotificationResponse(launchResponse);
      }
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForeground(message));
        unawaited(
          handlePushData(
            message.data.map((key, value) => MapEntry(key, '$value')),
            fetchMail: (id) async {
              try {
                await repository.getEmail(id);
                final type = message.data['type'];
                if (type == 'new_mail' || type == 'snooze_expired') {
                  await repository.refreshEmails(MailFolder.inbox);
                  await HomeWidgetService.refreshFromInbox(repository);
                }
              } catch (_) {
                // A failed refresh never crashes the foreground listener.
              }
            },
          ),
        );
      });

      // The persisted "Bildirimler" toggle (Settings) must be known before
      // deciding whether to register — otherwise a user who turned
      // notifications off would get silently re-registered on every launch.
      await AppSettingsController.instance.loadNotificationsEnabled();
      if (!_settingsListenerAttached) {
        AppSettingsController.instance.addListener(_onSettingsChanged);
        repository.addListener(_onRepositoryChanged);
        _settingsListenerAttached = true;
      }

      unawaited(_setUpToken(messaging, repository));
    } catch (_) {
      debugPrint('PushService: push unavailable, running without FCM.');
    }
  }

  /// Retries device registration after authentication establishes at least
  /// one repository session. Safe when Firebase is unavailable or disabled.
  static Future<void> registerAuthenticatedDevice() async {
    final messaging = _messaging;
    final repository = _repository;
    if (messaging == null ||
        repository == null ||
        !AppSettingsController.instance.notificationsEnabled) {
      return;
    }
    await _register(messaging, repository);
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

  /// Registers again when an account was connected after launch — the
  /// device registration is per account, and [registerAuthenticatedDevice]
  /// only runs once at sign-in.
  static void _onRepositoryChanged() {
    final messaging = _messaging;
    final repository = _repository;
    if (messaging == null ||
        repository == null ||
        !AppSettingsController.instance.notificationsEnabled) {
      return;
    }
    final ids = {for (final account in repository.accounts) account.id};
    if (ids.difference(_registeredAccountIds).isEmpty) return;
    unawaited(_register(messaging, repository));
  }

  static void _routeTap(RemoteMessage message) {
    final mailId = message.data['mailId'];
    if (mailId != null && mailId.isNotEmpty) {
      _mailTapped.add((mailId: mailId, reply: false));
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final mailId = mailIdFromNotificationPayload(response.payload);
    if (mailId == null) return;
    final reply = response.actionId == MailNotificationAction.reply.id;
    if (response.actionId != null && !reply) return;
    _mailTapped.add((mailId: mailId, reply: reply));
  }

  /// Shows a push that arrived while the app is open. Mail pushes are
  /// rendered from their data payload with quick actions; the others only
  /// when they carry a `notification` block. `mail_state_changed` is a
  /// silent sync signal that clears the notification of a mail that was
  /// read, moved or deleted elsewhere.
  static Future<void> _showForeground(RemoteMessage message) async {
    final data = message.data.map((key, value) => MapEntry(key, '$value'));
    try {
      final mail = MailNotification.fromPushData(data);
      if (mail != null) {
        await LocalMailNotificationDisplay(_local).show(mail);
        return;
      }
      final dismissed = _dismissedMailId(data);
      if (dismissed != null) {
        await _local.cancel(id: notificationIdFor(dismissed));
        return;
      }
      final notification = message.notification;
      if (notification == null) return;
      await _local.show(
        id: message.messageId?.hashCode ?? notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: MailNotifications.details(
          notification.body ?? '',
          withActions: false,
        ),
        payload: data['mailId'],
      );
    } catch (_) {
      debugPrint('PushService: foreground notification skipped.');
    }
  }

  static Future<void> _register(
    FirebaseMessaging messaging,
    MailRepository repository,
  ) async {
    try {
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      final package = await PackageInfo.fromPlatform();
      final accountIds = {for (final a in repository.accounts) a.id};
      await repository.registerCurrentDevice(
        fcmToken: token,
        appVersion: package.version,
        locale: PlatformDispatcher.instance.locale.toLanguageTag(),
      );
      _registeredAccountIds = accountIds;
    } catch (_) {
      // Registration races (e.g. logged out mid-launch) retry next launch.
      debugPrint('PushService: device registration skipped.');
    }
  }
}

String? _dismissedMailId(Map<String, String> data) {
  if (data['type'] != 'mail_state_changed' ||
      !MailNotifications.dismissesNotification(data['operation'])) {
    return null;
  }
  final mailId = data['mailId'];
  return mailId == null || mailId.isEmpty ? null : mailId;
}

/// Handles a push delivered while the app is backgrounded or terminated.
///
/// Runs in its own isolate — re-initializing Firebase here is required per
/// the `firebase_messaging` contract, even though the app's own [Firebase]
/// instance already did it. On Android `new_mail`/`snooze_expired` arrive
/// data-only and are rendered here with quick actions, and a
/// `mail_state_changed` for a read/moved/deleted mail clears its
/// notification. `account_reauthentication_required`/`sync_error` and every
/// iOS mail push carry a system-rendered alert (see backend
/// `FirebasePushNotificationService`).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  if (defaultTargetPlatform != TargetPlatform.android) return;
  final data = message.data.map((key, value) => MapEntry(key, '$value'));
  final mail = MailNotification.fromPushData(data);
  final dismissed = _dismissedMailId(data);
  if (mail == null && dismissed == null) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await MailNotifications.initialize(plugin);
  if (mail != null) {
    await LocalMailNotificationDisplay(plugin).show(mail);
  } else {
    await plugin.cancel(id: notificationIdFor(dismissed!));
  }
}
