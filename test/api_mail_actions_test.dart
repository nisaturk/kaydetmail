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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiMailService actions', () {
    test(
      'mailAction sends a bodyless POST to /api/mails/{id}/{action}',
      () async {
        late http.Request sent;
        final service = ApiMailService(
          _client((request) async {
            sent = request;
            return http.Response('', 204);
          }),
        );

        await service.mailAction('mail-1', 'star');

        expect(sent.url.path, '/api/mails/mail-1/star');
        expect(sent.method, 'POST');
        expect(sent.body, isEmpty);
      },
    );

    test('moveMail POSTs the target folderId', () async {
      late Map<String, dynamic> body;
      final service = ApiMailService(
        _client((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204);
        }),
      );

      await service.moveMail('mail-1', 'folder-9');

      expect(body, {'folderId': 'folder-9'});
    });

    test(
      'bulkAction sends mailIds/folderId and parses per-item results',
      () async {
        late String path;
        late Map<String, dynamic> body;
        final service = ApiMailService(
          _client((request) async {
            path = request.url.path;
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'results': [
                  {'mailId': 'mail-1', 'success': true, 'code': null},
                  {
                    'mailId': 'mail-2',
                    'success': false,
                    'code': 'mail_not_found',
                  },
                ],
              }),
              200,
            );
          }),
        );

        final results = await service.bulkAction('trash', ['mail-1', 'mail-2']);

        expect(path, '/api/mails/bulk/trash');
        expect(body, {
          'mailIds': ['mail-1', 'mail-2'],
          'folderId': null,
        });
        expect(results[0].mailId, 'mail-1');
        expect(results[0].success, isTrue);
        expect(results[1].success, isFalse);
        expect(results[1].code, 'mail_not_found');
      },
    );
  });

  group('ApiMailRepository actions', () {
    test('markAsRead rolls back only the ids the server rejected', () async {
      final mailService = _RecordingMailService(
        folders: [_folder('folder-inbox', 'Inbox')],
        pagesByFolderId: {
          'folder-inbox': _page([
            _mailJson('mail-1', 'folder-inbox'),
            _mailJson('mail-2', 'folder-inbox'),
          ]),
        },
      );
      mailService.bulkResultsOverride = (action, ids) => ids
          .map((id) => BulkActionResult(mailId: id, success: id == 'mail-1'))
          .toList();
      final repo = await _repositoryWithLoadedInbox(mailService);

      await expectLater(
        repo.markAsRead(['mail-1', 'mail-2']),
        throwsA(isA<ApiException>()),
      );

      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      expect(inbox.firstWhere((e) => e.id == 'mail-1').isRead, isTrue);
      expect(inbox.firstWhere((e) => e.id == 'mail-2').isRead, isFalse);
      expect(mailService.bulkActionCalls, ['read:mail-1,mail-2:null']);
    });

    test('partial move rollback preserves the original cache order', () async {
      final mailService = _RecordingMailService(
        folders: [
          _folder('folder-inbox', 'Inbox'),
          _folder('folder-trash', 'Trash'),
        ],
        pagesByFolderId: {
          'folder-inbox': _page([
            _mailJson('mail-1', 'folder-inbox'),
            _mailJson('mail-2', 'folder-inbox'),
            _mailJson('mail-3', 'folder-inbox'),
          ]),
        },
      );
      mailService.bulkResultsOverride = (action, ids) => ids
          .map((id) => BulkActionResult(mailId: id, success: id == 'mail-1'))
          .toList();
      final repo = await _repositoryWithLoadedInbox(mailService);

      await expectLater(
        repo.moveToTrash(['mail-3', 'mail-1', 'mail-2']),
        throwsA(isA<ApiException>()),
      );

      expect(
        repo.getEmailsInFolder(MailFolder.inbox).map((email) => email.id),
        ['mail-2', 'mail-3'],
      );
    });

    test('moveToTrash moves the cached mail into the Trash bucket', () async {
      final mailService = _RecordingMailService(
        folders: [
          _folder('folder-inbox', 'Inbox'),
          _folder('folder-trash', 'Trash'),
        ],
        pagesByFolderId: {
          'folder-inbox': _page([_mailJson('mail-1', 'folder-inbox')]),
        },
      );
      final repo = await _repositoryWithLoadedInbox(mailService);

      await repo.moveToTrash(['mail-1']);

      expect(repo.getEmailsInFolder(MailFolder.inbox), isEmpty);
      expect(repo.getEmailsInFolder(MailFolder.trash).single.id, 'mail-1');
      expect(
        repo.getEmailsInFolder(MailFolder.trash).single.folder,
        MailFolder.trash,
      );
    });
    test(
      'moveToTrash updates the cache before the server request completes',
      () async {
        final mailService = _RecordingMailService(
          folders: [
            _folder('folder-inbox', 'Inbox'),
            _folder('folder-trash', 'Trash'),
          ],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1', 'folder-inbox')]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);
        final response = Completer<List<BulkActionResult>>();
        mailService.bulkActionCompleter = response;

        final operation = repo.moveToTrash(['mail-1']);

        expect(repo.getEmailsInFolder(MailFolder.inbox), isEmpty);
        expect(repo.getEmailsInFolder(MailFolder.trash).single.id, 'mail-1');
        response.complete([BulkActionResult(mailId: 'mail-1', success: true)]);
        await operation;
      },
    );

    test(
      'moveToFolder archives a live mail via the bulk archive action',
      () async {
        final mailService = _RecordingMailService(
          folders: [
            _folder('folder-inbox', 'Inbox'),
            _folder('folder-archive', 'Archive'),
          ],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1', 'folder-inbox')]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        await repo.moveToFolder(['mail-1'], MailFolder.archive);

        expect(mailService.bulkActionCalls, ['archive:mail-1:null']);
        expect(repo.getEmailsInFolder(MailFolder.archive).single.id, 'mail-1');
      },
    );

    test(
      'moveToFolder restores trashed mail via bulk restore and files each '
      'mail where the server put it back, not in the requested folder',
      () async {
        final mailService =
            _RecordingMailService(
                folders: [
                  _folder('folder-inbox', 'Inbox'),
                  _folder('folder-drafts', 'Drafts'),
                  _folder('folder-trash', 'Trash'),
                ],
                pagesByFolderId: {
                  'folder-trash': _page([
                    _mailJson('mail-1', 'folder-trash'),
                    _mailJson('draft-1', 'folder-trash'),
                  ]),
                },
              )
              ..folderAfterRestore.addAll({
                'mail-1': 'folder-inbox',
                'draft-1': 'folder-drafts',
              });
        final repo = await _repositoryWithLoadedFolder(
          mailService,
          MailFolder.trash,
        );

        await repo.moveToFolder(['mail-1', 'draft-1'], MailFolder.inbox);

        expect(mailService.singleActionCalls, isEmpty);
        expect(mailService.bulkActionCalls.single, startsWith('restore'));
        expect(repo.getEmailsInFolder(MailFolder.trash), isEmpty);
        expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
          'mail-1',
        ]);
        expect(repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id), [
          'draft-1',
        ]);
      },
    );

    test('refresh drops cached mail inside page 1\'s window that the server no '
        'longer lists, but keeps older mail paged in earlier', () async {
      Map<String, dynamic> mail(String id, String day) =>
          _mailJson(id, 'folder-inbox', receivedAt: '2026-09-${day}T08:00:00Z');
      final mailService = _RecordingMailService(
        folders: [_folder('folder-inbox', 'Inbox')],
        pagesByFolderId: {
          'folder-inbox': _page([
            mail('new', '20'),
            mail('gone', '18'),
            mail('old', '10'),
          ]),
        },
      );
      final repo = await _repositoryWithLoadedInbox(mailService);

      mailService.pagesByFolderId['folder-inbox'] = MailListPage(
        items: [
          mail('new', '20'),
          mail('mid', '15'),
        ].map(_mapMailForTest).toList(),
        page: 1,
        pageSize: 2,
        total: 3,
      );
      await repo.refreshEmails(MailFolder.inbox);

      expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
        'new',
        'mid',
        'old',
      ]);
    });

    test('deletePermanently removes only the mails the server expunged and '
        'reports the rest', () async {
      final mailService =
          _RecordingMailService(
              folders: [
                _folder('folder-inbox', 'Inbox'),
                _folder('folder-trash', 'Trash'),
              ],
              pagesByFolderId: {
                'folder-trash': _page([
                  _mailJson('mail-1', 'folder-trash'),
                  _mailJson('mail-2', 'folder-trash'),
                ]),
              },
            )
            ..bulkResultsOverride = (action, ids) => [
              for (final id in ids)
                BulkActionResult(
                  mailId: id,
                  success: id == 'mail-1',
                  code: id == 'mail-1' ? null : 'mail_delete_failed',
                ),
            ];
      final repo = await _repositoryWithLoadedFolder(
        mailService,
        MailFolder.trash,
      );

      await expectLater(
        repo.deletePermanently(['mail-1', 'mail-2']),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'mail_delete_failed',
          ),
        ),
      );

      expect(mailService.bulkActionCalls.single, startsWith('delete:'));
      expect(repo.getEmailsInFolder(MailFolder.trash).map((e) => e.id), [
        'mail-2',
      ]);
    });

    test(
      'setStarred uses one bulk star request and updates the cache',
      () async {
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([
              _mailJson('mail-1', 'folder-inbox'),
              _mailJson('mail-2', 'folder-inbox'),
            ]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        await repo.setStarred(['mail-1', 'mail-2'], true);

        expect(mailService.singleActionCalls, isEmpty);
        expect(mailService.bulkActionCalls.single, startsWith('star'));
        final inbox = repo.getEmailsInFolder(MailFolder.inbox);
        expect(inbox.every((e) => e.isStarred), isTrue);
      },
    );

    test('all mail view aggregates every loaded real folder', () async {
      final mailService = _RecordingMailService(
        folders: [
          _folder('folder-inbox', 'Inbox'),
          _folder('folder-sent', 'Sent'),
          _folder('folder-drafts', 'Drafts'),
          _folder('folder-spam', 'Spam'),
          _folder('folder-trash', 'Trash'),
          _folder('folder-archive', 'Archive'),
        ],
        pagesByFolderId: {
          'folder-inbox': _page([_mailJson('inbox-mail', 'folder-inbox')]),
          'folder-sent': _page([_mailJson('sent-mail', 'folder-sent')]),
          'folder-drafts': _page([_mailJson('draft-mail', 'folder-drafts')]),
          'folder-spam': _page([_mailJson('spam-mail', 'folder-spam')]),
          'folder-trash': _page([_mailJson('trash-mail', 'folder-trash')]),
          'folder-archive': _page([
            _mailJson('archive-mail', 'folder-archive'),
          ]),
        },
      );
      final repo = await _repositoryWithLoadedInbox(mailService);

      mailService.fetchedFolderIds.clear();
      await repo.refreshEmails(MailFolder.all);
      await repo.syncFolder(MailFolder.all);
      expect(mailService.syncedFolderIds.toSet(), {
        'folder-inbox',
        'folder-sent',
        'folder-drafts',
        'folder-spam',
        'folder-trash',
        'folder-archive',
      });

      expect(mailService.fetchedFolderIds.toSet(), {
        'folder-inbox',
        'folder-sent',
        'folder-drafts',
        'folder-spam',
        'folder-trash',
        'folder-archive',
      });
      expect(
        repo.getEmailsInFolder(MailFolder.all).map((mail) => mail.id).toSet(),
        {
          'inbox-mail',
          'sent-mail',
          'draft-mail',
          'spam-mail',
          'trash-mail',
          'archive-mail',
        },
      );
    });

    test('syncFolder resolves the folder id; unknown folders throw', () async {
      final mailService = _RecordingMailService(
        folders: [_folder('folder-inbox', 'Inbox')],
        pagesByFolderId: {
          'folder-inbox': _page([_mailJson('mail-1', 'folder-inbox')]),
        },
      );
      final repo = await _repositoryWithLoadedInbox(mailService);

      await repo.syncFolder(MailFolder.inbox);
      expect(mailService.syncedFolderIds, ['folder-inbox']);

      expect(() => repo.syncFolder(MailFolder.sent), throwsArgumentError);
    });
  });
  group('ApiMailService copy + folder sync', () {
    test('copyMail POSTs the target folderId', () async {
      late String path;
      late Map<String, dynamic> body;
      final service = ApiMailService(
        _client((request) async {
          path = request.url.path;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 204);
        }),
      );

      await service.copyMail('m-1', 'f-9');

      expect(path, '/api/mails/m-1/copy');
      expect(body, {'folderId': 'f-9'});
    });

    test('refreshFolders returns the reported folder count', () async {
      final service = ApiMailService(
        _client((_) async => http.Response(jsonEncode({'folders': 7}), 202)),
      );

      expect(await service.refreshFolders(), 7);
    });

    test('syncFolderId waits for job completion before returning', () async {
      final requests = <String>[];
      var polls = 0;
      final service = ApiMailService(
        _client((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'jobId': 'job-1',
                'status': 'queued',
                'errorCode': null,
              }),
              202,
            );
          }
          return http.Response(
            jsonEncode({
              'jobId': 'job-1',
              'status': ++polls == 1 ? 'running' : 'succeeded',
              'errorCode': null,
            }),
            200,
          );
        }),
        syncPollInterval: Duration.zero,
      );

      await service.syncFolderId('f-1');
      expect(requests, [
        'POST /api/folders/f-1/sync',
        'GET /api/folders/sync-jobs/job-1',
        'GET /api/folders/sync-jobs/job-1',
      ]);
    });

    test('failed sync does not report success', () async {
      final service = ApiMailService(
        _client(
          (request) async => request.method == 'POST'
              ? http.Response(jsonEncode({'jobId': 'job-1'}), 202)
              : http.Response(
                  jsonEncode({
                    'jobId': 'job-1',
                    'status': 'failed',
                    'errorCode': 'mail_authentication_failed',
                  }),
                  200,
                ),
        ),
      );

      await expectLater(
        service.syncFolderId('f-1'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'mail_authentication_failed',
          ),
        ),
      );
    });

    test(
      'lost job returns 404 rather than claiming cached data is fresh',
      () async {
        final service = ApiMailService(
          _client(
            (request) async => request.method == 'POST'
                ? http.Response(jsonEncode({'jobId': 'job-1'}), 202)
                : http.Response(
                    jsonEncode({'code': 'sync_job_not_found'}),
                    404,
                  ),
          ),
        );

        await expectLater(
          service.syncFolderId('f-1'),
          throwsA(
            isA<ApiException>().having((error) => error.status, 'status', 404),
          ),
        );
      },
    );
  });
}

