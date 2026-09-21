import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../repositories/mail_repository.dart';

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
/// on every refresh, and routes incoming data messages through
/// [handlePushData].
///
/// Everything Firebase-flavored is best-effort and swallowed: without
/// `google-services.json`/`GoogleService-Info.plist` (or with push disabled)
/// the app still runs — it just doesn't receive pushes. Registration itself
/// is an upsert, so calling it on every launch is safe (spec §7).
class PushService {
  const PushService._();

  /// Initializes Firebase, asks for notification permission, registers the
  /// current FCM token and listens for foreground messages + token refreshes.
  /// Never throws — callers (e.g. `main`) don't need their own guard.
  static Future<void> initialize(MailRepository repository) async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      await _register(messaging, repository);
      messaging.onTokenRefresh.listen((_) => _register(messaging, repository));
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
    } catch (_) {
      debugPrint('PushService: push unavailable, running without FCM.');
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
