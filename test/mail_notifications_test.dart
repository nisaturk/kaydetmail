import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/mail_notifications.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RecordingDisplay implements MailNotificationDisplay {
  final shown = <(MailNotification, String?)>[];
  final cancelled = <int>[];

  @override
  Future<void> show(MailNotification notification, {String? notice}) async =>
      shown.add((notification, notice));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

const _mail = MailNotification(
  accountId: 'acc-2',
  mailId: 'mail-9',
  title: 'Ayşe',
  body: 'Toplantı',
);

void main() {
  group('MailNotification.fromPushData', () {
    Map<String, String> data(String privacy, {String type = 'new_mail'}) => {
      'type': type,
      'accountId': 'acc-1',
      'mailId': 'm-1',
      'privacy': privacy,
      if (privacy != 'private') 'sender': 'Ayşe',
      if (privacy != 'private') 'subject': 'Toplantı',
      if (privacy == 'full') 'preview': 'Yarın 10:00',
    };

    test('renders only what the account privacy level sent', () {
      final full = MailNotification.fromPushData(data('full'))!;
      expect((full.title, full.body), ('Ayşe', 'Toplantı\nYarın 10:00'));

      final limited = MailNotification.fromPushData(data('limited'))!;
      expect((limited.title, limited.body), ('Ayşe', 'Toplantı'));

      final private = MailNotification.fromPushData(data('private'))!;
      expect(
        (private.title, private.body),
        ('Yeni e-posta', 'Yeni bir iletiniz var.'),
      );
      expect(private.accountId, 'acc-1');
      expect(private.mailId, 'm-1');
    });

    test('snooze wake-up keeps the returned mail identifiable', () {
      final limited = MailNotification.fromPushData(
        data('limited', type: 'snooze_expired'),
      )!;
      expect(
        (limited.title, limited.body),
        ('Ertelenen e-posta geri döndü', 'Ayşe: Toplantı'),
      );
      final private = MailNotification.fromPushData(
        data('private', type: 'snooze_expired'),
      )!;
      expect(private.body, 'Ertelenen bir iletiniz gelen kutusuna döndü.');
    });

    test('ignores non-mail pushes and pushes without mail ids', () {
      expect(
        MailNotification.fromPushData({
          'type': 'mail_state_changed',
          'accountId': 'a',
          'mailId': 'm',
        }),
        isNull,
      );
      expect(
        MailNotification.fromPushData({'type': 'new_mail', 'accountId': 'a'}),
        isNull,
      );
    });

    test('payload survives the isolate hop and legacy payloads still open', () {
      final restored = MailNotification.fromPayload(_mail.payload)!;
      expect(
        (restored.accountId, restored.mailId, restored.title, restored.body),
        ('acc-2', 'mail-9', 'Ayşe', 'Toplantı'),
      );
      expect(mailIdFromNotificationPayload(_mail.payload), 'mail-9');
      expect(mailIdFromNotificationPayload('legacy-mail-id'), 'legacy-mail-id');
      expect(mailIdFromNotificationPayload('{broken'), isNull);
    });
  });

  group('MailNotifications.runAction', () {
    late List<http.Request> requests;

    Future<void> Function(String, String, String) executor(int status) {
      return (accountId, mailId, apiAction) async {
        SharedPreferences.setMockInitialValues({});
        final store = TokenStore(storage: _MemoryTokenStorage());
        await store.save(
          accountId: accountId,
          accessToken: 'access-$accountId',
          refreshToken: 'refresh',
        );
        await ApiMailService(
          ApiClient(
            tokenStore: store,
            accountId: accountId,
            httpClient: MockClient((request) async {
              requests.add(request);
              return http.Response(status == 204 ? '' : '{}', status);
            }),
          ),
        ).mailAction(mailId, apiAction);
      };
    }

    setUp(() => requests = []);

    test(
      'archive runs against the owning account and clears the notification',
      () async {
        final display = _RecordingDisplay();

        final done = await MailNotifications.runAction(
          _mail,
          MailNotificationAction.archive,
          execute: executor(204),
          display: display,
        );

        expect(done, isTrue);
        final request = requests.single;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/mails/mail-9/archive');
        expect(request.headers['authorization'], 'Bearer access-acc-2');
        expect(display.cancelled, [_mail.id]);
        expect(display.shown, isEmpty);
      },
    );

    test(
      'a failed action keeps the notification and says it did not happen',
      () async {
        final display = _RecordingDisplay();

        final done = await MailNotifications.runAction(
          _mail,
          MailNotificationAction.trash,
          execute: executor(503),
          display: display,
        );

        expect(done, isFalse);
        expect(requests.single.url.path, '/api/mails/mail-9/trash');
        expect(display.cancelled, isEmpty);
        final (shown, notice) = display.shown.single;
        expect(shown.mailId, 'mail-9');
        expect(notice, contains('Sil'));
      },
    );

    test(
      'a mail already gone on the server just clears the notification',
      () async {
        final display = _RecordingDisplay();

        final done = await MailNotifications.runAction(
          _mail,
          MailNotificationAction.read,
          execute: executor(404),
          display: display,
        );

        expect(done, isTrue);
        expect(requests.single.url.path, '/api/mails/mail-9/read');
        expect(display.cancelled, [_mail.id]);
        expect(display.shown, isEmpty);
      },
    );

    test('reply is never executed in the background', () async {
      final display = _RecordingDisplay();

      final done = await MailNotifications.runAction(
        _mail,
        MailNotificationAction.reply,
        execute: executor(204),
        display: display,
      );

      expect(done, isFalse);
      expect(requests, isEmpty);
      expect(display.cancelled, isEmpty);
    });
  });
}
