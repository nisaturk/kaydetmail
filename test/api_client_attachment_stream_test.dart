import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'stream GET sends auth and Range and reports bytes as consumed',
    () async {
      final storage = _Storage();
      final tokens = TokenStore(storage: storage);
      await tokens.save(
        accountId: 'account-1',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      late http.Request sent;
      final client = ApiClient(
        tokenStore: tokens,
        accountId: 'account-1',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response.bytes(
            [5, 6],
            206,
            headers: const {
              'content-length': '2',
              'content-range': 'bytes 5-6/7',
            },
          );
        }),
      );
      final progress = <(int, int?)>[];
      final response = await client.getStream(
        '/api/mails/m1/attachments/a1',
        rangeStart: 5,
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(sent.headers['authorization'], 'Bearer access-token');
      expect(sent.headers['range'], 'bytes=5-');
      expect(await response.stream.toList(), [
        [5, 6],
      ]);
      expect(progress, [(2, 2)]);
    },
  );

  test('stream GET refreshes once after 401 before reading bytes', () async {
    final tokens = TokenStore(storage: _Storage());
    await tokens.save(
      accountId: 'account-1',
      accessToken: 'expired',
      refreshToken: 'refresh-token',
    );
    var attachmentRequests = 0;
    final client = ApiClient(
      tokenStore: tokens,
      accountId: 'account-1',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/auth/refresh') {
          return http.Response(
            jsonEncode({'accessToken': 'fresh', 'refreshToken': 'refresh-2'}),
            200,
          );
        }
        attachmentRequests++;
        if (attachmentRequests == 1) return http.Response('', 401);
        expect(request.headers['authorization'], 'Bearer fresh');
        return http.Response.bytes([7], 200);
      }),
    );
    final response = await client.getStream('/api/mails/m1/attachments/a1');
    expect(await response.stream.toList(), [
      [7],
    ]);
    expect(attachmentRequests, 2);
  });

  test('caller abort interrupts a streaming response', () async {
    final tokens = TokenStore(storage: _Storage());
    await tokens.save(
      accountId: 'account-1',
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    final abort = Completer<void>();
    final body = StreamController<List<int>>();
    var aborted = false;
    final client = ApiClient(
      tokenStore: tokens,
      accountId: 'account-1',
      httpClient: MockClient.streaming((request, _) async {
        final abortable = request as http.AbortableRequest;
        abortable.abortTrigger!.then((_) => aborted = true);
        return http.StreamedResponse(body.stream, 200);
      }),
    );
    final response = await client.getStream(
      '/api/mails/m1/attachments/a1',
      abortTrigger: abort.future,
    );
    final streamError = expectLater(
      response.stream.toList(),
      throwsA(isA<http.RequestAbortedException>()),
    );
    abort.complete();
    await streamError;
    expect(aborted, isTrue);
    await body.close();
  });
}
