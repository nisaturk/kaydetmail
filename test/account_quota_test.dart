import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/settings_screen.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiMailService.getQuota', () {
    Future<AccountQuota?> quotaFor(Map<String, Object?> body) {
      final service = ApiMailService(
        ApiClient(
          tokenStore: TokenStore(storage: _MemoryTokenStorage()),
          accountId: 'account-1',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/account/quota');
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      return service.getQuota();
    }

    test('maps an available quota to bytes', () async {
      final quota = await quotaFor({
        'available': true,
        'usedBytes': 10240,
        'limitBytes': 524288,
      });
      expect(quota?.usedBytes, 10240);
      expect(quota?.limitBytes, 524288);
    });

    test('unsupported or incomplete quota is absent', () async {
      expect(
        await quotaFor({
          'available': false,
          'usedBytes': null,
          'limitBytes': null,
        }),
        isNull,
      );
      expect(
        await quotaFor({'available': true, 'usedBytes': 1, 'limitBytes': null}),
        isNull,
      );
    });
  });

  test('AccountQuota percent and fraction stay within the bar', () {
    const quota = AccountQuota(usedBytes: 3 * 1024, limitBytes: 4 * 1024);
    expect(quota.usedPercent, 75);
    expect(quota.usedFraction, 0.75);
    const over = AccountQuota(usedBytes: 5, limitBytes: 4);
    expect(over.usedFraction, 1.0);
  });

  test('formatStorageSize uses binary units and a Turkish comma', () {
    expect(formatStorageSize(512 * 1024), '512 KB');
    expect(formatStorageSize(1536 * 1024 * 1024), '1,5 GB');
    expect(formatStorageSize(15 * 1024 * 1024 * 1024), '15 GB');
  });

  test('quota loads per account, unsupported servers stay hidden, failures keep the last value', () async {
    final one = _fakeAccount(
      accountId: 'account-1',
      email: 'one@example.com',
      quota: const AccountQuota(usedBytes: 10, limitBytes: 100),
    );
    await one.authService.tokenStore.save(
      accountId: 'account-1',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
    );
    final two = _fakeAccount(
      accountId: 'account-2',
      email: 'two@example.com',
      quota: null,
    );
    final repo = ApiMailRepository(
      authService: one.authService,
      mailService: one.mailService,
      sessionFactory: () =>
          (authService: two.authService, mailService: two.mailService),
    );

    await repo.restoreSession('one@example.com');
    await repo.connectAccount(email: 'two@example.com', password: 'pw');
    await repo.refreshQuota('account-1');
    await repo.refreshQuota('account-2');

    expect(repo.getAccount('account-1')?.quota?.usedBytes, 10);
    expect(repo.getAccount('account-1')?.quota?.limitBytes, 100);
    expect(repo.getAccount('account-2')?.quota, isNull);
    expect(two.mailService.quotaCalls, greaterThan(0));

    one.mailService.quotaError = const ApiException(status: 503);
    await repo.refreshQuota('account-1');
    expect(repo.getAccount('account-1')?.quota?.usedBytes, 10);

    one.mailService
      ..quotaError = null
      ..quota = null;
    await repo.refreshQuota('account-1');
    expect(repo.getAccount('account-1')?.quota, isNull);
  });

  group('Account settings storage row', () {
    Future<void> pump(
      WidgetTester tester,
      _SettingsRepo repo,
      String id,
    ) async {
      AppConfig.mailRepositoryForTest = repo;
      await tester.pumpWidget(
        MaterialApp(home: AccountSettingsScreen(accountId: id)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows used/total and percent for the opened account', (
      tester,
    ) async {
      final repo = _SettingsRepo();
      await pump(tester, repo, 'with-quota');

      expect(repo.refreshed, ['with-quota']);
      expect(find.byKey(const Key('account-quota')), findsOneWidget);
      expect(find.text('256 MB / 1 GB kullanılıyor (%25)'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.25);
    });

    testWidgets('hides the row when the server exposes no quota', (
      tester,
    ) async {
      final repo = _SettingsRepo();
      await pump(tester, repo, 'no-quota');

      expect(repo.refreshed, ['no-quota']);
      expect(find.byKey(const Key('account-quota')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}

class _SettingsRepo extends MailRepository {
  final refreshed = <String>[];

  @override
  List<MailAccount> get accounts => const [
    MailAccount(
      id: 'with-quota',
      email: 'quota@example.com',
      quota: AccountQuota(
        usedBytes: 256 * 1024 * 1024,
        limitBytes: 1024 * 1024 * 1024,
      ),
    ),
    MailAccount(id: 'no-quota', email: 'plain@example.com'),
  ];

  @override
  Future<void> refreshQuota(String accountId) async => refreshed.add(accountId);

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

({ApiAuthService authService, _QuotaMailService mailService}) _fakeAccount({
  required String accountId,
  required String email,
  required AccountQuota? quota,
}) {
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  final client = ApiClient(
    tokenStore: tokenStore,
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/accounts/discover') {
        return http.Response(
          jsonEncode({
            'discoveryId': 'discovery-$accountId',
            'email': email,
            'provider': 'Custom',
            'authenticationMethods': ['Password'],
            'manualSetupAvailable': true,
          }),
          200,
        );
      }
      if (request.url.path == '/api/accounts/connect') {
        return http.Response(
          jsonEncode({
            'accessToken': 'access-$accountId',
            'refreshToken': 'refresh-$accountId',
            'mailAccountId': accountId,
            'accessTokenExpiresAt': '2026-09-18T08:14:33Z',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    }),
  );
  final authService = ApiAuthService(
    client: client,
    tokenStore: tokenStore,
    deviceIdentifierProvider: MemoryDeviceIdentifierProvider(
      'device-$accountId',
    ),
  );
  final mailService = _QuotaMailService(
    client,
    accountId: accountId,
    email: email,
    quota: quota,
  );
  return (authService: authService, mailService: mailService);
}

class _QuotaMailService extends ApiMailService {
  _QuotaMailService(
    super.client, {
    required this.accountId,
    required this.email,
    required this.quota,
  });

  final String accountId;
  final String email;
  AccountQuota? quota;
  Object? quotaError;
  int quotaCalls = 0;

  @override
  Future<MailAccount> getAccount() async =>
      MailAccount(id: accountId, email: email);

  @override
  Future<AccountQuota?> getQuota() async {
    quotaCalls++;
    if (quotaError case final error?) throw error;
    return quota;
  }

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: 'folder-$accountId',
      mailAccountId: accountId,
      name: 'Inbox',
      type: 'Inbox',
    ),
  ];

  @override
  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    bool? hasAttachments,
    String? search,
  }) async =>
      MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);
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
