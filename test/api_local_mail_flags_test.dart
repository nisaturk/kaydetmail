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
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pin/reply/forward stay client-only', () {
    test(
      'setPinned caps at maxPinnedMails and never calls the network',
      () async {
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([
              _mailJson('mail-1'),
              _mailJson('mail-2'),
              _mailJson('mail-3'),
              _mailJson('mail-4'),
            ]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        await repo.setPinned(['mail-1', 'mail-2', 'mail-3', 'mail-4'], true);

        final inbox = repo.getEmailsInFolder(MailFolder.inbox);
        expect(inbox.where((email) => email.isPinned).length, 3);
        expect(
          inbox.singleWhere((email) => email.id == 'mail-4').isPinned,
          false,
        );
        expect(mailService.singleActionCalls, isEmpty);
        expect(mailService.bulkActionCalls, isEmpty);

        await repo.setPinned(['mail-1'], false);
        expect(
          repo
              .getEmailsInFolder(MailFolder.inbox)
              .singleWhere((email) => email.id == 'mail-1')
              .isPinned,
          isFalse,
        );
      },
    );

    test(
      'pin/reply/forward flags survive a fresh repository instance (persisted)',
      () async {
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1')]),
          },
        );
        final db = MailCache.inMemory(); // the "disk" both launches share
        final repo1 = await _repositoryWithLoadedInbox(mailService, cache: db);
        await repo1.setPinned(['mail-1'], true);
        await repo1.markAsReplied(['mail-1']);

        // A second repository instance (e.g. after an app restart) refetches
        // from the fixture's static isRead:false — only the local-only flags
        // (pin/reply) are expected to survive that; isRead itself is real
        // server state and out of scope for this fixture.
        final repo2 = await _repositoryWithLoadedInbox(mailService, cache: db);
        final email = repo2.getEmailsInFolder(MailFolder.inbox).single;

        expect(email.isPinned, isTrue);
        expect(email.isReplied, isTrue);
      },
    );

    test(
      'markAsForwarded marks forwarded locally and read via the real API',
      () async {
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1')]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        await repo.markAsForwarded(['mail-1']);

        final email = repo.getEmailsInFolder(MailFolder.inbox).single;
        expect(email.isForwarded, isTrue);
        expect(email.isRead, isTrue);
        // "Forwarded" is local-only; the resulting read state is a real mail
        // state, so it goes through the bulk read action, not a local fake.
        expect(mailService.bulkActionCalls, ['read:mail-1:null']);
        expect(mailService.singleActionCalls, isEmpty);
      },
    );

    test(
      'markAsReplied marks every loaded thread member, not only the opened '
      'message',
      () async {
        // Two messages in the same conversation; the user opens the reply
        // screen from mail-1 but the inbox row representative could be
        // either one depending on thread grouping — both must show replied.
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([
              _mailJson('mail-1', threadId: 'thread-1'),
              _mailJson('mail-2', threadId: 'thread-1'),
            ]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        await repo.markAsReplied(['mail-1']);

        final inbox = repo.getEmailsInFolder(MailFolder.inbox);
        expect(inbox.every((e) => e.isReplied), isTrue);
      },
    );

    test(
      'replied/forwarded survive a fresh instance even when the originally '
      'marked message in the thread is never reloaded',
      () async {
        // Regression for the audit bug where a thread's representative row
        // sometimes didn't show the replied/forwarded icon: aggregation
        // used to require the specific flagged message to be loaded into
        // memory. Here only mail-2 is ever fetched in the second instance —
        // mail-1 (the one actually marked) is not — yet mail-2 must still
        // show both flags because they are tracked per-thread.
        final mailService = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([
              _mailJson('mail-1', threadId: 'thread-1'),
              _mailJson('mail-2', threadId: 'thread-1'),
            ]),
          },
        );
        final db = MailCache.inMemory();
        final repo1 = await _repositoryWithLoadedInbox(mailService, cache: db);
        await repo1.markAsReplied(['mail-1']);
        await repo1.markAsForwarded(['mail-1']);

        final onlyMailTwo = _RecordingMailService(
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-2', threadId: 'thread-1')]),
          },
        );
        final repo2 = await _repositoryWithLoadedInbox(onlyMailTwo, cache: db);
        final mailTwo = repo2.getEmailsInFolder(MailFolder.inbox).single;

        expect(mailTwo.isReplied, isTrue);
        expect(mailTwo.isForwarded, isTrue);
      },
    );
  });
  group('starred virtual folder', () {
    test(
      'shows only starred mail while pins only change folder order',
      () async {
        final mailService = _RecordingMailService(
          folders: [
            _folder('folder-inbox', 'Inbox'),
            _folder('folder-archive', 'Archive'),
          ],
          pagesByFolderId: {
            'folder-inbox': _page([
              _mailJson('mail-old', receivedAt: '2026-01-01T00:00:00Z'),
              _mailJson('mail-new', receivedAt: '2026-06-01T00:00:00Z'),
            ]),
            'folder-archive': _page([_mailJson('mail-archived')]),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);
        await repo.loadMoreEmails(MailFolder.archive);

        await repo.setPinned(['mail-old'], true);
        await repo.setStarred(['mail-archived'], true);

        final starred = repo.getEmailsInFolder(MailFolder.starred);
        expect(starred.map((e) => e.id), ['mail-archived']);

        final inbox = repo.getEmailsInFolder(MailFolder.inbox);
        // Highlighted (pinned) mail floats above newer, non-highlighted mail.
        expect(inbox.first.id, 'mail-old');
      },
    );
  });

  group('lastSyncedAt', () {
    test(
      'null before a folder has ever synced, set after initial load and '
      'refresh',
      () async {
        final mailService = _RecordingMailService(
          folders: [
            _folder('folder-inbox', 'Inbox'),
            _folder('folder-archive', 'Archive'),
          ],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1')]),
            'folder-archive': _page(const []),
          },
        );
        final repo = await _repositoryWithLoadedInbox(mailService);

        // Inbox was loaded by the shared setup helper.
        final afterLoad = repo.lastSyncedAt(MailFolder.inbox);
        expect(afterLoad, isNotNull);
        // A folder nothing ever fetched has no sync timestamp yet.
        expect(repo.lastSyncedAt(MailFolder.trash), isNull);

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repo.refreshEmails(MailFolder.inbox);
        final afterRefresh = repo.lastSyncedAt(MailFolder.inbox);
        expect(afterRefresh, isNotNull);
        expect(afterRefresh!.isAfter(afterLoad!), isTrue);
      },
    );
  });
}

