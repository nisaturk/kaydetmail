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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiMailService drafts', () {
    test('getDraft maps MailDetailResponse with cc/bcc/attachments', () async {
      final service = ApiMailService(
        _client(
          (_) async => http.Response(
            jsonEncode({
              'id': 'd-1',
              'folderId': 'f-1',
              'accountId': 'account-1',
              'subject': 'Taslak',
              'from': [
                {'address': 'me@x.com', 'displayName': 'Ben'},
              ],
              'to': ['a@x.com'],
              'cc': ['c@x.com'],
              'bcc': ['b@x.com'],
              'bodyText': 'gövde',
              'isRead': true,
              'flagged': false,
              'receivedAt': '2026-09-18T08:00:00Z',
              'conversationId': 'conv-1',
              'inReplyToMessageId': 'm-0',
              'attachments': [
                {
                  'id': 'a-1',
                  'fileName': 'rapor.pdf',
                  'contentType': 'application/pdf',
                  'sizeBytes': 48211,
                },
              ],
            }),
            200,
          ),
        ),
      );

      final mail = await service.getDraft(
        'd-1',
        resolveFolder: (_) => MailFolder.drafts,
      );

      expect(mail.id, 'd-1');
      expect(mail.folder, MailFolder.drafts);
      expect(mail.recipients, ['a@x.com']);
      expect(mail.cc, ['c@x.com']);
      expect(mail.bcc, ['b@x.com']);
      expect(mail.threadId, 'conv-1');
      expect(mail.inReplyToId, 'm-0');
      expect(mail.attachments.single.name, 'rapor.pdf');
      expect(mail.attachments.single.sizeBytes, 48211);
    });

    test(
      'updateDraft PUTs multipart parts and returns the new mailId',
      () async {
        late http.MultipartRequest sent;
        final service = ApiMailService(
          _multipartClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({'created': false, 'mailId': 'draft-new'}),
              200,
            );
          }),
        );

        final result = await service.updateDraft(
          'draft-old',
          to: ['a@x.com'],
          cc: ['c@x.com'],
          subject: 'Konu',
          bodyText: 'Gövde',
        );

        expect(sent.method, 'PUT');
        expect(sent.url.path, '/api/drafts/draft-old');
        expect(await _partValues(sent, 'To'), ['a@x.com']);
        expect(await _partValues(sent, 'Cc'), ['c@x.com']);
        expect(sent.fields['subject'], 'Konu');
        expect(result.created, isFalse);
        expect(result.mailId, 'draft-new');
      },
    );

    test('deleteDraft sends DELETE to /api/drafts/{id}', () async {
      late http.Request sent;
      final service = ApiMailService(
        _client((request) async {
          sent = request;
          return http.Response('', 204);
        }),
      );

      await service.deleteDraft('d-1');

      expect(sent.method, 'DELETE');
      expect(sent.url.path, '/api/drafts/d-1');
    });
  });

  group('ApiMailRepository drafts', () {
    test(
      'saveDraft with draftId swaps the old id for the new mailId',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _loggedInRepository(mailService);

        final created = await repo.saveDraft(
          to: ['a@x.com'],
          subject: 'Taslak',
        );
        expect(created.id, 'draft-old');

        final updated = await repo.saveDraft(
          to: ['a@x.com'],
          subject: 'Taslak v2',
          draftId: 'draft-old',
        );

        expect(updated.id, 'draft-new');
        expect(updated.subject, 'Taslak v2');
        final drafts = repo.getEmailsInFolder(MailFolder.drafts);
        expect(drafts.map((e) => e.id), contains('draft-new'));
        expect(drafts.map((e) => e.id), isNot(contains('draft-old')));
        expect(drafts.where((e) => e.subject == 'Taslak v2').length, 1);
      },
    );

    test('deleteDraft removes the draft through the service', () async {
      final mailService = _RecordingMailService();
      final repo = await _loggedInRepository(mailService);

      await repo.saveDraft(to: ['a@x.com'], subject: 'Taslak');
      await repo.deleteDraft('draft-old');

      expect(mailService.deletedDraftIds, ['draft-old']);
      expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
    });
  });

  group('ApiMailService draft send + compose prefill', () {
    test(
      'sendDraft posts bodyless with Idempotency-Key and parses draftRemoved',
      () async {
        late http.Request sent;
        final service = ApiMailService(
          _client((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'sent': true,
                'sentCopySaved': true,
                'draftRemoved': true,
              }),
              200,
            );
          }),
        );

        final res = await service.sendDraft('d-1', idempotencyKey: 'k-1');

        expect(sent.method, 'POST');
        expect(sent.url.path, '/api/drafts/d-1/send');
        expect(sent.headers['Idempotency-Key'], 'k-1');
        expect(res.sent, isTrue);
        expect(res.draftRemoved, isTrue);
      },
    );

    test(
      'compose prefill returns suggested subject and reply chain ids',
      () async {
        final service = ApiMailService(
          _client(
            (_) async => http.Response(
              jsonEncode({
                'sourceMailId': 'm-1',
                'to': [
                  {'address': 'a@x.com', 'displayName': ''},
                ],
                'cc': [],
                'suggestedSubject': 'Re: T',
                'inReplyToMessageId': 'mid',
                'references': 'mid',
                'originalFrom': 'a@x.com',
                'originalDate': '2026-09-18T08:00:00Z',
                'originalSubject': 'T',
                'attachments': [],
              }),
              200,
            ),
          ),
        );

        final p = await service.getComposePrefill('m-1', 'reply');

        expect(p.suggestedSubject, 'Re: T');
        expect(p.inReplyToMessageId, 'mid');
        expect(p.to, ['a@x.com']);
      },
    );

    test('compose prefill rejects unknown kind', () async {
      final service = ApiMailService(
        _client((_) async => http.Response('{}', 200)),
      );

      expect(
        () => service.getComposePrefill('m-1', 'bogus'),
        throwsArgumentError,
      );
    });
  });

  group('ApiMailRepository draft send', () {
    test('sendDraft drops the draft and echoes to Sent', () async {
      final mailService = _RecordingMailService();
      final repo = await _loggedInRepository(mailService);

      await repo.saveDraft(to: ['a@x.com'], subject: 'Taslak');
      expect(
        repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
        contains('draft-old'),
      );

      await repo.sendDraft('draft-old');

      expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      expect(repo.getEmailsInFolder(MailFolder.sent), isNotEmpty);
    });
  });

  group('draft error messages', () {
    test('branch on code, not title', () {
      expect(
        const ApiException(status: 422, code: 'mail_not_draft').userMessage,
        'Bu taslak artık geçerli değil.',
      );
      expect(
        const ApiException(status: 409, code: 'delivery_unknown').userMessage,
        contains('Gönderilenler'),
      );
    });
  });
}

