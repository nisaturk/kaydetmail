import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/account_notification_settings.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'api_mail_service.dart';
import 'token_store.dart';

enum MailNotificationAction {
  read('read', 'Okundu', 'read'),
  archive('archive', 'Arşivle', 'archive'),
  trash('trash', 'Sil', 'trash'),
  reply('reply', 'Yanıtla', null);

  const MailNotificationAction(this.id, this.label, this.apiAction);

  final String id;
  final String label;
  final String? apiAction;

  static MailNotificationAction? fromId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

class MailNotification {
  const MailNotification({
    required this.accountId,
    required this.mailId,
    required this.title,
    required this.body,
  });

  final String accountId;
  final String mailId;
  final String title;
  final String body;

  int get id => notificationIdFor(mailId);

  String get payload => jsonEncode({
    'accountId': accountId,
    'mailId': mailId,
    'title': title,
    'body': body,
  });

  static MailNotification? fromPushData(Map<String, String> data) {
    final type = data['type'];
    if (type != 'new_mail' && type != 'snooze_expired') return null;
    final accountId = _clean(data['accountId']);
    final mailId = _clean(data['mailId']);
    if (accountId == null || mailId == null) return null;
    final snooze = type == 'snooze_expired';
    final privacy = NotificationPrivacy.fromBackend(data['privacy']);
    final sender = _clean(data['sender']);
    final subject = _clean(data['subject']);
    final preview = _clean(data['preview']);
    if (privacy == NotificationPrivacy.private ||
        (sender == null && subject == null)) {
      return MailNotification(
        accountId: accountId,
        mailId: mailId,
        title: snooze ? 'Ertelenen e-posta geri döndü' : 'Yeni e-posta',
        body: snooze
            ? 'Ertelenen bir iletiniz gelen kutusuna döndü.'
            : 'Yeni bir iletiniz var.',
      );
    }
    final subjectLine = subject ?? '(Konu yok)';
    final details = privacy == NotificationPrivacy.full && preview != null
        ? '$subjectLine\n$preview'
        : subjectLine;
    return MailNotification(
      accountId: accountId,
      mailId: mailId,
      title: snooze ? 'Ertelenen e-posta geri döndü' : sender ?? 'Yeni e-posta',
      body: snooze && sender != null ? '$sender: $details' : details,
    );
  }

  static MailNotification? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return MailNotification(
        accountId: json['accountId'] as String,
        mailId: json['mailId'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

String? mailIdFromNotificationPayload(String? payload) {
  final notification = MailNotification.fromPayload(payload);
  if (notification != null) return notification.mailId;
  if (payload == null || payload.isEmpty || payload.startsWith('{')) {
    return null;
  }
  return payload;
}

int notificationIdFor(String mailId) {
  var hash = 0x811c9dc5;
  for (final unit in mailId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

abstract interface class MailNotificationDisplay {
  Future<void> show(MailNotification notification, {String? notice});
  Future<void> cancel(int id);
}

class LocalMailNotificationDisplay implements MailNotificationDisplay {
  LocalMailNotificationDisplay(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> show(MailNotification notification, {String? notice}) {
    final body = notice == null
        ? notification.body
        : '$notice\n${notification.body}';
    return _plugin.show(
      id: notification.id,
      title: notification.title,
      body: body,
      notificationDetails: MailNotifications.details(body),
      payload: notification.payload,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

typedef MailActionExecutor = Future<void> Function(
  String accountId,
  String mailId,
  String apiAction,
);

class MailNotifications {
  const MailNotifications._();

  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'mail',
    'E-postalar',
    description: 'Yeni e-posta ve hesap bildirimleri',
    importance: Importance.high,
  );

  static const _dismissingOperations = {
    'read',
    'archive',
    'trash',
    'spam',
    'move',
    'delete',
  };

  static NotificationDetails details(
    String body, {
    bool withActions = true,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
      actions: withActions
          ? [
              for (final action in MailNotificationAction.values)
                AndroidNotificationAction(
                  action.id,
                  action.label,
                  showsUserInterface: action == MailNotificationAction.reply,
                  cancelNotification: action == MailNotificationAction.reply,
                ),
            ]
          : null,
    ),
    iOS: const DarwinNotificationDetails(),
  );

  static Future<void> initialize(
    FlutterLocalNotificationsPlugin plugin, {
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: mailNotificationActionHandler,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static bool dismissesNotification(String? operation) =>
      _dismissingOperations.contains(operation);

  static Future<bool> runAction(
    MailNotification notification,
    MailNotificationAction action, {
    required MailActionExecutor execute,
    required MailNotificationDisplay display,
  }) async {
    final apiAction = action.apiAction;
    if (apiAction == null) return false;
    try {
      await execute(notification.accountId, notification.mailId, apiAction);
    } on ApiException catch (error) {
      if (error.status != 404) {
        await _showFailure(notification, action, display);
        return false;
      }
    } catch (_) {
      await _showFailure(notification, action, display);
      return false;
    }
    await display.cancel(notification.id);
    return true;
  }

  static Future<void> _showFailure(
    MailNotification notification,
    MailNotificationAction action,
    MailNotificationDisplay display,
  ) => display.show(
    notification,
    notice: '"${action.label}" yapılamadı, tekrar deneyin.',
  );
}

@pragma('vm:entry-point')
Future<void> mailNotificationActionHandler(
  NotificationResponse response,
) async {
  final notification = MailNotification.fromPayload(response.payload);
  final action = MailNotificationAction.fromId(response.actionId);
  if (notification == null || action == null || action.apiAction == null) {
    return;
  }
  final plugin = FlutterLocalNotificationsPlugin();
  await MailNotifications.initialize(plugin);
  await MailNotifications.runAction(
    notification,
    action,
    execute: _executeWithStoredSession,
    display: LocalMailNotificationDisplay(plugin),
  );
}

Future<void> _executeWithStoredSession(
  String accountId,
  String mailId,
  String apiAction,
) =>
    ApiMailService(ApiClient(tokenStore: TokenStore())..bindAccount(accountId))
        .mailAction(mailId, apiAction);
