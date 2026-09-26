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

  group('ApiMailRepository custom folders', () {
    test('refreshCustomFolders keeps only available Custom folders, sorted by fullName', () async {
      final service = _FakeMailService(
        folders: [
          _folder('f-inbox', 'Inbox', 'Inbox', type: 'Inbox'),
          _folder('f-b', 'Projeler', 'Projeler', type: 'Custom'),
          _folder('f-a', 'Özel', 'Arşiv/Özel', type: 'Custom'),
          _folder('f-gone', 'Eski', 'Eski', type: 'Custom', isAvailable: false),
        ],
      );
      final repo = await _repository(service);

      await repo.refreshCustomFolders();
      final folders = repo.getCustomFolders();

      expect(folders.map((f) => f.folderId), ['f-a', 'f-b']);
      expect(folders.every((f) => f.accountId == 'account-1'), isTrue);
    });

    test(
      'getCustomFolderMails/loadMoreCustomFolderMails paginate and accumulate',
      () async {
        final service = _FakeMailService(
          folders: [_folder('f-1', 'Projeler', 'Projeler', type: 'Custom')],
          pagesByFolderId: {
            'f-1': [
              _page([_mail('m1'), _mail('m2')], page: 1, total: 3),
              _page([_mail('m3')], page: 2, total: 3),
            ],
          },
        );
        final repo = await _repository(service);

        final first = await repo.getCustomFolderMails(
          accountId: 'account-1',
          folderId: 'f-1',
        );
        expect(first.map((e) => e.id), ['m1', 'm2']);
        expect(repo.hasMoreCustomFolderMails('account-1', 'f-1'), isTrue);

        final all = await repo.loadMoreCustomFolderMails(
          accountId: 'account-1',
          folderId: 'f-1',
        );
        expect(all.map((e) => e.id), ['m1', 'm2', 'm3']);
        expect(repo.hasMoreCustomFolderMails('account-1', 'f-1'), isFalse);
      },
    );

    test(
      'syncCustomFolder forwards the raw folder id; unknown accounts throw',
      () async {
        final service = _FakeMailService(folders: const []);
        final repo = await _repository(service);

        await repo.syncCustomFolder(accountId: 'account-1', folderId: 'f-1');
        expect(service.syncedFolderIds, ['f-1']);

        expect(
          () => repo.getCustomFolderMails(
            accountId: 'unknown-account',
            folderId: 'f-1',
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

Future<ApiMailRepository> _repository(_FakeMailService service) async {
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
    mailService: service,
  );
  await repo.restoreSession('person@example.com');
  return repo;
}

ApiMailFolder _folder(
  String id,
  String name,
  String fullName, {
  required String type,
  bool isAvailable = true,
}) => ApiMailFolder(
  id: id,
  mailAccountId: 'account-1',
  name: name,
  fullName: fullName,
  type: type,
  isAvailable: isAvailable,
);

Email _mail(String id) => Email(
  id: id,
  senderName: 'Sender',
  senderEmail: 'sender@example.com',
  recipients: const ['person@example.com'],
  subject: 'Subject $id',
  bodyText: '',
  timestamp: DateTime.parse('2026-09-17T01:56:58Z'),
  folder: MailFolder.inbox,
);

MailListPage _page(
  List<Email> items, {
  required int page,
  required int total,
}) => MailListPage(items: items, page: page, pageSize: 2, total: total);

class _FakeMailService extends ApiMailService {
  _FakeMailService({required this.folders, this.pagesByFolderId = const {}})
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<ApiMailFolder> folders;
  final Map<String, List<MailListPage>> pagesByFolderId;
  final List<String> syncedFolderIds = [];

  @override
  Future<List<ApiMailFolder>> getFolders() async => folders;

  @override
  Future<int> refreshFolders() async => folders.length;

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
    final pages = pagesByFolderId[folderId];
    if (pages == null || pages.isEmpty) {
      return MailListPage(
        items: const [],
        page: page,
        pageSize: pageSize,
        total: 0,
      );
    }
    final index = (page - 1).clamp(0, pages.length - 1);
    return pages[index];
  }

  @override
  Future<void> syncFolderId(String folderId) async {
    syncedFolderIds.add(folderId);
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
