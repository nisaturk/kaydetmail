import 'dart:convert';

import 'package:flutter/material.dart';
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
        expect(repo.hasMoreEmails(MailFolder.inbox), isFalse);

        await repo.setActiveAccount('account-1');
        expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
          'mail-1a',
          'mail-1b',
        ]);
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
        expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
          'mail-1a',
        ]);
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
    test(
      'global search ignores active scope and labels stay account-local',
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
        await repo.setActiveAccount('account-1');

        expect(repo.searchEmails(query: 'mail-2a').map((email) => email.id), [
          'mail-2a',
        ]);
        expect(repo.getScopedEmails().map((email) => email.id), ['mail-1a']);
        expect(
          (await repo.searchEmailsOnServer(query: 'mail'))
              .map((email) => email.id),
          containsAll(['mail-1a', 'mail-2a']),
        );

        final label = await repo.createLabel(
          name: 'Hesap 1',
          color: const Color(0xFF000000),
        );
        await repo.addLabelsToEmails(['mail-1a', 'mail-2a'], [label.id]);
        final byId = {for (final email in repo.getAllEmails()) email.id: email};
        expect(byId['mail-1a']!.labelIds, contains(label.id));
        expect(byId['mail-2a']!.labelIds, isNot(contains(label.id)));
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
    deviceIdentifierProvider: MemoryDeviceIdentifierProvider(
      'device-$accountId',
    ),
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
  final List<Map<String, dynamic>> labelDefs = [];
  final Map<String, List<String>> labelAssignments = {};
  int _labelSeq = 0;

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
      return MailListPage(
        items: const [],
        page: page,
        pageSize: pageSize,
        total: 0,
      );
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
  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    int page = 1,
    int pageSize = 20,
  }) async => [
    for (final id in mailIds)
      if (id.contains(query))
        Email(
          id: id,
          senderName: 'Sender',
          senderEmail: 'sender@example.com',
          recipients: const ['me@example.com'],
          subject: 'Subject $id',
          bodyText: '',
          timestamp: DateTime.parse('2026-01-01T00:00:00Z'),
          isRead: false,
          folder: MailFolder.inbox,
          accountId: accountId,
        ),
  ];

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
    return mailIds
        .map((id) => BulkActionResult(mailId: id, success: true))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getLabels() async => List.from(labelDefs);

  @override
  Future<Map<String, dynamic>> createLabel(String name, int color) async {
    final created = {
      'id': 'label-$accountId-${_labelSeq++}',
      'name': name,
      'color': color,
    };
    labelDefs.add(created);
    return created;
  }

  @override
  Future<Map<String, dynamic>> updateLabel(
    String id,
    String name,
    int color,
  ) async {
    final index = labelDefs.indexWhere((d) => d['id'] == id);
    final updated = {'id': id, 'name': name, 'color': color};
    if (index >= 0) labelDefs[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteLabel(String id) async {
    labelDefs.removeWhere((d) => d['id'] == id);
    for (final key in labelAssignments.keys.toList()) {
      labelAssignments[key]!.remove(id);
    }
  }

  @override
  Future<Map<String, List<String>>> getLabelAssignments() async =>
      Map.from(labelAssignments);

  @override
  Future<void> assignLabels(List<String> mailIds, List<String> labelIds) async {
    for (final id in mailIds) {
      final cur = labelAssignments.putIfAbsent(id, () => []);
      for (final labelId in labelIds) {
        if (!cur.contains(labelId)) cur.add(labelId);
      }
    }
  }

  @override
  Future<void> unassignLabels(
    List<String> mailIds,
    List<String> labelIds,
  ) async {
    for (final id in mailIds) {
      labelAssignments[id]?.removeWhere(labelIds.contains);
    }
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
