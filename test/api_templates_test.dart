import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_template.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test('template service sends CRUD request shapes and maps responses', () async {
    final calls = <http.Request>[];
    final client = ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      httpClient: MockClient((request) async {
        calls.add(request);
        final template = {
          'id': 'template-1',
          'name': 'Toplantı',
          'subject': 'Haftalık',
          'bodyText': 'Merhaba',
          'bodyHtml': null,
          'createdAt': '2026-09-25T09:00:00Z',
          'updatedAt': '2026-09-25T09:00:00Z',
        };
        if (request.method == 'GET') {
          return _jsonResponse({'items': [template]});
        }
        if (request.method == 'DELETE') return http.Response('', 204);
        return _jsonResponse(template);
      }),
    );
    await client.tokenStore.save(
      accountId: 'account-1',
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    client.bindAccount('account-1');
    final service = ApiMailService(client);
    final template = MailTemplate(
      id: 'template-1',
      name: 'Toplantı',
      subject: 'Haftalık',
      bodyText: 'Merhaba',
      createdAt: DateTime.utc(2026, 9, 25, 9),
      updatedAt: DateTime.utc(2026, 9, 25, 9),
    );

    expect((await service.getTemplates()).single.name, 'Toplantı');
    await service.createTemplate(template);
    await service.updateTemplate(template);
    await service.deleteTemplate(template.id);

    expect(calls.map((call) => '${call.method} ${call.url.path}'), [
      'GET /api/templates',
      'POST /api/templates',
      'PUT /api/templates/template-1',
      'DELETE /api/templates/template-1',
    ]);
    expect(jsonDecode(calls[1].body), {
      'name': 'Toplantı',
      'subject': 'Haftalık',
      'bodyText': 'Merhaba',
      'bodyHtml': null,
    });
    expect(jsonDecode(calls[2].body), jsonDecode(calls[1].body));
  });
}

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// `http.Response` defaults to latin1 — Turkish bodies need explicit UTF-8.
http.Response _jsonResponse(Map<String, dynamic> json) => http.Response.bytes(
  utf8.encode(jsonEncode(json)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