Future<ApiMailRepository> _repositoryWithLoadedInbox(
  _RecordingMailService mailService,
) => _repositoryWithLoadedFolder(mailService, MailFolder.inbox);

Future<ApiMailRepository> _repositoryWithLoadedFolder(
  _RecordingMailService mailService,
  MailFolder folder,
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
  await repo.loadMoreEmails(folder);
  return repo;
}

Map<String, dynamic> _folder(String id, String type) => {
  'id': id,
  'mailAccountId': 'account-1',
  'name': type,
  'folderType': type,
};

Map<String, dynamic> _mailJson(
  String id,
  String folderId, {
  String receivedAt = '2026-09-17T01:56:58Z',
}) => {
  'id': id,
  'folderId': folderId,
  'subject': 'Subject $id',
  'fromAddress': 'sender@example.com',
  'fromDisplayName': 'Sender',
  'toAddress': 'person@example.com',
  'isRead': false,
  'hasAttachments': false,
  'receivedAt': receivedAt,
};

MailListPage _page(List<Map<String, dynamic>> items) => MailListPage(
  items: items.map((item) => _mapMailForTest(item)).toList(),
  page: 1,
  pageSize: 20,
  total: items.length,
);

/// Mirrors [ApiMailService]'s private mapping so fixtures stay in the same
/// shape the real mapper would produce (folder resolved from `folderId`).
Email _mapMailForTest(Map<String, dynamic> item) {
  const typeByFolderId = {
    'folder-inbox': MailFolder.inbox,
    'folder-trash': MailFolder.trash,
    'folder-archive': MailFolder.archive,
  };
  return Email(
    id: item['id'] as String,
    senderName: item['fromDisplayName'] as String,
    senderEmail: item['fromAddress'] as String,
    recipients: [item['toAddress'] as String],
    subject: item['subject'] as String,
    bodyText: '',
    timestamp: DateTime.parse(item['receivedAt'] as String),
    isRead: item['isRead'] as bool,
    folder: typeByFolderId[item['folderId']] ?? MailFolder.inbox,
  );
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService({required this.folders, required this.pagesByFolderId})
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<Map<String, dynamic>> folders;
  final Map<String, MailListPage> pagesByFolderId;
  final List<String> fetchedFolderIds = [];
  final List<String> bulkActionCalls = [];
  final List<String> singleActionCalls = [];
  final List<String> syncedFolderIds = [];
  List<BulkActionResult> Function(String action, List<String> ids)?
  bulkResultsOverride;
  Completer<List<BulkActionResult>>? bulkActionCompleter;

  /// Server folder id each mail's detail reports after a `restore`.
  final Map<String, String> folderAfterRestore = {};

  @override
  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
    bool allowRemoteImages = false,
  }) async => Email(
    id: id,
    senderName: 'Sender',
    senderEmail: 'sender@example.com',
    recipients: const ['person@example.com'],
    subject: 'Subject $id',
    bodyText: '',
    timestamp: DateTime.parse('2026-09-17T01:56:58Z'),
    folder: resolveFolder(folderAfterRestore[id]!),
  );

  @override
  Future<List<ApiMailFolder>> getFolders() async => folders
      .map(
        (f) => ApiMailFolder(
          id: f['id'] as String,
          mailAccountId: f['mailAccountId'] as String,
          name: f['name'] as String,
          type: f['folderType'] as String,
        ),
      )
      .toList();

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
    fetchedFolderIds.add(folderId);
    return pagesByFolderId[folderId] ??
        MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);
  }

  @override
  Future<void> mailAction(String id, String action) async {
    singleActionCalls.add('$id:$action');
  }

  @override
  Future<void> moveMail(String id, String folderId) async {
    singleActionCalls.add('$id:move:$folderId');
  }

  @override
  Future<void> copyMail(String id, String folderId) async {
    singleActionCalls.add('$id:copy:$folderId');
  }

  @override
  Future<int> refreshFolders() async => folders.length;

  @override
  Future<void> syncFolderId(String folderId) async {
    syncedFolderIds.add(folderId);
  }

  @override
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    bulkActionCalls.add('$action:${mailIds.join(",")}:$folderId');
    final completer = bulkActionCompleter;
    if (completer != null) return completer.future;
    final override = bulkResultsOverride;
    if (override != null) return override(action, mailIds);
    return mailIds
        .map((id) => BulkActionResult(mailId: id, success: true))
        .toList();
  }
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
