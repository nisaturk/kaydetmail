import 'dart:async';
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

import 'support/wire_multipart.dart';

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
              'inReplyToMessageId': '<original@example.test>',
              'replySourceMailId': '00000000-0000-4000-8000-000000000001',
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
      expect(mail.inReplyToId, '00000000-0000-4000-8000-000000000001');
      expect(mail.attachments.single.name, 'rapor.pdf');
      expect(mail.attachments.single.sizeBytes, 48211);
    });

    test(
      'MIME reply header without a GUID source is never sent as a source id',
      () async {
        final service = ApiMailService(
          _client(
            (_) async => http.Response(
              jsonEncode({
                'id': 'draft-id',
                'folderId': 'folder-drafts',
                'inReplyToMessageId': '<original@example.test>',
                'from': [],
                'to': [],
              }),
              200,
            ),
          ),
        );
        final draft = await service.getDraft(
          'draft-id',
          resolveFolder: (_) => MailFolder.drafts,
        );
        expect(draft.inReplyToId, isNull);
      },
    );

    test(
      'updateDraft PUTs multipart parts and returns the new mailId',
      () async {
        late WireMultipart sent;
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
      'editing during sync preserves the latest content and replacement id',
      () async {
        final service = _ControlledDraftMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com'], body: 'First');
        await service.createStarted.future;
        await repo.saveDraft(
          draftId: local.id,
          to: ['a@x.com'],
          body: 'Latest',
        );
        service.createCompleted.complete(
          const DraftResult(created: true, mailId: 'draft-old'),
        );
        await _flushDraftSync();

        expect(service.updatedIds, ['draft-old']);
        expect(service.updatedBodies, ['Latest']);
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.bodyText,
          'Latest',
        );
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.id,
          'draft-new',
        );
      },
    );

    test(
      'deleting the composer local id after sync deletes the server copy',
      () async {
        final service = _RecordingMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com']);
        await _flushDraftSync();
        await repo.deleteDraft(local.id);
        expect(service.deletedDraftIds, ['draft-old']);
        expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      },
    );

    test(
      'deleting during create waits and removes the appended copy',
      () async {
        final service = _ControlledDraftMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com']);
        await service.createStarted.future;
        final deletion = repo.deleteDraft(local.id);
        service.createCompleted.complete(
          const DraftResult(created: true, mailId: 'draft-old'),
        );
        await deletion;
        await _flushDraftSync();
        expect(service.deletedDraftIds, ['draft-old']);
        expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      },
    );

    test(
      'editing during PUT sends the next revision to the replacement',
      () async {
        final service = _SlowUpdateMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com'], body: 'Original');
        await _flushDraftSync();
        await repo.saveDraft(
          draftId: local.id,
          to: ['a@x.com'],
          body: 'First edit',
        );
        await service.updateStarted.future;
        await repo.saveDraft(
          draftId: local.id,
          to: ['a@x.com'],
          body: 'Last edit',
        );
        service.updateCompleted.complete();
        await _flushDraftSync();
        expect(service.updatedIds, ['draft-old', 'draft-new']);
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.id,
          'draft-latest',
        );
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.bodyText,
          'Last edit',
        );
      },
    );

    test(
      'deleting during PUT clears the queued revision permanently',
      () async {
        final service = _SlowUpdateMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com']);
        await _flushDraftSync();
        await repo.saveDraft(draftId: local.id, to: ['a@x.com'], body: 'Edit');
        await service.updateStarted.future;
        final deletion = repo.deleteDraft(local.id);
        service.updateCompleted.complete();
        await deletion;
        await repo.saveDraft(to: ['b@x.com'], body: 'Unrelated');
        await _flushDraftSync();
        expect(service.deletedDraftIds, ['draft-new']);
        expect(service.updatedIds, ['draft-old']);
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.bodyText,
          'Unrelated',
        );
      },
    );

    test(
      'pending reconciliation resumes queued edits using the server id',
      () async {
        final service = _PendingDraftMailService();
        final repo = await _loggedInRepository(service);
        final failures = <Email>[];
        final subscription = repo.draftSyncFailures.listen(failures.add);
        addTearDown(subscription.cancel);
        final local = await repo.saveDraft(to: ['a@x.com'], subject: 'Pending');
        await _flushDraftSync();
        await repo.saveDraft(
          draftId: local.id,
          to: ['a@x.com'],
          subject: 'Pending',
          body: 'Newest revision',
        );
        await _flushDraftSync();
        expect(failures, isEmpty);
        expect(service.updatedIds, isEmpty);
        service.imported = true;
        await repo.refreshEmails(MailFolder.drafts);
        await _flushDraftSync();
        expect(service.updatedIds, ['draft-reconciled']);
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.bodyText,
          'Newest revision',
        );
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).single.id,
          'draft-new',
        );
      },
    );

    test(
      'delete reconciles a pending edited draft without leaving a local ghost',
      () async {
        final service = _PendingDraftMailService();
        final repo = await _loggedInRepository(service);
        final local = await repo.saveDraft(to: ['a@x.com'], subject: 'Pending');
        await _flushDraftSync();
        await repo.saveDraft(
          draftId: local.id,
          to: ['a@x.com'],
          subject: 'Pending',
          body: 'Queued edit',
        );
        await _flushDraftSync();
        service.imported = true;
        await repo.deleteDraft(local.id);
        await _flushDraftSync();
        expect(service.deletedDraftIds, ['draft-reconciled']);
        expect(service.updatedIds, isEmpty);
        expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      },
    );

    test(
      'permanent sync failure preserves content without blocking other drafts',
      () async {
        final service = _FailingDraftMailService();
        final repo = await _loggedInRepository(service);
        final failures = <Email>[];
        final subscription = repo.draftSyncFailures.listen(failures.add);
        addTearDown(subscription.cancel);
        final failed = await repo.saveDraft(
          to: ['a@x.com'],
          subject: 'Failed reply',
          body: 'Keep my reply',
          inReplyToId: 'missing-source',
        );
        await _flushDraftSync();
        await repo.saveDraft(to: ['b@x.com'], subject: 'Healthy draft');
        await _flushDraftSync();

        final drafts = repo.getEmailsInFolder(MailFolder.drafts);
        expect(drafts.any((draft) => draft.id == 'healthy-server-id'), isTrue);
        expect(
          drafts.singleWhere((draft) => draft.id == failed.id).bodyText,
          'Keep my reply',
        );
        expect(service.failedAttempts, 1);
        expect(failures.map((draft) => draft.id), [failed.id]);
        await Future<void>.delayed(const Duration(seconds: 16));
        expect(service.failedAttempts, 1);

        service.sourceAvailable = true;
        await repo.saveDraft(
          draftId: failed.id,
          to: failed.recipients,
          subject: failed.subject,
          body: 'Edited reply',
          inReplyToId: failed.inReplyToId,
        );
        await _flushDraftSync();
        expect(
          repo
              .getEmailsInFolder(MailFolder.drafts)
              .singleWhere((draft) => draft.id == 'recovered-server-id')
              .bodyText,
          'Edited reply',
        );
      },
    );

    test(
      'saveDraft persists locally first, then reconciles with server id',
      () async {
        final mailService = _RecordingMailService();
        final repo = await _loggedInRepository(mailService);

        expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
        final created = await repo.saveDraft(
          to: ['a@x.com'],
          subject: 'Taslak',
        );
        expect(created.id, startsWith('local-draft-'));
        expect(created.senderName, 'person@example.com');
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
          contains(created.id),
        );

        await _flushDraftSync();
        expect(
          repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
          contains('draft-old'),
        );
      },
    );

    test('deleteDraft removes the draft through the service', () async {
      final mailService = _RecordingMailService();
      final repo = await _loggedInRepository(mailService);

      await repo.saveDraft(to: ['a@x.com'], subject: 'Taslak');
      await _flushDraftSync();
      await repo.deleteDraft('draft-old');

      expect(mailService.deletedDraftIds, ['draft-old']);
      expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
    });

    test('deleteDraft hides the row before the server responds', () async {
      final mailService = _SlowDeleteMailService();
      final repo = await _loggedInRepository(mailService);
      await repo.saveDraft(to: ['a@x.com'], subject: 'Taslak');
      await _flushDraftSync();

      final deletion = repo.deleteDraft('draft-old');

      expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(mailService.deletionRequested, isTrue);
      expect(mailService.deleteStarted.isCompleted, isFalse);
      mailService.deleteStarted.complete();
      await deletion;
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

      final created = await repo.saveDraft(to: ['a@x.com'], subject: 'Taslak');
      expect(created.id, startsWith('local-draft-'));
      expect(
        repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
        contains(created.id),
      );
      await _flushDraftSync();

      expect(repo.getEmailsInFolder(MailFolder.sent), isEmpty);
      await repo.sendDraft('draft-old');

      expect(repo.getEmailsInFolder(MailFolder.drafts), isEmpty);
      expect(
        repo.getEmailsInFolder(MailFolder.sent).single.senderName,
        'person@example.com',
      );
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
    accountId: 'account-1',
    accessToken: 'access',
    refreshToken: 'refresh',
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
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async => const DraftResult(created: true, mailId: 'draft-old');

  @override
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
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

class _ControlledDraftMailService extends _RecordingMailService {
  final createStarted = Completer<void>();
  final createCompleted = Completer<DraftResult>();
  final updatedIds = <String>[];
  final updatedBodies = <String>[];

  @override
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) {
    createStarted.complete();
    return createCompleted.future;
  }

  @override
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async {
    updatedIds.add(id);
    updatedBodies.add(bodyText);
    return const DraftResult(created: false, mailId: 'draft-new');
  }
}

class _SlowUpdateMailService extends _RecordingMailService {
  final updateStarted = Completer<void>();
  final updateCompleted = Completer<void>();
  final updatedIds = <String>[];

  @override
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async {
    updatedIds.add(id);
    if (updatedIds.length == 1) {
      updateStarted.complete();
      await updateCompleted.future;
      return const DraftResult(created: false, mailId: 'draft-new');
    }
    if (id != 'draft-new') {
      throw const ApiException(status: 422, code: 'mail_not_draft');
    }
    return const DraftResult(created: false, mailId: 'draft-latest');
  }
}

class _PendingDraftMailService extends _RecordingMailService {
  bool imported = false;
  final updatedIds = <String>[];

  @override
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async => const DraftResult(created: true, mailId: null);

  @override
  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    bool? hasAttachments,
    String? search,
  }) async => MailListPage(
    items: [
      if (imported)
        Email(
          id: 'draft-reconciled',
          senderName: 'person@example.com',
          senderEmail: 'person@example.com',
          recipients: const ['a@x.com'],
          subject: 'Pending',
          bodyText: '',
          timestamp: DateTime.now(),
          folder: MailFolder.drafts,
          accountId: 'account-1',
        ),
    ],
    page: page,
    pageSize: pageSize,
    total: imported ? 1 : 0,
  );

  @override
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async {
    updatedIds.add(id);
    if (id != 'draft-reconciled') {
      throw const ApiException(status: 422, code: 'mail_not_draft');
    }
    return const DraftResult(created: false, mailId: 'draft-new');
  }
}

