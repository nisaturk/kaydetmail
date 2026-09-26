import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test('reply reminder service sends CRUD shapes and maps responses',
      () async {
    final calls = <http.Request>[];
    final client = ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient((request) async {
        calls.add(request);
        final reminder = {
          'id': 'rem-1',
          'mailId': 'mail-1',
          'conversationId': null,
          'dueAtUtc': '2026-09-30T09:00:00Z',
          'createdAt': '2026-09-25T09:00:00Z',
          'status': 'Pending',
          'notifiedAt': null,
          'subject': 'Teklif',
          'recipient': 'musteri@x.com',
          'sentAt': '2026-09-25T08:00:00Z',
        };
        if (request.method == 'GET') {
          return _jsonResponse({
            'items': [reminder],
          });
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return _jsonResponse(reminder);
      }),
    );
    final service = ApiMailService(client);

    final created = await service.setReplyReminder(
      'mail-1',
      DateTime.utc(2026, 9, 30, 9),
    );
    expect(created.subject, 'Teklif');
    expect(created.recipient, 'musteri@x.com');
    await service.cancelReplyReminder('mail-1');
    expect((await service.listReplyReminders()).single.id, 'rem-1');

    expect(calls.map((call) => '${call.method} ${call.url.path}'), [
      'POST /api/mails/mail-1/reply-reminder',
      'DELETE /api/mails/mail-1/reply-reminder',
      'GET /api/reply-reminders',
    ]);
    expect(jsonDecode(calls[0].body), {
      'dueAtUtc': '2026-09-30T09:00:00.000Z',
    });
  });
}

http.Response _jsonResponse(Map<String, dynamic> json) => http.Response.bytes(
  utf8.encode(jsonEncode(json)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
