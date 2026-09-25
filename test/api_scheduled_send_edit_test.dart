import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

import 'support/wire_multipart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiMailService scheduled edit', () {
    test('getScheduledSend parses body and staged attachments', () async {
      late http.Request sent;
      final service = ApiMailService(
        _client((request) async {
          sent = request;
          return _jsonResponse({
            'id': 'sch-1',
            'to': ['a@example.com'],
            'cc': [],
            'bcc': [],
            'subject': 'Konu',
            'bodyText': 'Gövde',
            'bodyHtml': null,
            'sendAtUtc': '2026-10-01T10:00:00Z',
            'attachments': [
              {
                'id': 'att-1',
                'fileName': 'dosya.txt',
                'contentType': 'text/plain',
                'sizeBytes': 5,
              },
            ],
          });
        }),
      );

      final detail = await service.getScheduledSend('sch-1');

      expect(sent.method, 'GET');
      expect(sent.url.path, '/api/scheduled-sends/sch-1');
      expect(detail.to, ['a@example.com']);
      expect(detail.bodyText, 'Gövde');
      expect(detail.attachments.single.id, 'att-1');
      expect(detail.attachments.single.name, 'dosya.txt');
    });

    test('updateScheduledSend PUTs multipart with keepAttachmentIds', () async {
      late WireMultipart sent;
      final service = ApiMailService(
        _multipartClient((request) async {
          sent = request;
          return http.Response('{"ok":true}', 200);
        }, method: 'PUT'),
      );

      await service.updateScheduledSend(
        id: 'sch-1',
        to: ['a@example.com', 'b@example.com'],
        subject: 'Yeni konu',
        bodyText: 'Yeni gövde',
        sendAtUtc: DateTime.utc(2026, 10, 2, 10),
        keepAttachmentIds: ['att-1'],
        attachments: [
          Attachment(
            name: 'yeni.txt',
            sizeBytes: 3,
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );

      expect(sent.method, 'PUT');
      expect(sent.url.path, '/api/scheduled-sends/sch-1');
      expect(sent.values('To'), ['a@example.com', 'b@example.com']);
      expect(sent.values('keepAttachmentIds'), ['att-1']);
      expect(sent.fields['subject'], 'Yeni konu');
      expect(sent.fields['bodyText'], 'Yeni gövde');
      expect(sent.fields['sendAtUtc'], isNotEmpty);
      final added = sent.files.singleWhere((f) => f.filename == 'yeni.txt');
      expect(added.field, 'attachments');
    });

    test('rescheduleFailedSend posts JSON with fresh Idempotency-Key',
        () async {
      late http.Request sent;
      Map<String, dynamic>? sentBody;
      final service = ApiMailService(
        _client((request) async {
          sent = request;
          sentBody =
              jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'id': 'sch-2',
            'sendAtUtc': '2026-10-03T10:00:00Z',
            'status': 'Pending',
          });
        }),
      );

      await service.rescheduleFailedSend(
        id: 'sch-1',
        to: ['a@example.com'],
        subject: 'Konu',
        bodyText: 'Gövde',
        sendAtUtc: DateTime.utc(2026, 10, 3, 10),
        idempotencyKey: 'fresh-key',
      );

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/scheduled-sends/sch-1/reschedule');
      expect(sent.headers['Idempotency-Key'], 'fresh-key');
      expect(sentBody!['to'], ['a@example.com']);
      expect(sentBody!['subject'], 'Konu');
      expect(sentBody!['sendAtUtc'], isNotEmpty);
    });

    test('listScheduledSends maps DeliveryUnknown with attempt fields',
        () async {
      final service = ApiMailService(
        _client(
          (_) async => _jsonResponse({
            'items': [
              {
                'id': 'sch-9',
                'to': ['a@example.com'],
                'cc': [],
                'bcc': [],
                'subject': 'X',
                'sendAtUtc': '2026-10-01T10:00:00Z',
                'status': 'DeliveryUnknown',
                'createdAtUtc': '2026-09-30T10:00:00Z',
                'sentMailId': null,
                'failureReason': 'timeout',
                'attemptCount': 3,
                'nextAttemptAtUtc': null,
              },
            ],
          }),
        ),
      );

      final items = await service.listScheduledSends();

      expect(items.single.status, ScheduledSendStatus.deliveryUnknown);
      expect(items.single.attemptCount, 3);
      expect(items.single.failureReason, 'timeout');
    });
  });
}

http.Response _jsonResponse(Map<String, dynamic> json) => http.Response.bytes(
      utf8.encode(jsonEncode(json)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient(handler),
    );

ApiClient _multipartClient(
  Future<http.Response> Function(WireMultipart) handler, {
  String method = 'POST',
}) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient.streaming((request, bodyStream) async {
        expect(request.method, method);
        final response = await handler(
          await WireMultipart.decode(request, bodyStream),
        );
        return http.StreamedResponse(
          Stream.value(response.bodyBytes),
          response.statusCode,
        );
      }),
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