class _FailingDraftMailService extends _RecordingMailService {
  int failedAttempts = 0;
  bool sourceAvailable = false;

  @override
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    String? identityId,
  }) async {
    if (replySourceMailId != null && !sourceAvailable) {
      failedAttempts++;
      throw const ApiException(status: 404, code: 'mail_not_found');
    }
    return DraftResult(
      created: true,
      mailId: replySourceMailId == null
          ? 'healthy-server-id'
          : 'recovered-server-id',
    );
  }
}

class _SlowDeleteMailService extends _RecordingMailService {
  final Completer<void> deleteStarted = Completer<void>();
  bool deletionRequested = false;

  @override
  Future<void> deleteDraft(String id) async {
    deletionRequested = true;
    await deleteStarted.future;
    await super.deleteDraft(id);
  }
}

/// Reads every no-filename multipart part named [field], in order.
Future<List<String>> _partValues(WireMultipart request, String field) async =>
    request.values(field);

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'account-1',
      httpClient: MockClient(handler),
    );
Future<void> _flushDraftSync() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

ApiClient _multipartClient(
  Future<http.Response> Function(WireMultipart) handler,
) => ApiClient(
  tokenStore: TokenStore(storage: _MemoryTokenStorage()),
  accountId: 'account-1',
  httpClient: MockClient.streaming((request, bodyStream) async {
    final response = await handler(
      await WireMultipart.decode(request, bodyStream),
    );
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
