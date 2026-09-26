import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as testing;
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('multipart reports monotonic bytes through the complete body', () async {
    final store = TokenStore(storage: _MemoryTokenStorage());
    await store.save(
      accountId: 'account-1',
      accessToken: 'token',
      refreshToken: 'refresh',
    );
    final progress = <(int, int)>[];
    var bodyLength = 0;
    final client = ApiClient(
      tokenStore: store,
      httpClient: testing.MockClient.streaming((request, body) async {
        final bytes = await body.toBytes();
        bodyLength = bytes.length;
        return http.StreamedResponse(Stream.value('{}'.codeUnits), 200);
      }),
    )..bindAccount('account-1');
    addTearDown(client.close);

    await client.multipart(
      '/api/mails/send',
      fields: const {'subject': 'hello'},
      files: () => [
        http.MultipartFile.fromBytes('attachments', List.filled(200000, 7)),
      ],
      onProgress: (sent, total) => progress.add((sent, total)),
    );

    expect(progress, isNotEmpty);
    expect(progress.first.$1, 0);
    expect(progress.last.$1, progress.last.$2);
    expect(progress.last.$2, bodyLength);
    expect(
      progress.map((event) => event.$1).toList(),
      orderedEquals(progress.map((event) => event.$1).toList()..sort()),
    );
  });

  test('multipart abort interrupts an incomplete request body', () async {
    final store = TokenStore(storage: _MemoryTokenStorage());
    await store.save(
      accountId: 'account-1',
      accessToken: 'token',
      refreshToken: 'refresh',
    );
    final abort = Completer<void>();
    final client = ApiClient(
      tokenStore: store,
      httpClient: testing.MockClient.streaming((request, body) async {
        await for (final _ in body) {}
        return http.StreamedResponse(Stream.value('{}'.codeUnits), 200);
      }),
    )..bindAccount('account-1');
    addTearDown(client.close);

    final upload = client.multipart(
      '/api/mails/send',
      fields: const {},
      files: () => [
        http.MultipartFile.fromBytes('attachments', List.filled(300000, 1)),
      ],
      abortTrigger: abort.future,
      onProgress: (sent, total) {
        if (sent > 0 && !abort.isCompleted) abort.complete();
      },
    );

    await expectLater(
      upload,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'upload_cancelled'),
      ),
    );
  });
}
