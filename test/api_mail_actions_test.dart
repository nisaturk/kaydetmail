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
    test('markAsRead updates only the ids the server confirmed', () async {
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

      await repo.markAsRead(['mail-1', 'mail-2']);

      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      expect(inbox.firstWhere((e) => e.id == 'mail-1').isRead, isTrue);
      expect(inbox.firstWhere((e) => e.id == 'mail-2').isRead, isFalse);
      expect(mailService.bulkActionCalls, ['read:mail-1,mail-2:null']);
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

    test('moveToFolder restores a trashed mail via bulk restore, not bulk move', () async {
      final mailService = _RecordingMailService(
        folders: [
          _folder('folder-inbox', 'Inbox'),
          _folder('folder-trash', 'Trash'),
        ],
        pagesByFolderId: {
          'folder-trash': _page([_mailJson('mail-1', 'folder-trash')]),
        },
      );
      final repo = await _repositoryWithLoadedFolder(
        mailService,
        MailFolder.trash,
      );

      await repo.moveToFolder(['mail-1'], MailFolder.inbox);

      expect(mailService.singleActionCalls, isEmpty);
      expect(mailService.bulkActionCalls.single, startsWith('restore'));
      expect(repo.getEmailsInFolder(MailFolder.trash), isEmpty);
      expect(repo.getEmailsInFolder(MailFolder.inbox).single.id, 'mail-1');
    });

    test('setStarred uses one bulk star request and updates the cache', () async {
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

    test('syncFolderId POSTs a bodyless folder sync', () async {
      late http.Request sent;
      final service = ApiMailService(
        _client((request) async {
          sent = request;
          return http.Response('', 202);
        }),
      );

      await service.syncFolderId('f-1');

      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/folders/f-1/sync');
      expect(sent.body, isEmpty);
    });
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

Map<String, dynamic> _mailJson(String id, String folderId) => {
  'id': id,
  'folderId': folderId,
  'subject': 'Subject $id',
  'fromAddress': 'sender@example.com',
  'fromDisplayName': 'Sender',
  'toAddress': 'person@example.com',
  'isRead': false,
  'hasAttachments': false,
  'receivedAt': '2026-09-17T01:56:58Z',
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
  final List<String> bulkActionCalls = [];
  final List<String> singleActionCalls = [];
  final List<String> syncedFolderIds = [];
  List<BulkActionResult> Function(String action, List<String> ids)?
  bulkResultsOverride;

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
  }) async =>
      pagesByFolderId[folderId] ??
      MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);

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
