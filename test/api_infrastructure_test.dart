import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/push_service.dart';
import 'package:kaydetmail/services/server_address_store.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryTokenStorage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Server URL', () {
    test('Given saved base URL When API client builds path Then slash is not duplicated', () async {
      SharedPreferences.setMockInitialValues({
        'kaydet.server.baseUrl': 'http://localhost:5071/',
      });
      final tokenStore = TokenStore(storage: MemoryTokenStorage());
      final seen = <Uri>[];
      final client = ApiClient(
        tokenStore: tokenStore,
        httpClient: MockClient((request) async {
          seen.add(request.url);
          return http.Response('{}', 200);
        }),
      );

      await client.get('/api/accounts/discover', authenticated: false);

      expect(
        seen.single.toString(),
        'http://localhost:5071/api/accounts/discover',
      );
    });

    test('Given no saved URL When loading default Then backend development URL is used', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await ServerAddressStore.load(), 'http://localhost:5071');
    });
  });

  group('TokenStore', () {
    test(
      'Given tokens When saved Then values can be read and cleared',
      () async {
        final store = TokenStore(storage: MemoryTokenStorage());

        await store.save(
          accessToken: 'access',
          refreshToken: 'refresh',
          mailAccountId: 'account-1',
        );

        expect(await store.readAccessToken(), 'access');
        expect(await store.readRefreshToken(), 'refresh');
        expect(await store.readMailAccountId(), 'account-1');

        await store.clear();

        expect(await store.readAccessToken(), isNull);
        expect(await store.readRefreshToken(), isNull);
        expect(await store.readMailAccountId(), isNull);
      },
    );
  });

  group('ApiException', () {
    test('Given Problem Details JSON When parsed Then code and correlationId are preserved', () {
      final exception = ApiException.fromResponse(
        401,
        jsonEncode({
          'code': 'mail_authentication_failed',
          'title': 'Bad credentials',
          'status': 401,
          'correlationId': 'corr-1',
        }),
      );

      expect(exception.status, 401);
      expect(exception.code, 'mail_authentication_failed');
      expect(exception.title, 'Bad credentials');
      expect(exception.correlationId, 'corr-1');
      expect(exception.userMessage, 'E-posta şifresi reddedildi.');
    });

    test('Given empty response body When parsed Then it does not crash', () {
      final exception = ApiException.fromResponse(429, '');

      expect(exception.status, 429);
      expect(exception.code, isNull);
      expect(exception.correlationId, isNull);
    });
  });

  group('ApiClient', () {
    test('Given access token When authenticated request is sent Then Authorization header is attached', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(storage: MemoryTokenStorage());
      await store.save(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        mailAccountId: 'account-1',
      );
      final headers = <String, String>{};
      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          headers.addAll(request.headers);
          return http.Response('{}', 200);
        }),
      );

      await client.get('/api/account');

      expect(headers['authorization'], 'Bearer access-1');
      expect(headers['accept'], 'application/json');
    });

    test(
      'Given anonymous request When sent Then Authorization header is omitted',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = TokenStore(storage: MemoryTokenStorage());
        await store.save(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          mailAccountId: 'account-1',
        );
        final headers = <String, String>{};
        final client = ApiClient(
          tokenStore: store,
          httpClient: MockClient((request) async {
            headers.addAll(request.headers);
            return http.Response('{}', 200);
          }),
        );

        await client.postJson('/api/accounts/discover', {
          'email': 'person@example.com',
        }, authenticated: false);

        expect(headers.containsKey('authorization'), isFalse);
      },
    );

    test('Given expired access token When request gets 401 Then refresh rotates token and retry uses new access token', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(storage: MemoryTokenStorage());
      await store.save(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        mailAccountId: 'account-1',
      );
      final authorizations = <String?>[];
      var refreshCalls = 0;
      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            refreshCalls++;
            expect(jsonDecode(request.body)['refreshToken'], 'old-refresh');
            return http.Response(
              jsonEncode({
                'accessToken': 'new-access',
                'refreshToken': 'new-refresh',
                'mailAccountId': 'account-1',
                'accessTokenExpiresAt': '2026-09-18T08:14:33Z',
              }),
              200,
            );
          }
          authorizations.add(request.headers['authorization']);
          if (authorizations.length == 1) {
            return http.Response(
              jsonEncode({
                'code': 'invalid_token',
                'title': 'Expired',
                'status': 401,
              }),
              401,
            );
          }
          return http.Response('{"ok":true}', 200);
        }),
      );

      final response = await client.get('/api/account');

      expect(response['ok'], isTrue);
      expect(refreshCalls, 1);
      expect(authorizations, ['Bearer old-access', 'Bearer new-access']);
      expect(await store.readRefreshToken(), 'new-refresh');
    });

    test('Given concurrent 401s When they refresh Then only one refresh request is made', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(storage: MemoryTokenStorage());
      await store.save(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        mailAccountId: 'account-1',
      );
      var refreshCalls = 0;
      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            refreshCalls++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return http.Response(
              jsonEncode({
                'accessToken': 'new-access',
                'refreshToken': 'new-refresh',
                'mailAccountId': 'account-1',
                'accessTokenExpiresAt': '2026-09-18T08:14:33Z',
              }),
              200,
            );
          }
          if (request.headers['authorization'] == 'Bearer old-access') {
            return http.Response(
              jsonEncode({
                'code': 'invalid_token',
                'title': 'Expired',
                'status': 401,
              }),
              401,
            );
          }
          return http.Response('{"ok":true}', 200);
        }),
      );

      await Future.wait([
        client.get('/api/account'),
        client.get('/api/account'),
        client.get('/api/account'),
      ]);

      expect(refreshCalls, 1);
      expect(await store.readAccessToken(), 'new-access');
    });

    test('Given invalid refresh token When refresh fails Then stored session is cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(storage: MemoryTokenStorage());
      await store.save(
        accessToken: 'old-access',
        refreshToken: 'bad-refresh',
        mailAccountId: 'account-1',
      );
      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            return http.Response(
              jsonEncode({
                'code': 'invalid_refresh_token',
                'title': 'Invalid refresh token',
                'status': 401,
                'correlationId': 'corr-1',
              }),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'code': 'invalid_token',
              'title': 'Expired',
              'status': 401,
            }),
            401,
          );
        }),
      );

      await expectLater(
        client.get('/api/account'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_refresh_token',
          ),
        ),
      );
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
      expect(await store.readMailAccountId(), isNull);
    });
  });

  group('Authentication', () {
    test(
      'Given email When discover is called Then documented body is sent',
      () async {
        SharedPreferences.setMockInitialValues({});
        late Map<String, dynamic> body;
        final auth = ApiAuthService(
          client: ApiClient(
            tokenStore: TokenStore(storage: MemoryTokenStorage()),
            httpClient: MockClient((request) async {
              body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'discoveryId': 'discovery-1',
                  'email': 'person@example.com',
                  'provider': 'Custom',
                  'authenticationMethods': ['Password'],
                  'manualSetupAvailable': true,
                }),
                200,
              );
            }),
          ),
          tokenStore: TokenStore(storage: MemoryTokenStorage()),
          deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-1'),
        );

        final discovery = await auth.discover('person@example.com');

        expect(body, {'email': 'person@example.com'});
        expect(discovery.discoveryId, 'discovery-1');
        expect(discovery.provider, AccountProvider.other);
      },
    );

    test('Given discovery and password When connect succeeds Then token response is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final tokenStore = TokenStore(storage: MemoryTokenStorage());
      late Map<String, dynamic> body;
      final auth = ApiAuthService(
        client: ApiClient(
          tokenStore: tokenStore,
          httpClient: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'accessToken': 'access',
                'refreshToken': 'refresh',
                'mailAccountId': 'account-1',
                'accessTokenExpiresAt': '2026-09-18T08:14:33Z',
              }),
              200,
            );
          }),
        ),
        tokenStore: tokenStore,
        deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-1'),
      );

      final response = await auth.connect(
        discoveryId: 'discovery-1',
        password: 'secret',
      );

      expect(body, {
        'discoveryId': 'discovery-1',
        'authentication': {'type': 'Password', 'password': 'secret'},
        'deviceIdentifier': 'device-1',
      });
      expect(response.mailAccountId, 'account-1');
      expect(await tokenStore.readAccessToken(), 'access');
      expect(await tokenStore.readRefreshToken(), 'refresh');
      expect(await tokenStore.readMailAccountId(), 'account-1');
    });

    test('Given manual settings When connectManual is called Then documented structure is sent', () async {
      SharedPreferences.setMockInitialValues({});
      final tokenStore = TokenStore(storage: MemoryTokenStorage());
      late Map<String, dynamic> body;
      final auth = ApiAuthService(
        client: ApiClient(
          tokenStore: tokenStore,
          httpClient: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'accessToken': 'access',
                'refreshToken': 'refresh',
                'mailAccountId': 'account-1',
                'accessTokenExpiresAt': '2026-09-18T08:14:33Z',
              }),
              200,
            );
          }),
        ),
        tokenStore: tokenStore,
        deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-1'),
      );

      await auth.connectManual(
        email: 'person@example.com',
        username: 'person@example.com',
        password: 'secret',
        imap: const ManualMailServer(
          host: 'imap.example.com',
          port: 993,
          security: MailSecurity.sslOnConnect,
        ),
        smtp: const ManualMailServer(
          host: 'smtp.example.com',
          port: 587,
          security: MailSecurity.startTls,
        ),
        displayName: 'Kişisel',
      );

      expect(body, {
        'email': 'person@example.com',
        'username': 'person@example.com',
        'authentication': {'type': 'Password', 'password': 'secret'},
        'imap': {
          'host': 'imap.example.com',
          'port': 993,
          'security': 'SslOnConnect',
        },
        'smtp': {
          'host': 'smtp.example.com',
          'port': 587,
          'security': 'StartTls',
        },
        'displayName': 'Kişisel',
        'deviceIdentifier': 'device-1',
      });
    });

    test('Given refresh token When logout is called Then server logout attempted and tokens cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final tokenStore = TokenStore(storage: MemoryTokenStorage());
      await tokenStore.save(
        accessToken: 'access',
        refreshToken: 'refresh',
        mailAccountId: 'account-1',
      );
      late Map<String, dynamic> body;
      final auth = ApiAuthService(
        client: ApiClient(
          tokenStore: tokenStore,
          httpClient: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response('', 204);
          }),
        ),
        tokenStore: tokenStore,
        deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-1'),
      );

      await auth.logout();

      expect(body, {'refreshToken': 'refresh'});
      expect(await tokenStore.readAccessToken(), isNull);
    });
  });

  group('MailAccount', () {
    test(
      'Given server account id When MailAccount is built Then id is preserved',
      () {
        const account = MailAccount(
          id: 'server-id',
          email: 'person@example.com',
        );

        expect(account.id, 'server-id');
        expect(account.email, 'person@example.com');
      },
    );

    test('Given backend provider strings When mapped Then supported providers are centralized', () {
      expect(AccountProvider.fromBackend('Google'), AccountProvider.google);
      expect(
        AccountProvider.fromBackend('Microsoft'),
        AccountProvider.microsoft,
      );
      expect(AccountProvider.fromBackend('ICloud'), AccountProvider.other);
      expect(AccountProvider.fromBackend('Yahoo'), AccountProvider.other);
      expect(AccountProvider.fromBackend('Custom'), AccountProvider.other);
    });
  });

  group('Devices', () {
    test('Given FCM token When registerDevice is called Then upsert body is sent and registration parsed', () async {
      SharedPreferences.setMockInitialValues({});
      late String path;
      late Map<String, dynamic> body;
      final service = ApiMailService(
        _clientForDevices((request) async {
          path = request.url.path;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'id': 'dev-1',
              'platform': 'android',
              'appVersion': '1.4.0',
              'locale': 'tr-TR',
              'registeredAt': '2026-09-18T08:00:00Z',
            }),
            201,
          );
        }),
      );

      final dev = await service.registerDevice(
        token: 'fcm-t',
        platform: 'android',
        appVersion: '1.4.0',
        locale: 'tr-TR',
      );

      expect(path, '/api/devices');
      expect(body['token'], 'fcm-t');
      expect(dev.id, 'dev-1');
      expect(dev.platform, 'android');
    });

    test('Given device id When unregisterDevice is called Then DELETE hits the device path', () async {
      SharedPreferences.setMockInitialValues({});
      late String path;
      late String method;
      final service = ApiMailService(
        _clientForDevices((request) async {
          path = request.url.path;
          method = request.method;
          return http.Response('', 204);
        }),
      );

      await service.unregisterDevice('dev-1');

      expect(method, 'DELETE');
      expect(path, '/api/devices/dev-1');
    });
  });

  group('Rate limiting', () {
    test('Given 429 on a GET When retried Then it succeeds without surfacing the error', () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(storage: MemoryTokenStorage());
      var calls = 0;
      final client = ApiClient(
        tokenStore: store,
        httpClient: MockClient((_) async {
          calls++;
          if (calls == 1) return http.Response('', 429);
          return http.Response('{"ok":true}', 200);
        }),
      );

      final body = await client.get('/api/account', authenticated: false);

      expect(body['ok'], isTrue);
      expect(calls, 2);
    });

    test(
      'Given 429 on a POST When sent Then it throws immediately without retry',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = TokenStore(storage: MemoryTokenStorage());
        var calls = 0;
        final client = ApiClient(
          tokenStore: store,
          httpClient: MockClient((_) async {
            calls++;
            return http.Response('', 429);
          }),
        );

        await expectLater(
          client.post('/api/account/sessions/x'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)),
        );
        expect(calls, 1);
      },
    );
  });

  group('Push handling', () {
    test('Given new_mail data When handled Then the mail is fetched by id, never read from the payload', () async {
      final fetched = <String>[];
      await handlePushData(const {
        'type': 'new_mail',
        'mailId': 'm-1',
      }, fetchMail: (id) async => fetched.add(id));

      expect(fetched, ['m-1']);
    });

    test(
      'Given reauthentication push When handled Then the reauth callback fires',
      () async {
        var reauthCalls = 0;
        await handlePushData(
          const {'type': 'account_reauthentication_required'},
          fetchMail: (_) async {},
          onAccountReauth: () async => reauthCalls++,
        );

        expect(reauthCalls, 1);
      },
    );

    test(
      'Given mail without id When handled Then nothing is fetched',
      () async {
        var calls = 0;
        await handlePushData(const {
          'type': 'new_mail',
        }, fetchMail: (_) async => calls++);

        expect(calls, 0);
      },
    );
  });
}

ApiClient _clientForDevices(
  Future<http.Response> Function(http.Request) handler,
) => ApiClient(
  tokenStore: TokenStore(storage: MemoryTokenStorage()),
  httpClient: MockClient(handler),
);