Future<ApiMailRepository> _repositoryWithLoadedInbox(
  _RecordingMailService mailService, {
  MailCache? cache,
}) async {
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
    openCache: cache == null ? null : () async => cache,
  );
  await repo.restoreSession('person@example.com');
  await repo.loadMoreEmails(MailFolder.inbox);
  return repo;
}

Map<String, dynamic> _folder(String id, String type) => {
  'id': id,
  'mailAccountId': 'account-1',
  'name': type,
  'folderType': type,
};

Map<String, dynamic> _mailJson(
  String id, {
  String receivedAt = '2026-09-17T01:56:58Z',
  String threadId = '',
}) => {
  'id': id,
  'subject': 'Subject $id',
  'fromAddress': 'sender@example.com',
  'fromDisplayName': 'Sender',
  'toAddress': 'person@example.com',
  'isRead': false,
  'hasAttachments': false,
  'receivedAt': receivedAt,
  'conversationId': threadId,
};

MailListPage _page(List<Map<String, dynamic>> items) => MailListPage(
  items: items.map(_mapMailForTest).toList(),
  page: 1,
  pageSize: 20,
  total: items.length,
);

Email _mapMailForTest(Map<String, dynamic> item) => Email(
  id: item['id'] as String,
  senderName: item['fromDisplayName'] as String,
  senderEmail: item['fromAddress'] as String,
  recipients: [item['toAddress'] as String],
  subject: item['subject'] as String,
  bodyText: '',
  timestamp: DateTime.parse(item['receivedAt'] as String),
  isRead: item['isRead'] as bool,
  threadId: item['conversationId'] as String? ?? '',
);

class _RecordingMailService extends ApiMailService {
  _RecordingMailService({required this.folders, required this.pagesByFolderId})
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<Map<String, dynamic>> folders;
  final Map<String, MailListPage> pagesByFolderId;
  final List<String> bulkActionCalls = [];
  final List<String> singleActionCalls = [];

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
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    bulkActionCalls.add('$action:${mailIds.join(",")}:$folderId');
    return mailIds
        .map((id) => BulkActionResult(mailId: id, success: true))
        .toList();
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
