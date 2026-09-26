import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_custom_folder.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/screens/custom_folders_screen.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/widgets/move_folder_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('folder service uses create, patch, delete request contracts', () async {
    final requests = <http.Request>[];
    final service = ApiMailService(
      _client((request) async {
        requests.add(request);
        if (request.method == 'DELETE') return http.Response('', 204);
        return http.Response(
          jsonEncode({
            'id': 'f-1',
            'mailAccountId': 'acc-1',
            'name': 'Mobil',
            'fullName': 'INBOX.Mobil',
            'folderType': 'Custom',
            'delimiter': '.',
            'parentId': 'inbox-id',
          }),
          200,
        );
      }),
    );

    final created = await service.createFolder('Mobil', parentId: 'inbox-id');
    await service.renameFolder('f-1', 'Yeni');
    await service.deleteFolder('f/1');

    expect(requests[0].method, 'POST');
    expect(requests[0].url.path, '/api/folders');
    expect(jsonDecode(requests[0].body), {
      'name': 'Mobil',
      'parentId': 'inbox-id',
    });
    expect(created.delimiter, '.');
    expect(created.parentId, 'inbox-id');
    expect(requests[1].method, 'PATCH');
    expect(requests[1].url.path, '/api/folders/f-1');
    expect(jsonDecode(requests[1].body), {'name': 'Yeni'});
    expect(requests[2].method, 'DELETE');
    expect(requests[2].url.toString(), endsWith('/api/folders/f%2F1'));
  });

  test('folder service preserves structured problem error codes', () async {
    final service = ApiMailService(
      _client(
        (_) async => http.Response(
          jsonEncode({'code': 'mail_folder_not_empty', 'title': 'Conflict'}),
          409,
        ),
      ),
    );
    await expectLater(
      service.deleteFolder('f-1'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'mail_folder_not_empty',
        ),
      ),
    );
  });

  test('folder operations route to each owning account session', () async {
    SharedPreferences.setMockInitialValues({});
    final first = _routingAccount('account-1', 'first@example.com');
    final second = _routingAccount('account-2', 'second@example.com');
    final repo = ApiMailRepository(
      authService: first.authService,
      mailService: first.mailService,
      sessionFactory: () =>
          (authService: second.authService, mailService: second.mailService),
    );
    await repo.connectAccount(email: 'first@example.com', password: 'pw');
    await repo.connectAccount(email: 'second@example.com', password: 'pw');

    await repo.createCustomFolder(accountId: 'account-1', name: 'First');
    await repo.createCustomFolder(accountId: 'account-2', name: 'Second');
    await repo.renameCustomFolder(
      accountId: 'account-2',
      folderId: 'custom-account-2',
      name: 'Renamed',
    );
    await repo.deleteCustomFolder(
      accountId: 'account-1',
      folderId: 'custom-account-1',
    );

    expect(first.mailService.calls, [
      'create:First:null',
      'delete:custom-account-1',
    ]);
    expect(second.mailService.calls, [
      'create:Second:null',
      'rename:custom-account-2:Renamed',
    ]);
  });

  test(
    'folders cached before hierarchy support are rediscovered once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final account = _routingAccount('account-1', 'first@example.com');
      final repo = ApiMailRepository(
        authService: account.authService,
        mailService: account.mailService,
      );
      await repo.connectAccount(email: 'first@example.com', password: 'pw');
      account.mailService.folders.addAll([
        ApiMailFolder(
          id: 'projects',
          mailAccountId: 'account-1',
          name: 'Projeler',
          type: 'Custom',
        ),
        ApiMailFolder(
          id: 'mobile',
          mailAccountId: 'account-1',
          name: 'Mobil',
          fullName: 'Projeler/Mobil',
          type: 'Custom',
        ),
      ]);

      await repo.refreshCustomFolders(accountId: 'account-1');
      await repo.refreshCustomFolders(accountId: 'account-1');

      expect(account.mailService.refreshes, 1);
      final roots = buildCustomFolderTree(
        repo.getCustomFolders(accountId: 'account-1'),
      );
      expect(roots.map((node) => node.folder.folderId), ['projects']);
      expect(roots.single.children.map((node) => node.folder.folderId), [
        'mobile',
      ]);
    },
  );

  test('folder error messages explain management conflicts in Turkish', () {
    expect(
      customFolderErrorMessage(
        const ApiException(status: 409, code: 'mail_folder_exists'),
      ),
      'Bu adda bir klasör zaten var.',
    );
    expect(
      customFolderErrorMessage(
        const ApiException(status: 409, code: 'mail_folder_has_children'),
      ),
      'Önce alt klasörleri silin.',
    );
  });

  test(
    'folder names are trimmed and reject the active hierarchy delimiter',
    () {
      expect(validateCustomFolderName('  Mobil  '), isNull);
      expect(
        validateCustomFolderName('Work.Archive', delimiter: '.'),
        'Klasör adı "." karakterini içeremez.',
      );
      expect(validateCustomFolderName('   '), isNotNull);
    },
  );

  test('tree resolves parent ids across slash and INBOX dot paths', () {
    final folders = [
      _folder('root', 'Projects', 'INBOX.Projects', delimiter: '.'),
      _folder(
        'child',
        'Archive',
        'INBOX.Projects.Archive',
        parentId: 'root',
        delimiter: '.',
      ),
      _folder('other', 'Other', 'Work/Other', delimiter: '/'),
      _folder(
        'nested',
        'Nested',
        'Work/Other/Nested',
        parentId: 'other',
        delimiter: '/',
      ),
      _folder(
        'inbox-parent-child',
        'Shared',
        'INBOX.Shared',
        parentId: 'non-custom-inbox',
        delimiter: '.',
      ),
    ];
    final rows = flattenCustomFolderTree(folders);
    expect(rows.map((row) => (row.folder.folderId, row.depth)), [
      ('other', 0),
      ('nested', 1),
      ('root', 0),
      ('child', 1),
      ('inbox-parent-child', 0),
    ]);
  });

  test(
    'move target list filters current folders and account-local folders',
    () {
      final repo = _FolderRepo(
        available: {
          'a': {
            MailFolder.inbox,
            MailFolder.sent,
            MailFolder.drafts,
            MailFolder.archive,
            MailFolder.trash,
          },
          'b': {
            MailFolder.inbox,
            MailFolder.sent,
            MailFolder.drafts,
            MailFolder.archive,
            MailFolder.trash,
          },
        },
        folders: [
          _folder('a-custom', 'Project', 'Project', accountId: 'a'),
          _folder('b-custom', 'Secret', 'Secret', accountId: 'b'),
        ],
      );
      final targets = buildMoveFolderTargets(
        repository: repo,
        accountIds: {'a', 'b'},
        currentFolders: {MailFolder.inbox},
      );
      expect(targets.map((target) => target.folder), [
        MailFolder.archive,
        MailFolder.trash,
      ]);
      expect(targets.every((target) => target.customFolder == null), isTrue);
      final singleAccount = buildMoveFolderTargets(
        repository: repo,
        accountIds: {'a'},
        currentFolders: {MailFolder.inbox},
        currentCustomFolderId: 'a-custom',
      );
      expect(
        singleAccount.where((target) => target.customFolder != null),
        isEmpty,
      );
    },
  );
  testWidgets('create, rename and confirm deletion of a custom folder', (
    tester,
  ) async {
    final repo = _ScreenFolderRepo();
    AppConfig.mailRepositoryForTest = repo;
    addTearDown(AppConfig.resetForTest);
    await tester.pumpWidget(const MaterialApp(home: CustomFoldersScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni klasör'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Projects ');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.createdNames, ['Projects']);
    expect(find.text('Projects'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeniden adlandır'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.renamedNames, ['Work']);
    expect(find.text('Work'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    expect(find.text('Klasör silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    expect(repo.deletedIds, ['folder-1']);
    expect(find.text('Özel klasör yok'), findsOneWidget);
  });
}

MailCustomFolder _folder(
  String id,
  String name,
  String fullName, {
  String accountId = 'a',
  String? parentId,
  String? delimiter,
}) => MailCustomFolder(
  accountId: accountId,
  folderId: id,
  name: name,
  fullName: fullName,
  isSyncEnabled: false,
  parentFolderId: parentId,
  delimiter: delimiter,
);

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      tokenStore: TokenStore(storage: _MemoryTokenStorage()),
      accountId: 'acc-1',
      httpClient: MockClient(handler),
    );
({ApiAuthService authService, _RoutingFolderService mailService})
_routingAccount(String id, String email) {
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  final client = ApiClient(
    tokenStore: tokenStore,
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/accounts/discover') {
        return http.Response(
          jsonEncode({
            'discoveryId': 'discovery-$id',
            'email': email,
            'provider': 'Custom',
            'authenticationMethods': ['Password'],
            'manualSetupAvailable': true,
          }),
          200,
        );
      }
      if (request.url.path == '/api/accounts/connect') {
        return http.Response(
          jsonEncode({
            'accessToken': 'access-$id',
            'refreshToken': 'refresh-$id',
            'mailAccountId': id,
            'accessTokenExpiresAt': '2026-09-25T00:00:00Z',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    }),
  );
  return (
    authService: ApiAuthService(
      client: client,
      tokenStore: tokenStore,
      deviceIdentifierProvider: MemoryDeviceIdentifierProvider('device-$id'),
    ),
    mailService: _RoutingFolderService(
      ApiClient(
        tokenStore: tokenStore,
        accountId: id,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      id,
      email,
    ),
  );
}

class _RoutingFolderService extends ApiMailService {
  _RoutingFolderService(super.client, this.accountId, this.email);

  final String accountId;
  final String email;
  final List<String> calls = [];
  final List<ApiMailFolder> folders = [];
  int refreshes = 0;

  @override
  Future<MailAccount> getAccount() async =>
      MailAccount(id: accountId, email: email);

  @override
  Future<int> refreshFolders() async {
    refreshes++;
    return folders.length + 1;
  }

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: 'inbox-$accountId',
      mailAccountId: accountId,
      name: 'Inbox',
      type: 'Inbox',
      delimiter: refreshes > 0 ? '/' : null,
    ),
    for (final folder in folders)
      ApiMailFolder(
        id: folder.id,
        mailAccountId: folder.mailAccountId,
        name: folder.name,
        fullName: folder.fullName,
        type: folder.type,
        parentId: folder.parentId,
        delimiter: refreshes > 0 ? '/' : folder.delimiter,
      ),
  ];

  @override
  Future<List<String>> getPinnedMailIds() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getLabels() async => const [];

  @override
  Future<Map<String, List<String>>> getLabelAssignments() async => const {};

  @override
  Future<List<Map<String, dynamic>>> getContacts() async => const [];

  @override
  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    int page = 1,
    int pageSize = 20,
  }) async => const [];

  @override
  Future<ApiMailFolder> createFolder(String name, {String? parentId}) async {
    calls.add('create:$name:$parentId');
    final folder = ApiMailFolder(
      id: 'custom-$accountId',
      mailAccountId: accountId,
      name: name,
      type: 'Custom',
      parentId: parentId,
    );
    folders.add(folder);
    return folder;
  }

  @override
  Future<ApiMailFolder> renameFolder(String id, String name) async {
    calls.add('rename:$id:$name');
    final folder = ApiMailFolder(
      id: id,
      mailAccountId: accountId,
      name: name,
      type: 'Custom',
    );
    folders.removeWhere((entry) => entry.id == id);
    folders.add(folder);
    return folder;
  }

  @override
  Future<void> deleteFolder(String id) async {
    calls.add('delete:$id');
    folders.removeWhere((entry) => entry.id == id);
  }
}

class _ScreenFolderRepo extends MailRepository {
  final List<MailCustomFolder> folders = [];
  final List<String> createdNames = [];
  final List<String> renamedNames = [];
  final List<String> deletedIds = [];

  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'a', email: 'person@example.com'),
  ];

  @override
  String? get activeAccountId => 'a';

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) => folders;

  @override
  Future<void> refreshCustomFolders({String? accountId}) async {}

  @override
  Future<void> createCustomFolder({
    required String accountId,
    required String name,
    String? parentFolderId,
  }) async {
    createdNames.add(name);
    folders.add(
      _folder(
        'folder-1',
        name,
        name,
        accountId: accountId,
        delimiter: '/',
        parentId: parentFolderId,
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> renameCustomFolder({
    required String accountId,
    required String folderId,
    required String name,
  }) async {
    renamedNames.add(name);
    final index = folders.indexWhere((folder) => folder.folderId == folderId);
    folders[index] = _folder(folderId, name, name, accountId: accountId);
    notifyListeners();
  }

  @override
  Future<void> deleteCustomFolder({
    required String accountId,
    required String folderId,
  }) async {
    deletedIds.add(folderId);
    folders.removeWhere((folder) => folder.folderId == folderId);
    notifyListeners();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FolderRepo extends MailRepository {
  _FolderRepo({required this.available, required this.folders});

  final Map<String, Set<MailFolder>> available;
  final List<MailCustomFolder> folders;

  @override
  Set<MailFolder> availableFolders(String accountId) =>
      available[accountId] ?? const {};

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) => folders
      .where((folder) => accountId == null || folder.accountId == accountId)
      .toList();

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
