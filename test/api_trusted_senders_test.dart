import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/trusted_sender.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test('trusted sender service sends API shapes and maps kinds', () async {
    final calls = <http.Request>[];
    final entry = {
      'id': 'ts-1',
      'kind': 'Domain',
      'value': 'corp.example',
      'createdAt': '2026-09-26T08:00:00Z',
    };
    final client = ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient((request) async {
        calls.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        if (request.method == 'GET') {
          return _jsonResponse({
            'items': [entry],
          });
        }
        return _jsonResponse(entry, 201);
      }),
    );
    final service = ApiMailService(client);

    final list = await service.getTrustedSenders();
    expect(list.single.kind, TrustedSenderKind.domain);
    expect(list.single.value, 'corp.example');
    await service.addTrustedSender(TrustedSenderKind.sender, 'a@corp.example');
    await service.removeTrustedSender('ts-1');

    expect(calls.map((c) => '${c.method} ${c.url.path}'), [
      'GET /api/trusted-senders',
      'POST /api/trusted-senders',
      'DELETE /api/trusted-senders/ts-1',
    ]);
    expect(jsonDecode(calls[1].body), {
      'kind': 'Sender',
      'value': 'a@corp.example',
    });
  });
}

http.Response _jsonResponse(Object json, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(json)),
      status,
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
