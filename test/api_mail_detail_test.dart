import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:kaydetmail/utils/html_to_text.dart';

/// Realistic `GET /api/mails/{id}` response straight from the handoff
/// contract (§3): full participants, Turkish body, HTML twin, remote-content
/// flags, one attachment, conversation linkage.
Map<String, dynamic> _realisticDetail() => {
  'id': 'mail-9',
  'folderId': 'folder-inbox',
  'accountId': 'account-1',
  'uid': 8,
  'messageId': '<abc@mail.example.com>',
  'inReplyToMessageId': '<parent@mail.example.com>',
  'references': '<parent@mail.example.com>',
  'subject': 'Yarınki toplantı',
  'from': [
    {
      'id': 'p-1',
      'type': 'From',
      'address': 'mentor@example.com',
      'displayName': 'Mentor',
      'sortOrder': 0,
    },
  ],
  'to': ['ben@kaydet.app'],
  'cc': ['ekip@kaydet.app'],
  'bcc': [],
  'replyTo': [],
  'bodyText': 'Merhaba,\nyarın saat 10:00\'da toplantımız var.',
  'body': {
    'html': '<p>Merhaba,</p><p>yarın saat 10:00\'da toplantımız var.</p>',
    'hasRemoteContent': true,
    'remoteContentHosts': ['track.example.com'],
    'trackingPixelHosts': ['track.example.com'],
  },
  'isRead': false,
  'answered': false,
  'flagged': true,
  'draft': false,
  'deleted': false,
  'recent': false,
  'hasAttachments': true,
  'sentAt': '2026-09-18T07:59:00Z',
  'receivedAt': '2026-09-18T08:00:00Z',
  'internalDate': '2026-09-18T08:00:01Z',
  'headers': [
    {'name': 'X-Mailer', 'value': 'x'},
  ],
  'attachments': [
    {
      'id': 'att-1',
      'fileName': 'notlar.pdf',
      'contentType': 'application/pdf',
      'sizeBytes': 48211,
      'isInline': false,
      'contentId': '',
      'contentDisposition': 'attachment',
    },
  ],
  'conversationId': 'conv-7',
};

