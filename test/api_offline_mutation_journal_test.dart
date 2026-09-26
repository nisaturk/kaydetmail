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
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a read mutation that fails while offline still applies locally, then '
      'replays exactly once after reconnecting', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.markAsRead(['mail-1']);

    // Applied optimistically even though the network call failed.
    expect(repo.getEmailsInFolder(MailFolder.inbox).single.isRead, isTrue);
    expect(repo.isOffline, isTrue);
    mailService.bulkActionCalls.clear();

    // Back online: the next successful network round-trip replays the
    // queue exactly once.
    mailService.failBulkAction = false;
    await repo.refreshEmails(MailFolder.inbox);
    // refreshEmails's own network call plus the replay's bulkAction call.
    expect(mailService.bulkActionCalls, ['read:mail-1']);
    expect(repo.isOffline, isFalse);

    // A second successful reconnect-style call must NOT replay again —
    // the queue was cleared after the first successful replay.
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, ['read:mail-1']);
  });

  test('a replay that comes back as a mailbox conflict drops the queued '
      'mutation and surfaces it instead of retrying forever', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.markAsRead(['mail-1']);
    mailService.bulkActionCalls.clear();

    mailService.failBulkAction = false;
    mailService.forcedResultCodes['mail-1'] = 'mail_operation_conflict';
    await repo.refreshEmails(MailFolder.inbox);

    expect(repo.offlineMutationConflicts, ['mail-1']);

    // Dismissing clears it, and it does not reappear on a further
    // reconnect (the queue entry was dropped, not retried).
    repo.dismissMutationConflict('mail-1');
    expect(repo.offlineMutationConflicts, isEmpty);
    mailService.bulkActionCalls.clear();
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, isEmpty);
  });

  test(
    'toggling read then unread while offline only replays the final state',
    () async {
      final mailService = _RecordingMailService();
      final db = MailCache.inMemory();
      final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

      mailService.failBulkAction = true;
      await repo.markAsRead(['mail-1']);
      await repo.markAsUnread(['mail-1']);
      mailService.bulkActionCalls.clear();
      expect(repo.getEmailsInFolder(MailFolder.inbox).single.isRead, isFalse);

      mailService.failBulkAction = false;
      await repo.refreshEmails(MailFolder.inbox);
      expect(mailService.bulkActionCalls, ['unread:mail-1']);
    },
  );

  test('star/unstar offline queues and replays after reconnecting', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.setStarred(['mail-1'], true);
    expect(repo.getEmailsInFolder(MailFolder.inbox).single.isStarred, isTrue);
    mailService.bulkActionCalls.clear();

    mailService.failBulkAction = false;
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, ['star:mail-1']);
  });

  test('archive offline queues and replays after reconnecting', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.moveToFolder(['mail-1'], MailFolder.archive);
    expect(repo.getEmailsInFolder(MailFolder.archive).single.id, 'mail-1');
    expect(repo.getEmailsInFolder(MailFolder.inbox), isEmpty);
    mailService.bulkActionCalls.clear();

    mailService.failBulkAction = false;
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, ['archive:mail-1']);
  });

  test('archiving then trashing the same mail while offline collapses to one '
      'replayed location mutation', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.moveToFolder(['mail-1'], MailFolder.archive);
    await repo.moveToTrash(['mail-1']);
    expect(repo.getEmailsInFolder(MailFolder.trash).single.id, 'mail-1');
    mailService.bulkActionCalls.clear();

    mailService.failBulkAction = false;
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, ['trash:mail-1']);
  });

  test(
    'restore offline files the mail into Inbox as a placeholder, then '
    'corrects it to its real origin folder once the replay succeeds',
    () async {
      final mailService = _RecordingMailService();
      final db = MailCache.inMemory();
      final repo = await _repositoryWithLoadedInbox(mailService, cache: db);
      await repo.loadMoreEmails(MailFolder.trash);
      expect(repo.getEmailsInFolder(MailFolder.trash).single.id, 'mail-t');

      mailService.failBulkAction = true;
      await repo.moveToFolder(['mail-t'], MailFolder.inbox);
      expect(
        repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
        containsAll(['mail-1', 'mail-t']),
      );
      mailService.bulkActionCalls.clear();

      // The backend remembers mail-t actually came from Archive.
      mailService.restoreDestinationFolderId['mail-t'] = 'folder-archive';
      mailService.failBulkAction = false;
      await repo.refreshEmails(MailFolder.inbox);
      expect(mailService.bulkActionCalls, ['restore:mail-t']);
      expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
        'mail-1',
      ]);
      expect(repo.getEmailsInFolder(MailFolder.archive).single.id, 'mail-t');
    },
  );

  test('a non-read operation replay conflict drops the queued mutation and '
      'surfaces it, same as read/unread', () async {
    final mailService = _RecordingMailService();
    final db = MailCache.inMemory();
    final repo = await _repositoryWithLoadedInbox(mailService, cache: db);

    mailService.failBulkAction = true;
    await repo.setStarred(['mail-1'], true);
    mailService.bulkActionCalls.clear();

    mailService.failBulkAction = false;
    mailService.forcedResultCodes['mail-1'] = 'mail_not_found';
    await repo.refreshEmails(MailFolder.inbox);

    expect(repo.offlineMutationConflicts, ['mail-1']);
    mailService.bulkActionCalls.clear();
    await repo.refreshEmails(MailFolder.inbox);
    expect(mailService.bulkActionCalls, isEmpty);
  });
}

