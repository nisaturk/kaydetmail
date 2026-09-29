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
import 'package:kaydetmail/models/account_sync_scope.dart';
import 'package:kaydetmail/models/mail_folder_info.dart';
import 'package:kaydetmail/screens/custom_folders_screen.dart';
import 'package:kaydetmail/screens/folder_manager_screen.dart';
import 'package:kaydetmail/utils/error_messages.dart';
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
    await service.setFolderParent('f-1', null);
    await service.setFolderParent('f-1', 'inbox-id');
    await service.renameFolder('f-1', 'Yeni');
    await service.deleteFolder('f/1');
    await service.setFolderRole('f-1', 'Sent');
    await service.setFolderRole('f-1', null);

    expect(requests[0].method, 'POST');
    expect(requests[0].url.path, '/api/folders');
    expect(jsonDecode(requests[0].body), {
      'name': 'Mobil',
      'parentId': 'inbox-id',
    });
    expect(created.delimiter, '.');
    expect(created.parentId, 'inbox-id');
    expect(requests[1].method, 'PUT');
    expect(requests[1].url.path, '/api/folders/f-1/parent');
    expect(jsonDecode(requests[1].body), {'parentId': null});
    expect(jsonDecode(requests[2].body), {'parentId': 'inbox-id'});
    expect(requests[3].method, 'PATCH');
    expect(requests[3].url.path, '/api/folders/f-1');
    expect(jsonDecode(requests[3].body), {'name': 'Yeni'});
    expect(requests[4].method, 'DELETE');
    expect(requests[4].url.toString(), endsWith('/api/folders/f%2F1'));
    expect(requests[5].method, 'PUT');
    expect(requests[5].url.path, '/api/folders/f-1/role');
    expect(jsonDecode(requests[5].body), {'role': 'Sent'});
    expect(jsonDecode(requests[6].body), {'role': null});
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
    await repo.changeCustomFolderParent(
      accountId: 'account-2',
      folderId: 'custom-account-2',
      parentFolderId: 'inbox-account-2',
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
      'parent:custom-account-2:inbox-account-2',
    ]);
  });

  test('folder role routes to the owning account and remaps Sent', () async {
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
    await repo.createCustomFolder(accountId: 'account-2', name: 'Sent Items');

    await repo.setFolderRole(
      accountId: 'account-2',
      folderId: 'custom-account-2',
      role: MailFolder.sent,
    );

    expect(second.mailService.calls, [
      'create:Sent Items:null',
      'role:custom-account-2:Sent',
    ]);
    expect(first.mailService.calls, isEmpty);
    expect(repo.availableFolders('account-2'), contains(MailFolder.sent));
    expect(
      repo.availableFolders('account-1'),
      isNot(contains(MailFolder.sent)),
    );
    expect(repo.getCustomFolders(accountId: 'account-2'), isEmpty);
    final assignment = repo.getFolderRoleAssignments().single;
    expect(assignment.accountId, 'account-2');
    expect(assignment.folderId, 'custom-account-2');
    expect(assignment.role, MailFolder.sent);

    await repo.setFolderRole(
      accountId: 'account-2',
      folderId: 'custom-account-2',
      role: null,
    );
    expect(
      repo.availableFolders('account-2'),
      isNot(contains(MailFolder.sent)),
    );
    expect(repo.getFolderRoleAssignments(), isEmpty);
    expect(repo.getCustomFolders(accountId: 'account-2'), hasLength(1));
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
      friendlyErrorMessage(
        const ApiException(status: 409, code: 'mail_folder_exists'),
      ),
      'Bu adda bir klasör zaten var.',
    );
    expect(
      friendlyErrorMessage(
        const ApiException(status: 409, code: 'mail_folder_has_children'),
      ),
      'Önce alt klasörleri silin.',
    );
  });

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

  test('explicit root ignores unchanged IMAP path after virtual reparent', () {
    final rows = flattenCustomFolderTree([
      _folder('parent', 'Parent', 'Parent', delimiter: '/'),
      _folder(
        'child',
        'Child',
        'Parent/Child',
        delimiter: '/',
        parentKnown: true,
      ),
    ]);
    expect(rows.map((row) => (row.folder.folderId, row.depth)), [
      ('child', 0),
      ('parent', 0),
    ]);
    expect(
      flattenCustomFolderTree(
        [
          _folder(
            'standard-child',
            'Child',
            'INBOX/Child',
            parentId: 'inbox-id',
            parentKnown: true,
          ),
          _folder(
            'nested',
            'Nested',
            'INBOX/Child/Nested',
            parentId: 'standard-child',
            parentKnown: true,
          ),
        ],
        standardParentIds: {'inbox-id'},
      ).map((row) => row.depth),
      [1, 2],
    );
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
  testWidgets(
    'move sheet nests selected-account folders and returns child target',
    (tester) async {
      final repo = _FolderRepo(
        available: {
          'a': {MailFolder.inbox, MailFolder.archive},
          'b': {MailFolder.inbox, MailFolder.archive},
        },
        folders: [
          _folder('a-parent', 'Projects', 'Projects', accountId: 'a'),
          _folder(
            'a-child',
            'Receipts',
            'Projects/Receipts',
            accountId: 'a',
            parentId: 'a-parent',
            delimiter: '/',
          ),
          _folder('b-parent', 'Private', 'Private', accountId: 'b'),
          _folder(
            'b-child',
            'Hidden',
            'Private/Hidden',
            accountId: 'b',
            parentId: 'b-parent',
            delimiter: '/',
          ),
        ],
      );
      MoveFolderTarget? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => selected = await showMoveFolderSheet(
                  context,
                  repository: repo,
                  accountIds: {'a'},
                  currentFolders: {MailFolder.inbox},
                ),
                child: const Text('Open move'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open move'));
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Private'), findsNothing);
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Receipts'), findsOneWidget);
      final parentTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Projects'),
          matching: find.byType(ListTile),
        ),
      );
      final childTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Receipts'),
          matching: find.byType(ListTile),
        ),
      );
      expect(
        (childTile.contentPadding! as EdgeInsets).left,
        greaterThan((parentTile.contentPadding! as EdgeInsets).left),
      );
      await tester.tap(find.text('Receipts'));
      await tester.pumpAndSettle();
      expect(selected?.customFolder?.folderId, 'a-child');
      expect(selected?.accountId, 'a');
    },
  );

  testWidgets('mixed-account move sheet omits custom targets', (tester) async {
    final repo = _FolderRepo(
      available: {
        'a': {MailFolder.inbox, MailFolder.archive},
        'b': {MailFolder.inbox, MailFolder.archive},
      },
      folders: [
        _folder('a-parent', 'Projects', 'Projects', accountId: 'a'),
        _folder('b-parent', 'Private', 'Private', accountId: 'b'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMoveFolderSheet(
                context,
                repository: repo,
                accountIds: {'a', 'b'},
                currentFolders: {MailFolder.inbox},
              ),
              child: const Text('Open move'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open move'));
    await tester.pumpAndSettle();
    expect(find.text('Arşiv'), findsOneWidget);
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Private'), findsNothing);
  });
  Future<_ScreenFolderRepo> pumpManager(
    WidgetTester tester, {
    List<MailFolderInfo> extra = const [],
    List<SyncScopeFolder>? scope,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _ScreenFolderRepo()..folders.addAll(extra);
    if (scope != null) repo.scope = scope;
    AppConfig.mailRepositoryForTest = repo;
    addTearDown(AppConfig.resetForTest);
    await tester.pumpWidget(
      const MaterialApp(home: FolderManagerScreen(accountId: 'a')),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> openMenu(WidgetTester tester, String folderId) async {
    await tester.tap(find.byKey(ValueKey('folder-menu-$folderId')));
    await tester.pumpAndSettle();
  }

  testWidgets('create, rename and delete an empty custom folder', (
    tester,
  ) async {
    final repo = await pumpManager(tester);
    await tester.tap(find.byKey(const Key('new-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bağımsız klasör'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Projects ');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.createdNames, ['Projects']);
    expect(find.text('Projects'), findsOneWidget);

    await openMenu(tester, 'folder-1');
    await tester.tap(find.text('Yeniden adlandır'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repo.renamedNames, ['Work']);

    await openMenu(tester, 'folder-1');
    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Klasör silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    expect(repo.deletedIds, ['folder-1']);
    expect(find.text('Work'), findsNothing);
  });

  testWidgets('duplicate sibling names are rejected before any request', (
    tester,
  ) async {
    final repo = await pumpManager(tester, extra: [_info('p', 'Projects')]);
    await tester.tap(find.byKey(const Key('new-folder')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bağımsız klasör'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'projects');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(find.text('Bu adda bir klasör zaten var.'), findsOneWidget);
    expect(repo.createdNames, isEmpty);
  });

  testWidgets(
    'a folder with mail or sub-folders explains why it cannot be deleted',
    (tester) async {
      final repo = await pumpManager(
        tester,
        extra: [
          _info('full', 'Full', total: 3),
          _info('kid', 'Kid', parent: 'full'),
        ],
      );

      await openMenu(tester, 'full');
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      expect(find.text('Klasör silinemez'), findsOneWidget);
      expect(find.textContaining('alt klasörleri'), findsOneWidget);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, isEmpty);
    },
  );

  testWidgets('standard folders offer neither rename nor delete', (
    tester,
  ) async {
    await pumpManager(tester);
    await openMenu(tester, 'inbox-id');

    expect(find.text('Alt klasör oluştur'), findsOneWidget);
    expect(find.text('Yeniden adlandır'), findsNothing);
    expect(find.text('Sil'), findsNothing);
    expect(find.text('Üst klasörü değiştir'), findsNothing);
  });

  testWidgets('assigns a folder role and restores automatic detection', (
    tester,
  ) async {
    final repo = await pumpManager(
      tester,
      extra: [_info('sent-items', 'Sent Items')],
    );

    await openMenu(tester, 'sent-items');
    await tester.tap(find.text('Klasör rolü ata'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MailFolder.sent.label));
    await tester.pumpAndSettle();
    expect(repo.roleCalls, ['sent-items:sent']);
    expect(find.text('Giden Kutusu olarak kullanılıyor'), findsOneWidget);

    await openMenu(tester, 'sent-items');
    await tester.tap(find.text('Otomatiğe döndür'));
    await tester.pumpAndSettle();
    expect(repo.roleCalls, ['sent-items:sent', 'sent-items:null']);
    expect(find.text('Giden Kutusu olarak kullanılıyor'), findsNothing);
  });

  testWidgets(
    'creates below INBOX, nests it, moves it and returns it to the root',
    (tester) async {
      final repo = await pumpManager(
        tester,
        extra: [_info('parent', 'Projects')],
      );

      await openMenu(tester, 'inbox-id');
      await tester.tap(find.text('Alt klasör oluştur'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Receipts');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(repo.createdParents, ['inbox-id']);

      double indent(String name) =>
          (tester
                      .widget<ListTile>(
                        find.ancestor(
                          of: find.text(name),
                          matching: find.byType(ListTile),
                        ),
                      )
                      .contentPadding!
                  as EdgeInsets)
              .left;
      expect(indent('Receipts'), greaterThan(indent('INBOX')));

      await openMenu(tester, 'folder-1');
      await tester.tap(find.text('Üst klasörü değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projects').last);
      await tester.pumpAndSettle();
      expect(repo.parentChanges, ['folder-1:parent']);
      expect(indent('Receipts'), greaterThan(indent('Projects')));

      await openMenu(tester, 'folder-1');
      await tester.tap(find.text('Üst klasörü değiştir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bağımsız klasör'));
      await tester.pumpAndSettle();
      expect(repo.parentChanges, ['folder-1:parent', 'folder-1:null']);
    },
  );

  testWidgets('automatic sync can be toggled per folder but never emptied', (
    tester,
  ) async {
    final repo = await pumpManager(
      tester,
      extra: [_info('docs', 'Docs')],
      scope: const [
        SyncScopeFolder(
          id: 'inbox-id',
          name: 'INBOX',
          type: 'Inbox',
          synced: true,
        ),
        SyncScopeFolder(
          id: 'docs',
          name: 'Docs',
          type: 'Custom',
          synced: false,
        ),
      ],
    );

    await openMenu(tester, 'docs');
    await tester.tap(find.text('Otomatik eşitlemeyi aç'));
    await tester.pumpAndSettle();
    expect(repo.scopeUpdates.single.toSet(), {'inbox-id', 'docs'});

    await openMenu(tester, 'docs');
    await tester.tap(find.text('Otomatik eşitlemeyi kapat'));
    await tester.pumpAndSettle();
    expect(repo.scopeUpdates.last, ['inbox-id']);

    // The last synced folder cannot be switched off: its menu item is disabled.
    await openMenu(tester, 'inbox-id');
    final item = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Otomatik eşitlemeyi kapat'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(item.enabled, isFalse);
    await tester.tap(
      find.text('Otomatik eşitlemeyi kapat'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repo.scopeUpdates, hasLength(2));
  });

  testWidgets('the refresh action asks the server to rediscover folders', (
    tester,
  ) async {
    final repo = await pumpManager(tester);
    expect(repo.rediscoverCalls, [false]);

    await tester.tap(find.byTooltip('Sunucudaki klasörleri yeniden tara'));
    await tester.pumpAndSettle();

    expect(repo.rediscoverCalls, [false, true]);
  });

  testWidgets(
    'with several accounts the entry screen asks which one to manage',
    (tester) async {
      AppConfig.mailRepositoryForTest = _TwoAccountRepo();
      addTearDown(AppConfig.resetForTest);
      await tester.pumpWidget(const MaterialApp(home: CustomFoldersScreen()));
      await tester.pumpAndSettle();

      expect(find.text('a@example.com'), findsOneWidget);
      expect(find.text('b@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('manage-folders-b')));
      await tester.pumpAndSettle();
      expect(find.byType(FolderManagerScreen), findsOneWidget);
    },
  );
}

MailFolderInfo _info(
  String id,
  String name, {
  String? parent,
  int? total,
  FolderKind kind = FolderKind.custom,
}) => MailFolderInfo(
  accountId: 'a',
  folderId: id,
  name: name,
  fullName: name,
  kind: kind,
  isSyncEnabled: false,
  parentFolderId: parent,
  totalCount: total,
  delimiter: '/',
);

MailCustomFolder _folder(
  String id,
  String name,
  String fullName, {
  String accountId = 'a',
  String? parentId,
  String? delimiter,
  bool parentKnown = false,
}) => MailCustomFolder(
  accountId: accountId,
  folderId: id,
  name: name,
  fullName: fullName,
  isSyncEnabled: false,
  parentFolderId: parentId,
  parentIdKnown: parentKnown,
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
  final Map<String, String> roles = {};

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
        type: roles[folder.id] ?? folder.type,
        parentId: folder.parentId,
        delimiter: refreshes > 0 ? '/' : folder.delimiter,
        roleOverride: roles[folder.id],
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
  Future<ApiMailFolder> setFolderParent(String id, String? parentId) async {
    calls.add('parent:$id:$parentId');
    final previous = folders.singleWhere((folder) => folder.id == id);
    final changed = ApiMailFolder(
      id: id,
      mailAccountId: accountId,
      name: previous.name,
      type: 'Custom',
      parentId: parentId,
      parentIdKnown: true,
    );
    folders.remove(previous);
    folders.add(changed);
    return changed;
  }

  @override
  Future<void> deleteFolder(String id) async {
    calls.add('delete:$id');
    folders.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<ApiMailFolder> setFolderRole(String id, String? role) async {
    calls.add('role:$id:$role');
    roles.removeWhere((_, value) => value == role);
    if (role == null) {
      roles.remove(id);
    } else {
      roles[id] = role;
    }
    return (await getFolders()).singleWhere((folder) => folder.id == id);
  }
}

class _ScreenFolderRepo extends MailRepository {
  final List<MailFolderInfo> folders = [
    const MailFolderInfo(
      accountId: 'a',
      folderId: 'inbox-id',
      name: 'INBOX',
      fullName: 'INBOX',
      kind: FolderKind.inbox,
      isSyncEnabled: true,
      delimiter: '/',
    ),
  ];
  final List<String> createdNames = [];
  final List<String?> createdParents = [];
  final List<String> parentChanges = [];
  final List<String> renamedNames = [];
  final List<String> deletedIds = [];
  final List<String> roleCalls = [];
  final List<bool> rediscoverCalls = [];
  final List<List<String>> scopeUpdates = [];
  List<SyncScopeFolder>? scope;

  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'a', email: 'person@example.com'),
  ];

  @override
  String? get activeAccountId => 'a';

  @override
  MailAccount? getAccount(String accountId) => accounts.first;

  @override
  List<MailFolderInfo> getAccountFolders(String accountId) =>
      List.unmodifiable(folders);

  @override
  Future<void> refreshCustomFolders({
    String? accountId,
    bool rediscover = false,
  }) async => rediscoverCalls.add(rediscover);

  @override
  Future<AccountSyncScope> getSyncScope(String accountId) async {
    final current = scope;
    if (current == null) throw const ApiException(status: 503);
    return AccountSyncScope(
      scope: FolderSyncScope.selectedFolders,
      folders: current,
    );
  }

  @override
  Future<AccountSyncScope> updateSyncScope(
    String accountId,
    FolderSyncScope scope, {
    List<String>? folderIds,
  }) async {
    scopeUpdates.add(folderIds!);
    this.scope = [
      for (final f in this.scope!)
        SyncScopeFolder(
          id: f.id,
          name: f.name,
          type: f.type,
          synced: folderIds.contains(f.id),
        ),
    ];
    return AccountSyncScope(scope: scope, folders: this.scope!);
  }

  @override
  Future<void> createCustomFolder({
    required String accountId,
    required String name,
    String? parentFolderId,
  }) async {
    createdNames.add(name);
    createdParents.add(parentFolderId);
    folders.add(_info('folder-1', name, parent: parentFolderId));
    notifyListeners();
  }

  @override
  Future<void> renameCustomFolder({
    required String accountId,
    required String folderId,
    required String name,
  }) async {
    renamedNames.add(name);
    final index = folders.indexWhere((f) => f.folderId == folderId);
    final old = folders[index];
    folders[index] = _info(folderId, name, parent: old.parentFolderId);
    notifyListeners();
  }

  @override
  Future<void> changeCustomFolderParent({
    required String accountId,
    required String folderId,
    required String? parentFolderId,
  }) async {
    parentChanges.add('$folderId:$parentFolderId');
    final index = folders.indexWhere((f) => f.folderId == folderId);
    folders[index] = _info(
      folderId,
      folders[index].name,
      parent: parentFolderId,
    );
    notifyListeners();
  }

  @override
  Future<void> deleteCustomFolder({
    required String accountId,
    required String folderId,
  }) async {
    deletedIds.add(folderId);
    folders.removeWhere((f) => f.folderId == folderId);
    notifyListeners();
  }

  @override
  Future<void> setFolderRole({
    required String accountId,
    required String folderId,
    required MailFolder? role,
  }) async {
    roleCalls.add('$folderId:${role?.name}');
    final index = folders.indexWhere((f) => f.folderId == folderId);
    final old = folders[index];
    final kind = role == null ? FolderKind.custom : FolderKind.sent;
    folders[index] = MailFolderInfo(
      accountId: old.accountId,
      folderId: old.folderId,
      name: old.name,
      fullName: old.fullName,
      kind: kind,
      isSyncEnabled: false,
      parentFolderId: old.parentFolderId,
      roleOverride: role == null ? null : kind,
    );
    notifyListeners();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _TwoAccountRepo extends MailRepository {
  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'a', email: 'a@example.com'),
    MailAccount(id: 'b', email: 'b@example.com'),
  ];

  @override
  String? get activeAccountId => null;

  @override
  MailAccount? getAccount(String accountId) =>
      accounts.where((a) => a.id == accountId).firstOrNull;

  @override
  List<MailFolderInfo> getAccountFolders(String accountId) => const [];

  @override
  Future<void> refreshCustomFolders({
    String? accountId,
    bool rediscover = false,
  }) async {}

  @override
  Future<AccountSyncScope> getSyncScope(String accountId) async =>
      throw const ApiException(status: 503);

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
