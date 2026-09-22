import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  test('GET account parses backend account summary', () async {
    final service = ApiMailService(
      _client(
        (request) async => http.Response(
          jsonEncode({
            'id': 'account-1',
            'emailAddress': 'person@example.com',
            'displayName': 'Personal',
            'provider': 'Google',
            'status': 'Active',
          }),
          200,
        ),
      ),
    );

    final account = await service.getAccount();

    expect(account.id, 'account-1');
    expect(account.email, 'person@example.com');
    expect(account.displayName, 'Personal');
    expect(account.provider, AccountProvider.google);
  });

  test('GET folders parses folder array', () async {
    final service = ApiMailService(
      _client(
        (request) async => http.Response(
          jsonEncode([
            {
              'id': 'folder-1',
              'mailAccountId': 'account-1',
              'name': 'INBOX',
              'fullName': 'INBOX',
              'folderType': 'Inbox',
              'uidValidity': 1,
              'isSyncEnabled': true,
              'isAvailable': true,
            },
          ]),
          200,
        ),
      ),
    );

    final folders = await service.getFolders();

    expect(folders.single.id, 'folder-1');
    expect(folders.single.type, 'Inbox');
  });

  test('GET mails maps list item and sends folder pagination query', () async {
    late Uri uri;
    final service = ApiMailService(
      _client((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'mail-1',
                'folderId': 'folder-1',
                'subject': 'Hello',
                'fromAddress': 'sender@example.com',
                'fromDisplayName': 'Sender',
                'toAddress': 'person@example.com',
                'isRead': true,
                'hasAttachments': false,
                'receivedAt': '2026-09-17T01:56:58Z',
              },
            ],
            'page': 1,
            'pageSize': 20,
            'total': 1,
          }),
          200,
        );
      }),
    );

    final page = await service.getMails(
      folderId: 'folder-1',
      page: 1,
      pageSize: 20,
      resolveFolder: (id) =>
          id == 'folder-1' ? MailFolder.inbox : MailFolder.archive,
    );

    expect(uri.path, '/api/mails');
    expect(uri.queryParameters, {
      'folderId': 'folder-1',
      'page': '1',
      'pageSize': '20',
    });
    expect(page.items.single.id, 'mail-1');
    expect(page.items.single.senderEmail, 'sender@example.com');
    expect(page.items.single.isRead, isTrue);
    expect(page.items.single.folder, MailFolder.inbox);
    expect(page.items.single.hasAttachments, isFalse);
  });

  test('GET mails surfaces hasAttachments without needing full attachment metadata', () async {
    // The list endpoint never sends per-attachment details (only the
    // detail endpoint does) — just this boolean. Dropping it here is what
    // made the paperclip icon disappear for mail the user hadn't opened
    // yet, and reappear only after a detail fetch merged real attachments
    // in — see ApiMailRepository._refreshEmailsFor.
    final service = ApiMailService(
      _client(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'mail-2',
                'folderId': 'folder-1',
                'subject': 'Has an attachment',
                'fromAddress': 'sender@example.com',
                'fromDisplayName': 'Sender',
                'toAddress': 'person@example.com',
                'isRead': false,
                'hasAttachments': true,
                'receivedAt': '2026-09-17T01:56:58Z',
              },
            ],
            'page': 1,
            'pageSize': 20,
            'total': 1,
          }),
          200,
        ),
      ),
    );

    final page = await service.getMails(
      folderId: 'folder-1',
      page: 1,
      pageSize: 20,
      resolveFolder: (_) => MailFolder.inbox,
    );

    expect(page.items.single.hasAttachments, isTrue);
    expect(page.items.single.attachments, isEmpty);
  });

  test('GET mail detail maps body and participants', () async {
    final service = ApiMailService(
      _client(
        (request) async => http.Response(
          jsonEncode({
            'id': 'mail-1',
            'folderId': 'folder-1',
            'accountId': 'account-1',
            'subject': 'Hello',
            'from': [
              {'address': 'sender@example.com', 'displayName': 'Sender'},
            ],
            'to': [
              {'address': 'person@example.com', 'displayName': 'Person'},
            ],
            'bodyText': 'Message body',
            'isRead': false,
            'flagged': true,
            'hasAttachments': false,
            'receivedAt': '2026-09-17T01:56:58Z',
          }),
          200,
        ),
      ),
    );

    final email = await service.getMail(
      'mail-1',
      resolveFolder: (id) =>
          id == 'folder-1' ? MailFolder.inbox : MailFolder.archive,
    );

    expect(email.id, 'mail-1');
    expect(email.bodyText, 'Message body');
    expect(email.senderName, 'Sender');
    expect(email.recipients, ['person@example.com']);
    expect(email.isStarred, isTrue);
    expect(email.folder, MailFolder.inbox);
  });

  test('GET mails forwards isRead/hasAttachments/search filters', () async {
    late Uri uri;
    final service = ApiMailService(
      _client((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({'items': [], 'page': 1, 'pageSize': 20, 'total': 0}),
          200,
        );
      }),
    );

    await service.getMails(
      folderId: 'folder-1',
      resolveFolder: (_) => MailFolder.inbox,
      isRead: false,
      hasAttachments: true,
      search: 'fatura',
    );

    expect(uri.queryParameters['isRead'], 'false');
    expect(uri.queryParameters['hasAttachments'], 'true');
    expect(uri.queryParameters['search'], 'fatura');
  });

  test(
    'search sends full filter set with correct hasAttachment name',
    () async {
      late Uri uri;
      final service = ApiMailService(
        _client((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({'items': [], 'page': 1, 'pageSize': 20, 'total': 0}),
            200,
          );
        }),
      );

      await service.search(
        query: 'fatura',
        resolveFolder: (_) => MailFolder.inbox,
        from: 'a@x.com',
        isRead: false,
        flagged: true,
        hasAttachment: true,
      );

      expect(uri.path, '/api/search');
      expect(uri.queryParameters['q'], 'fatura');
      // /search uses the singular name — /mails uses hasAttachments (plural).
      expect(uri.queryParameters['hasAttachment'], 'true');
      expect(uri.queryParameters['flagged'], 'true');
      expect(uri.queryParameters['from'], 'a@x.com');
      expect(uri.queryParameters['isRead'], 'false');
    },
  );

  test('search serializes dates as UTC ISO-8601 and drops nulls', () async {
    late Uri uri;
    final service = ApiMailService(
      _client((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({'items': [], 'page': 1, 'pageSize': 20, 'total': 0}),
          200,
        );
      }),
    );

    await service.search(
      query: 'x',
      resolveFolder: (_) => MailFolder.inbox,
      fromDate: DateTime.utc(2026, 9, 1, 12),
      toDate: DateTime.utc(2026, 9, 18, 12),
    );

    expect(uri.queryParameters['fromDate'], '2026-09-01T12:00:00.000Z');
    expect(uri.queryParameters['toDate'], '2026-09-18T12:00:00.000Z');
    expect(uri.queryParameters.containsKey('from'), isFalse);
    expect(uri.queryParameters.containsKey('flagged'), isFalse);
  });

  test('getConversations parses messageCount/unreadCount envelope', () async {
    late Uri uri;
    final service = ApiMailService(
      _client((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'c-1',
                'subject': 'T',
                'participants': ['a@x.com'],
                'messageCount': 3,
                'unreadCount': 1,
                'hasAttachments': false,
                'startedAt': '2026-09-18T08:00:00Z',
                'lastMessageAt': '2026-09-18T09:00:00Z',
              },
            ],
            'page': 1,
            'pageSize': 50,
            'total': 1,
          }),
          200,
        );
      }),
    );

    final page = await service.getConversations();

    expect(uri.path, '/api/conversations');
    expect(page.items.single.messageCount, 3);
    expect(page.items.single.unreadCount, 1);
    expect(page.items.single.subject, 'T');
    expect(page.total, 1);
  });

  test('downloadAttachment streams raw bytes with encoded ids', () async {
    late String path;
    final service = ApiMailService(
      ApiClient(
        tokenStore: TokenStore(storage: _MemoryTokenStorage()),
        accountId: 'account-1',
        httpClient: MockClient((request) async {
          path = request.url.path;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      ),
    );

    final bytes = await service.downloadAttachment('m-1', 'a-1');

    expect(path, '/api/mails/m-1/attachments/a-1');
    expect(bytes, Uint8List.fromList([1, 2, 3]));
  });
}

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient(handler),
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
