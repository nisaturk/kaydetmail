import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_snippet.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test('snippet service sends CRUD shapes and maps responses', () async {
    final calls = <http.Request>[];
    final json = {
      'id': 'sn-1',
      'title': null,
      'text': 'İyi çalışmalar.',
      'sortOrder': 2,
      'createdAt': '2026-09-25T09:00:00Z',
      'updatedAt': '2026-09-25T09:00:00Z',
    };
    final client = ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient((request) async {
        calls.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        if (request.method == 'GET') {
          return _jsonResponse({
            'items': [json],
          });
        }
        return _jsonResponse(json, request.method == 'POST' ? 201 : 200);
      }),
    );
    final service = ApiMailService(client);
    final draft = MailSnippet(
      id: 'sn-1',
      text: 'İyi çalışmalar.',
      sortOrder: 2,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect((await service.getSnippets()).single.text, 'İyi çalışmalar.');
    final created = await service.createSnippet(draft);
    expect(created.title, isNull);
    await service.updateSnippet(draft);
    await service.deleteSnippet('sn-1');

    expect(calls.map((c) => '${c.method} ${c.url.path}'), [
      'GET /api/snippets',
      'POST /api/snippets',
      'PUT /api/snippets/sn-1',
      'DELETE /api/snippets/sn-1',
    ]);
    expect(jsonDecode(calls[1].body), {
      'title': null,
      'text': 'İyi çalışmalar.',
      'sortOrder': 2,
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
