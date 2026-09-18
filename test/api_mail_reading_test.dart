import 'dart:convert';

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
      resolveFolder: (id) => id == 'folder-1' ? MailFolder.inbox : MailFolder.archive,
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
      resolveFolder: (id) => id == 'folder-1' ? MailFolder.inbox : MailFolder.archive,
    );

    expect(email.id, 'mail-1');
    expect(email.bodyText, 'Message body');
    expect(email.senderName, 'Sender');
    expect(email.recipients, ['person@example.com']);
    expect(email.isStarred, isTrue);
    expect(email.folder, MailFolder.inbox);
  });
}

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
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