Future<ApiMailRepository> _repositoryWithLoadedInbox(
  _RecordingMailService mailService, {
  required MailCache cache,
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
    openCache: () async => cache,
  );
  await repo.restoreSession('person@example.com');
  await repo.loadMoreEmails(MailFolder.inbox);
  return repo;
}

class _RecordingMailService extends ApiMailService {
  _RecordingMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  bool failBulkAction = false;
  final List<String> bulkActionCalls = [];
  final Map<String, String> forcedResultCodes = {};

  /// mailId -> folder id `getMail` reports it landed in — used only by the
  /// restore tests, where `_fileRestored` asks the server where a restored
  /// mail actually went.
  final Map<String, String> restoreDestinationFolderId = {};

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: 'folder-inbox',
      mailAccountId: 'account-1',
      name: 'Inbox',
      type: 'Inbox',
    ),
    ApiMailFolder(
      id: 'folder-archive',
      mailAccountId: 'account-1',
      name: 'Archive',
      type: 'Archive',
    ),
    ApiMailFolder(
      id: 'folder-trash',
      mailAccountId: 'account-1',
      name: 'Trash',
      type: 'Trash',
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
    final item = folderId == 'folder-trash'
        ? Email(
            id: 'mail-t',
            senderName: 'Sender',
            senderEmail: 'sender@example.com',
            recipients: const ['person@example.com'],
            subject: 'Trashed',
            bodyText: '',
            timestamp: DateTime.parse('2026-09-17T01:56:58Z'),
            isRead: false,
          )
        : Email(
            id: 'mail-1',
            senderName: 'Sender',
            senderEmail: 'sender@example.com',
            recipients: const ['person@example.com'],
            subject: 'Subject',
            bodyText: '',
            timestamp: DateTime.parse('2026-09-17T01:56:58Z'),
            isRead: false,
          );
    return MailListPage(
      items: [item],
      page: page,
      pageSize: pageSize,
      total: 1,
    );
  }

  @override
  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
    bool allowRemoteImages = false,
  }) async {
    final folder = resolveFolder(
      restoreDestinationFolderId[id] ?? 'folder-inbox',
    );
    return Email(
      id: id,
      senderName: 'Sender',
      senderEmail: 'sender@example.com',
      recipients: const ['person@example.com'],
      subject: 'Subject',
      bodyText: '',
      timestamp: DateTime.parse('2026-09-17T01:56:58Z'),
      isRead: false,
      folder: folder,
    );
  }

  @override
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    bulkActionCalls.add('$action:${mailIds.join(",")}');
    if (failBulkAction) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    return [
      for (final id in mailIds)
        BulkActionResult(
          mailId: id,
          success: forcedResultCodes[id] == null,
          code: forcedResultCodes[id],
        ),
    ];
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
