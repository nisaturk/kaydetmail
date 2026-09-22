import 'dart:io';

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

  group('offline restore', () {
    test(
      'restoreSession falls back to the on-device cache when the backend is unreachable',
      () async {
        final db = MailCache.inMemory();
        // A previous, successful launch left its mailbox and folder map on
        // disk — mirrors what ApiMailRepository.notifyListeners persists.
        db.apply('account-1', [
          _mail('mail-1', 'inbox'),
          _mail('mail-2', 'inbox'),
        ], const []);
        db.saveFolders('account-1', {'folder-inbox': 'inbox'});

        final repo = await _restoredRepository(
          _ToggleableMailService(online: false, folders: const [], pagesByFolderId: const {}),
          cache: db,
        );

        expect(repo.isLoggedIn, isTrue);
        expect(repo.isOffline, isTrue);
        expect(
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          unorderedEquals(['mail-1', 'mail-2']),
        );
      },
    );

    test(
      'restoreSession still fails when the backend is unreachable and nothing is cached',
      () async {
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
          deviceIdentifierProvider: const MemoryDeviceIdentifierProvider(
            'device-1',
          ),
        );
        final repo = ApiMailRepository(
          authService: authService,
          mailService: _ToggleableMailService(
            online: false,
            folders: const [],
            pagesByFolderId: const {},
          ),
          openCache: () async => MailCache.inMemory(),
        );

        await expectLater(
          repo.restoreSession('person@example.com'),
          throwsA(anything),
        );
        expect(repo.isLoggedIn, isFalse);
      },
    );

    test(
      'a successful reload after coming back online clears the offline flag',
      () async {
        final db = MailCache.inMemory();
        db.apply('account-1', [_mail('mail-1', 'inbox')], const []);
        db.saveFolders('account-1', {'folder-inbox': 'inbox'});

        final service = _ToggleableMailService(
          online: false,
          folders: [_folder('folder-inbox', 'Inbox')],
          pagesByFolderId: {
            'folder-inbox': _page([_mailJson('mail-1'), _mailJson('mail-2')]),
          },
        );
        final repo = await _restoredRepository(service, cache: db);
        expect(repo.isOffline, isTrue);

        service.online = true;
        await repo.refreshEmails(MailFolder.inbox);

        expect(repo.isOffline, isFalse);
        expect(
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          containsAll(['mail-1', 'mail-2']),
        );
      },
    );
  });
}

Future<ApiMailRepository> _restoredRepository(
  ApiMailService mailService, {
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
    deviceIdentifierProvider: const MemoryDeviceIdentifierProvider(
      'device-1',
    ),
  );
  final repo = ApiMailRepository(
    authService: authService,
    mailService: mailService,
    openCache: () async => cache,
  );
  await repo.restoreSession('person@example.com');
  return repo;
}

Email _mail(String id, String folderName) => Email(
  id: id,
  senderName: 'Sender',
  senderEmail: 'sender@example.com',
  recipients: const ['person@example.com'],
  subject: 'Subject $id',
  bodyText: '',
  timestamp: DateTime.utc(2026, 1, 1),
  folder: MailFolder.values.byName(folderName),
  accountId: 'account-1',
);

Map<String, dynamic> _folder(String id, String type) => {
  'id': id,
  'mailAccountId': 'account-1',
  'name': type,
  'folderType': type,
};

Map<String, dynamic> _mailJson(String id) => {
  'id': id,
  'subject': 'Subject $id',
  'fromAddress': 'sender@example.com',
  'fromDisplayName': 'Sender',
  'toAddress': 'person@example.com',
  'isRead': false,
  'hasAttachments': false,
  'receivedAt': '2026-09-17T01:56:58Z',
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
);

/// A mail service whose network calls throw (simulating no route to the
/// backend) until [online] is flipped to `true`, mirroring connectivity
/// returning mid-session.
class _ToggleableMailService extends ApiMailService {
  _ToggleableMailService({
    required this.online,
    required this.folders,
    required this.pagesByFolderId,
  }) : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  bool online;
  final List<Map<String, dynamic>> folders;
  final Map<String, MailListPage> pagesByFolderId;

  @override
  Future<List<ApiMailFolder>> getFolders() async {
    if (!online) throw const SocketException('Network unreachable');
    return folders
        .map(
          (f) => ApiMailFolder(
            id: f['id'] as String,
            mailAccountId: f['mailAccountId'] as String,
            name: f['name'] as String,
            type: f['folderType'] as String,
          ),
        )
        .toList();
  }

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
    if (!online) throw const SocketException('Network unreachable');
    return pagesByFolderId[folderId] ??
        MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);
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
