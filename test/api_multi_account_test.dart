import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression coverage for the multi-account bug report: connecting a
/// second mailbox used to silently replace the first one's session (single
/// shared `_account` field) instead of adding a second, independent one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Multi-account sessions', () {
    test(
      'connecting a second account keeps the first one fully intact',
      () async {
        final one = _fakeAccount(
          accountId: 'account-1',
          email: 'one@example.com',
          folderId: 'folder-1',
          mailIds: ['mail-1a', 'mail-1b'],
        );
        await one.authService.tokenStore.save(
          accountId: 'account-1',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        );
        final two = _fakeAccount(
          accountId: 'account-2',
          email: 'two@example.com',
          folderId: 'folder-2',
          mailIds: ['mail-2a'],
        );

        final repo = ApiMailRepository(
          authService: one.authService,
          mailService: one.mailService,
          sessionFactory: () =>
              (authService: two.authService, mailService: two.mailService),
        );

        await repo.restoreSession('one@example.com');
        await repo.loadMoreEmails(MailFolder.inbox);
        expect(repo.accounts.map((a) => a.id), ['account-1']);
        expect(
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          containsAll(['mail-1a', 'mail-1b']),
        );

        await repo.connectAccount(email: 'two@example.com', password: 'pw');
        await repo.loadMoreEmails(MailFolder.inbox);

        // The regression: both accounts stay connected — the first one is
        // never evicted by the second.
        expect(
          repo.accounts.map((a) => a.id),
          containsAll(['account-1', 'account-2']),
        );
        expect(repo.accounts.length, 2);
        expect(repo.getAccount('account-1')?.email, 'one@example.com');
        expect(repo.getAccount('account-2')?.email, 'two@example.com');

        // The unified mailbox now shows mail from both accounts.
        final unified = repo.getEmailsInFolder(MailFolder.inbox);
        expect(
          unified.map((e) => e.id),
          containsAll(['mail-1a', 'mail-1b', 'mail-2a']),
        );

        await repo.setActiveAccount('account-1');
        expect(
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          ['mail-1a', 'mail-1b'],
        );
      },
    );

    test(
      'removing one account leaves every other connected account untouched',
      () async {
        final one = _fakeAccount(
          accountId: 'account-1',
          email: 'one@example.com',
          folderId: 'folder-1',
          mailIds: ['mail-1a'],
        );
        await one.authService.tokenStore.save(
          accountId: 'account-1',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        );
        final two = _fakeAccount(
          accountId: 'account-2',
          email: 'two@example.com',
          folderId: 'folder-2',
          mailIds: ['mail-2a'],
        );

        final repo = ApiMailRepository(
          authService: one.authService,
          mailService: one.mailService,
          sessionFactory: () =>
              (authService: two.authService, mailService: two.mailService),
        );
        await repo.restoreSession('one@example.com');
        await repo.loadMoreEmails(MailFolder.inbox);
        await repo.connectAccount(email: 'two@example.com', password: 'pw');
        await repo.loadMoreEmails(MailFolder.inbox);
        expect(repo.accounts.length, 2);

        await repo.removeAccount('account-2');

        expect(repo.accounts.map((a) => a.id), ['account-1']);
        expect(two.mailService.deleteAccountCalled, isTrue);
        expect(
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          ['mail-1a'],
        );
      },
    );

    test(
      'bulk actions route each id to its own account, never crossing wires',
      () async {
        final one = _fakeAccount(
          accountId: 'account-1',
          email: 'one@example.com',
          folderId: 'folder-1',
          mailIds: ['mail-1a'],
        );
        await one.authService.tokenStore.save(
          accountId: 'account-1',
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        );
        final two = _fakeAccount(
          accountId: 'account-2',
          email: 'two@example.com',
          folderId: 'folder-2',
          mailIds: ['mail-2a'],
        );

        final repo = ApiMailRepository(
          authService: one.authService,
          mailService: one.mailService,
          sessionFactory: () =>
              (authService: two.authService, mailService: two.mailService),
        );
        await repo.restoreSession('one@example.com');
        await repo.loadMoreEmails(MailFolder.inbox);
        await repo.connectAccount(email: 'two@example.com', password: 'pw');
        await repo.loadMoreEmails(MailFolder.inbox);

        await repo.markAsRead(['mail-1a', 'mail-2a']);

        expect(one.mailService.bulkActionCalls, ['read:mail-1a']);
        expect(two.mailService.bulkActionCalls, ['read:mail-2a']);
      },
    );
  });
}

({ApiAuthService authService, _RecordingMailService mailService}) _fakeAccount({
  required String accountId,
  required String email,
  required String folderId,
  required List<String> mailIds,
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
      // getAccount/search/getConversations best-effort calls during
      // activation — any harmless empty body keeps them from throwing.
      return http.Response('{}', 200);
    }),
  );
  final authService = ApiAuthService(
    client: client,
    tokenStore: tokenStore,
    deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-$accountId'),
  );
  final mailService = _RecordingMailService(
    client,
    accountId: accountId,
    folderId: folderId,
    mailIds: mailIds,
  );
  return (authService: authService, mailService: mailService);
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService(
    super.client, {
    required this.accountId,
    required this.folderId,
    required this.mailIds,
  });

  final String accountId;
  final String folderId;
  final List<String> mailIds;
  bool deleteAccountCalled = false;
  final List<String> bulkActionCalls = [];

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: folderId,
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
  }) async {
    if (folderId != this.folderId || page != 1) {
      return MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);
    }
    return MailListPage(
      items: [
        for (final id in mailIds)
          Email(
            id: id,
            senderName: 'Sender',
            senderEmail: 'sender@example.com',
            recipients: const ['me@example.com'],
            subject: 'Subject $id',
            bodyText: '',
            timestamp: DateTime.parse('2026-01-01T00:00:00Z'),
            isRead: false,
            accountId: accountId,
          ),
      ],
      page: 1,
      pageSize: 20,
      total: mailIds.length,
    );
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalled = true;
  }

  @override
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    bulkActionCalls.add('$action:${mailIds.join(",")}');
    return mailIds.map((id) => BulkActionResult(mailId: id, success: true)).toList();
  }
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