/// `http.Response` defaults to latin1 — Turkish bodies need explicit UTF-8.
http.Response _jsonResponse(Map<String, dynamic> json) => http.Response.bytes(
  utf8.encode(jsonEncode(json)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detail mapping', () {
    test('realistic detail JSON maps every visible field', () async {
      final service = ApiMailService(
        _client((_) async => _jsonResponse(_realisticDetail())),
      );

      final email = await service.getMail(
        'mail-9',
        resolveFolder: (_) => MailFolder.inbox,
      );

      expect(email.id, 'mail-9');
      expect(email.bodyText, 'Merhaba,\nyarın saat 10:00\'da toplantımız var.');
      expect(email.senderName, 'Mentor');
      expect(email.senderEmail, 'mentor@example.com');
      expect(email.recipients, ['ben@kaydet.app']);
      expect(email.cc, ['ekip@kaydet.app']);
      expect(email.bcc, isEmpty);
      expect(email.subject, 'Yarınki toplantı');
      expect(email.isRead, isFalse);
      expect(email.isStarred, isTrue);
      expect(email.folder, MailFolder.inbox);
      expect(email.threadId, 'conv-7');
      expect(email.inReplyToId, '<parent@mail.example.com>');
      expect(email.hasRemoteContent, isTrue);
      expect(email.attachments.single.id, 'att-1');
      expect(email.attachments.single.name, 'notlar.pdf');
      expect(email.attachments.single.sizeBytes, 48211);
      expect(email.attachments.single.mimeType, 'application/pdf');
      expect(email.timestamp, DateTime.parse('2026-09-18T08:00:00Z'));
    });

    test('missing optional fields never break the mapping', () async {
      final service = ApiMailService(
        _client(
          (_) async => http.Response(
            jsonEncode({
              'id': 'm-t',
              'folderId': 'f-1',
              'subject': 'S',
              'receivedAt': 'not-a-date',
            }),
            200,
          ),
        ),
      );

      final email = await service.getMail(
        'm-t',
        resolveFolder: (_) => MailFolder.inbox,
      );

      expect(email.bodyText, isEmpty);
      expect(email.senderName, isEmpty);
      expect(email.senderEmail, isEmpty);
      expect(email.recipients, isEmpty);
      expect(email.attachments, isEmpty);
      expect(email.hasRemoteContent, isFalse);
      expect(email.inReplyToId, isNull);
    });

    test('HTML-only message falls back to safe readable text', () async {
      final service = ApiMailService(
        _client(
          (_) async => _jsonResponse({
            'id': 'm-h',
            'folderId': 'f-1',
            'subject': 'S',
            'from': [
              {'address': 'a@x.com', 'displayName': ''},
            ],
            'to': ['b@x.com'],
            'bodyText': '',
            'body': {
              'html':
                  '<html><head><style>.x{color:red}</style></head><body>'
                  '<script>alert(1)</script>'
                  '<p>Merhaba,<br>yarın <b>toplantı</b> &amp; kahve.</p>'
                  '<img src="http://track.example.com/x.png">'
                  '</body></html>',
              'hasRemoteContent': true,
              'remoteContentHosts': ['track.example.com'],
              'trackingPixelHosts': [],
            },
            'receivedAt': '2026-09-18T08:00:00Z',
          }),
        ),
      );

      final email = await service.getMail(
        'm-h',
        resolveFolder: (_) => MailFolder.inbox,
      );

      expect(email.bodyText, contains('Merhaba,'));
      expect(email.bodyText, contains('toplantı & kahve'));
      expect(email.bodyText.contains('<'), isFalse);
      expect(email.bodyText, isNot(contains('alert')));
      expect(email.hasRemoteContent, isTrue);
    });
  });

  group('htmlToPlainText', () {
    test('strips tags, drops scripts, decodes entities', () {
      expect(
        htmlToPlainText('<p>Hi <b>there</b></p><script>x()</script>'),
        'Hi there',
      );
      expect(htmlToPlainText('a&lt;b&gt;&amp;&#65;&#x42;'), 'a<b>&AB');
      expect(htmlToPlainText('<!-- hidden -->visible'), 'visible');
      expect(htmlToPlainText(''), isEmpty);
    });
  });

  group('conversations', () {
    test('getConversation parses and dedupes message ids', () async {
      late Uri uri;
      final service = ApiMailService(
        _client((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({
              'id': 'conv-1',
              'subject': 'T',
              'messages': [
                {'id': 'm-new'},
                {'id': 'm-old'},
                {'id': 'm-new'},
                {'no': 'id'},
              ],
            }),
            200,
          );
        }),
      );

      final conversation = await service.getConversation('conv-1');

      expect(uri.path, '/api/conversations/conv-1');
      expect(conversation.messageIds, ['m-new', 'm-old']);
    });
  });

  group('ApiMailRepository threads', () {
    test('fetchThreadEmails loads full bodies sorted oldest first', () async {
      final repo = await _repoWithService(_ThreadMailService());

      final thread = await repo.fetchThreadEmails('conv-1');

      expect(thread.map((e) => e.id), ['m-old', 'm-new']);
      expect(thread.map((e) => e.bodyText), ['old body', 'new body']);
    });

    test('fetchThreadEmails propagates a conversation-level failure', () async {
      final repo = await _repoWithService(_BrokenConversationService());

      expect(
        () => repo.fetchThreadEmails('conv-1'),
        throwsA(isA<ApiException>()),
      );
    });

    test('getEmail caches the detail without duplicating it', () async {
      final repo = await _repoWithService(_SingleMailService());

      final first = await repo.getEmail('m-1');
      final second = await repo.getEmail('m-1');

      expect(first?.bodyText, 'full body');
      expect(second?.bodyText, 'full body');
      expect(repo.getAllEmails().where((e) => e.id == 'm-1').length, 1);
    });

    test('getEmail maps 404 to null and rethrows other failures', () async {
      final missing = await _repoWithResponses({
        '/api/mails/m-1': http.Response(
          jsonEncode({
            'code': 'mail_not_found',
            'title': 'Not found',
            'status': 404,
          }),
          404,
        ),
      });
      expect(await missing.getEmail('m-1'), isNull);

      final broken = await _repoWithResponses({
        '/api/mails/m-1': http.Response('oops', 500),
      });
      expect(() => broken.getEmail('m-1'), throwsA(isA<ApiException>()));
    });
  });
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  @override
  Future<List<ApiMailFolder>> getFolders() async => const [
    ApiMailFolder(
      id: 'f-in',
      mailAccountId: 'account-1',
      name: 'INBOX',
      type: 'Inbox',
    ),
  ];
}