Future<ApiMailRepository> _loggedInRepository(
  _RecordingMailService mailService,
) async {
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

class _RecordingMailService extends ApiMailService {
  _RecordingMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<String> deletedDraftIds = [];

  @override
  Future<List<ApiMailFolder>> getFolders() async => const [
    ApiMailFolder(
      id: 'f-drafts',
      mailAccountId: 'account-1',
      name: 'Drafts',
      type: 'Drafts',
    ),
  ];

  @override
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async => const DraftResult(created: true, mailId: 'draft-old');

  @override
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async => const DraftResult(created: false, mailId: 'draft-new');

  @override
  Future<void> deleteDraft(String id) async {
    deletedDraftIds.add(id);
  }

  @override
  Future<SendDraftResult> sendDraft(
    String id, {
    required String idempotencyKey,
  }) async => const SendDraftResult(
    sent: true,
    sentCopySaved: true,
    draftRemoved: true,
  );
}

/// Reads every no-filename multipart part named [field], in order.
Future<List<String>> _partValues(
  http.MultipartRequest request,
  String field,
) async {
  final values = <String>[];
  for (final file in request.files) {
    if (file.field != field || file.filename != null) continue;
    values.add(utf8.decode(await file.finalize().toBytes()));
  }
  return values;
}

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      httpClient: MockClient(handler),
    );

ApiClient _multipartClient(
  Future<http.Response> Function(http.MultipartRequest) handler,
) => ApiClient(
  tokenStore: TokenStore(storage: _MemoryTokenStorage()),
  httpClient: MockClient.streaming((request, bodyStream) async {
    final response = await handler(request as http.MultipartRequest);
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
