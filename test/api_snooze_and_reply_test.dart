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

  group('snooze deadline expiry', () {
    test('a passing deadline invalidates the view via notifyListeners without '
        'an explicit getEmailsInFolder call forcing it', () async {
      final mailService = _RecordingMailService(
        folders: [_folder('folder-inbox', 'Inbox')],
        pagesByFolderId: {
          'folder-inbox': _page([_mailJson('mail-1')]),
        },
      );
      // A short check interval (real time, no fake clock) keeps this a
      // fast unit test while still exercising the real Timer.periodic
      // sweep end to end.
      final repo = await _repositoryWithLoadedInbox(
        mailService,
        snoozeCheckInterval: const Duration(milliseconds: 20),
      );
      var notifications = 0;
      repo.addListener(() => notifications++);

      await repo.setSnoozed([
        'mail-1',
      ], DateTime.now().add(const Duration(milliseconds: 60)));

      // Snoozed: hidden from Inbox, surfaced in the Ertelenenler view.
      expect(repo.getEmailsInFolder(MailFolder.inbox), isEmpty);
      expect(repo.getEmailsInFolder(MailFolder.snoozed).map((e) => e.id), [
        'mail-1',
      ]);

      notifications = 0;
      // Nothing here calls getEmailsInFolder while waiting — the
      // periodic sweep alone must notice the deadline passed and
      // invalidate the cached view on its own.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(notifications, greaterThan(0));
      expect(repo.getEmailsInFolder(MailFolder.snoozed), isEmpty);
      expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id), [
        'mail-1',
      ]);
    });

    test('a still-future deadline does not fire early', () async {
      final mailService = _RecordingMailService(
        folders: [_folder('folder-inbox', 'Inbox')],
        pagesByFolderId: {
          'folder-inbox': _page([_mailJson('mail-1')]),
        },
      );
      final repo = await _repositoryWithLoadedInbox(
        mailService,
        snoozeCheckInterval: const Duration(milliseconds: 20),
      );

      await repo.setSnoozed([
        'mail-1',
      ], DateTime.now().add(const Duration(minutes: 10)));

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(repo.getEmailsInFolder(MailFolder.snoozed).map((e) => e.id), [
        'mail-1',
      ]);
      expect(repo.getEmailsInFolder(MailFolder.inbox), isEmpty);
    });
  });
}

Future<ApiMailRepository> _repositoryWithLoadedInbox(
  _RecordingMailService mailService, {
  MailCache? cache,
  Duration snoozeCheckInterval = const Duration(seconds: 30),
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
    snoozeExpiryCheckInterval: snoozeCheckInterval,
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
  final Map<String, DateTime> snoozedMailIds = {};

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
  Future<void> mailAction(String id, String action) async {}

  @override
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async =>
      mailIds.map((id) => BulkActionResult(mailId: id, success: true)).toList();

  @override
  Future<void> setSnooze(String mailId, DateTime untilUtc) async =>
      snoozedMailIds[mailId] = untilUtc;

  @override
  Future<void> clearSnooze(String mailId) async =>
      snoozedMailIds.remove(mailId);

  @override
  Future<Map<String, DateTime>> getSnoozed() async =>
      Map<String, DateTime>.from(snoozedMailIds);
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