class _ThreadMailService extends _RecordingMailService {
  @override
  Future<ApiConversation> getConversation(String id) async =>
      const ApiConversation(
        id: 'conv-1',
        subject: 'T',
        messageIds: ['m-new', 'm-old', 'm-new', 'm-bad'],
      );

  @override
  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
  }) async {
    if (id == 'm-bad') {
      throw const ApiException(status: 500, code: 'unexpected_error');
    }
    return Email(
      id: id,
      senderName: 'S',
      senderEmail: 's@x.com',
      recipients: const ['r@x.com'],
      subject: 'T',
      bodyText: id == 'm-old' ? 'old body' : 'new body',
      timestamp: id == 'm-old'
          ? DateTime.utc(2026, 1, 1)
          : DateTime.utc(2026, 1, 2),
      folder: MailFolder.inbox,
      accountId: 'account-1',
      threadId: 'conv-1',
    );
  }
}

class _BrokenConversationService extends _RecordingMailService {
  @override
  Future<ApiConversation> getConversation(String id) async {
    throw const ApiException(status: 503, code: 'sync_queue_full');
  }
}

class _SingleMailService extends _RecordingMailService {
  @override
  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
  }) async => Email(
    id: id,
    senderName: 'S',
    senderEmail: 's@x.com',
    recipients: const ['r@x.com'],
    subject: 'T',
    bodyText: 'full body',
    timestamp: DateTime.utc(2026, 1, 2),
    folder: MailFolder.inbox,
    accountId: 'account-1',
    threadId: 'conv-1',
  );
}

Future<ApiMailRepository> _repoWithService(ApiMailService mailService) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  await tokenStore.save(
    accessToken: 'access',
    refreshToken: 'refresh',
    mailAccountId: 'account-1',
  );
  final authService = ApiAuthService(
    client: ApiClient(
      tokenStore: tokenStore,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
    tokenStore: tokenStore,
    deviceIdentifierProvider: const MemoryDeviceIdentifierProvider('device-1'),
  );
  final repo = ApiMailRepository(
    authService: authService,
    mailService: mailService,
  );
  await repo.restoreSession('person@example.com');
  return repo;
}

Future<ApiMailRepository> _repoWithResponses(
  Map<String, http.Response> responses,
) async {
  SharedPreferences.setMockInitialValues({});
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  await tokenStore.save(
    accessToken: 'access',
    refreshToken: 'refresh',
    mailAccountId: 'account-1',
  );
  http.Response handler(http.Request request) =>
      responses[request.url.path] ?? http.Response('[]', 200);
  final apiClient = ApiClient(
    tokenStore: tokenStore,
    httpClient: MockClient((request) async => handler(request)),
  );
  final repo = ApiMailRepository(
    authService: ApiAuthService(
      client: apiClient,
      tokenStore: tokenStore,
      deviceIdentifierProvider: const MemoryDeviceIdentifierProvider(
        'device-1',
      ),
    ),
    mailService: ApiMailService(apiClient),
  );
  await repo.restoreSession('person@example.com');
  return repo;
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
