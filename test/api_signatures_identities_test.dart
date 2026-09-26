import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

import 'support/wire_multipart.dart';

void main() {
  test('signature service sends CRUD shapes and maps responses', () async {
    final calls = <http.Request>[];
    final client = _client((request) async {
      calls.add(request);
      final signature = {
        'id': 'sig-1',
        'name': 'Resmi',
        'bodyText': 'Saygılarımla',
        'bodyHtml': null,
        'createdAt': '2026-09-25T09:00:00Z',
        'updatedAt': '2026-09-25T09:00:00Z',
      };
      if (request.method == 'GET') {
        return _jsonResponse({
          'items': [signature],
          'defaults': {
            'newMailSignatureId': 'sig-1',
            'replySignatureId': null,
            'forwardSignatureId': null,
          },
        });
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      if (request.url.path == '/api/signatures/defaults') {
        return _jsonResponse({
          'newMailSignatureId': 'sig-1',
          'replySignatureId': 'sig-1',
          'forwardSignatureId': null,
        });
      }
      return _jsonResponse(signature);
    });
    final service = ApiMailService(client);
    final signature = MailSignature(
      id: 'sig-1',
      name: 'Resmi',
      bodyText: 'Saygılarımla',
      createdAt: DateTime.utc(2026, 9, 25, 9),
      updatedAt: DateTime.utc(2026, 9, 25, 9),
    );

    final listed = await service.getSignatures();
    expect(listed.items.single.name, 'Resmi');
    expect(listed.defaults.newMailSignatureId, 'sig-1');
    await service.createSignature(signature);
    await service.updateSignatureItem(signature);
    await service.deleteSignature(signature.id);
    final defaults = await service.updateSignatureDefaults(
      const SignatureDefaults(
        newMailSignatureId: 'sig-1',
        replySignatureId: 'sig-1',
      ),
    );
    expect(defaults.replySignatureId, 'sig-1');

    expect(calls.map((call) => '${call.method} ${call.url.path}'), [
      'GET /api/signatures',
      'POST /api/signatures',
      'PUT /api/signatures/sig-1',
      'DELETE /api/signatures/sig-1',
      'PUT /api/signatures/defaults',
    ]);
    expect(jsonDecode(calls[1].body), {
      'name': 'Resmi',
      'bodyText': 'Saygılarımla',
      'bodyHtml': null,
    });
    expect(jsonDecode(calls[4].body), {
      'newMailSignatureId': 'sig-1',
      'replySignatureId': 'sig-1',
      'forwardSignatureId': null,
    });
  });

  test('identity service sends CRUD shapes and maps responses', () async {
    final calls = <http.Request>[];
    final client = _client((request) async {
      calls.add(request);
      final identity = {
        'id': 'id-1',
        'emailAddress': 'alias@x.com',
        'displayName': 'Takma Ad',
        'replyTo': null,
        'signatureId': 'sig-1',
        'isDefault': true,
      };
      if (request.method == 'GET') {
        return _jsonResponse({'items': [identity]});
      }
      if (request.method == 'DELETE') return http.Response('', 204);
      return _jsonResponse(identity);
    });
    final service = ApiMailService(client);
    final identity = MailIdentity(
      id: 'id-1',
      emailAddress: 'alias@x.com',
      displayName: 'Takma Ad',
      signatureId: 'sig-1',
      isDefault: true,
    );

    expect((await service.getIdentities()).single.emailAddress, 'alias@x.com');
    await service.createIdentity(identity);
    await service.updateIdentity(identity);
    await service.deleteIdentity(identity.id);

    expect(calls.map((call) => '${call.method} ${call.url.path}'), [
      'GET /api/identities',
      'POST /api/identities',
      'PUT /api/identities/id-1',
      'DELETE /api/identities/id-1',
    ]);
    expect(jsonDecode(calls[1].body), {
      'emailAddress': 'alias@x.com',
      'displayName': 'Takma Ad',
      'replyTo': null,
      'signatureId': 'sig-1',
      'isDefault': true,
    });
  });

  test('sendMail threads identityId as a multipart field', () async {
    late WireMultipart sent;
    final service = ApiMailService(
      _multipartClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'sent': true, 'sentCopySaved': true}),
          200,
        );
      }),
    );

    await service.sendMail(
      to: ['a@x.com'],
      subject: 'Konu',
      bodyText: 'Gövde',
      identityId: 'id-1',
      idempotencyKey: 'key-1',
    );

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/mails/send');
    expect(sent.fields['identityId'], 'id-1');
  });

  test('createDraft threads identityId as a multipart field', () async {
    late WireMultipart sent;
    final service = ApiMailService(
      _multipartClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({'created': true, 'mailId': 'draft-1'}),
          200,
        );
      }),
    );

    await service.createDraft(
      to: ['a@x.com'],
      subject: 'Konu',
      bodyText: 'Gövde',
      identityId: 'id-1',
    );

    expect(sent.method, 'POST');
    expect(sent.url.path, '/api/drafts');
    expect(sent.fields['identityId'], 'id-1');
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
  Future<http.Response> Function(WireMultipart) handler,
) => ApiClient(
  tokenStore: TokenStore(storage: _MemoryTokenStorage()),
  accountId: 'account-1',
  httpClient: MockClient.streaming((request, bodyStream) async {
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
