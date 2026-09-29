import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_custom_folder.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/custom_folder_mail_screen.dart';
import 'package:kaydetmail/screens/home_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/custom_folder_order_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _orderKey = 'kaydet.folders.customOrder.';

MailCustomFolder _folder(
  String id,
  String name, {
  String account = 'a1',
  String? parent,
}) => MailCustomFolder(
  accountId: account,
  folderId: id,
  name: name,
  fullName: parent == null ? name : '$parent/$name',
  isSyncEnabled: false,
  parentFolderId: parent,
);

List<String> _preorder(
  Iterable<MailCustomFolder> folders,
  Map<String, List<String>> orders,
) => [
  for (final row in flattenCustomFolderTree(folders, orderByAccount: orders))
    row.folder.folderId,
];

class _FakeRepo extends MailRepository {
  _FakeRepo(this.folders);

  final List<MailCustomFolder> folders;
  String? active;

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';
  @override
  MailAccount? getAccount(String id) => null;
  @override
  String? get activeAccountId => active;
  @override
  bool get isOffline => false;
  @override
  List<String> get offlineMutationConflicts => const [];
  @override
  void dismissMutationConflict(String id) {}
  @override
  List<Email> getEmailsInFolder(MailFolder folder) => const [];
  @override
  List<Email> getAllEmails() => const [];
  @override
  List<Email> getScopedEmails() => const [];
  @override
  int unreadCount(MailFolder folder) => 0;
  @override
  bool hasMoreEmails(MailFolder folder) => false;
  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async => const [];
  @override
  List<MailLabel> getLabels() => const [];
  @override
  Future<void> syncFolder(MailFolder folder) async {}
  @override
  Future<void> refreshEmails(MailFolder folder) async {}

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) => [
    for (final folder in folders)
      if ((accountId ?? active) == null ||
          folder.accountId == (accountId ?? active))
        folder,
  ];

  void switchAccount(String? accountId) {
    active = accountId;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
    CustomFolderOrderController.resetForTest();
  });
  tearDown(AppConfig.resetForTest);

  group('moveCustomFolderAmongSiblings', () {
    final folders = [
      _folder('a', 'Alfa'),
      _folder('b', 'Beta'),
      _folder('b1', 'Bir', parent: 'b'),
      _folder('b2', 'İki', parent: 'b'),
    ];
    const order = ['a', 'b', 'b1', 'b2'];

    test('moves a root together with its subtree', () {
      expect(moveCustomFolderAmongSiblings(folders, order, 'b', -1), [
        'b',
        'b1',
        'b2',
        'a',
      ]);
    });

    test('reorders children only under their own parent', () {
      expect(moveCustomFolderAmongSiblings(folders, order, 'b2', -1), [
        'a',
        'b',
        'b2',
        'b1',
      ]);
      expect(moveCustomFolderAmongSiblings(folders, order, 'b1', -1), isNull);
      expect(moveCustomFolderAmongSiblings(folders, order, 'b2', 1), isNull);
      expect(moveCustomFolderAmongSiblings(folders, order, 'a', -1), isNull);
    });
  });

  group('CustomFolderOrderController', () {
    test('drops deleted ids, appends new folders alphabetically and '
        'persists per account', () async {
      SharedPreferences.setMockInitialValues({
        '${_orderKey}a1': ['b', 'gone', 'a'],
        '${_orderKey}a2': ['x2', 'x1'],
      });
      final folders = [
        _folder('a', 'Alfa'),
        _folder('b', 'Beta'),
        _folder('c', 'Cem'),
        _folder('d', 'Ahmet'),
      ];
      final controller = CustomFolderOrderController.instance;

      await controller.sync(folders);

      expect(controller.orders['a1'], ['b', 'a', 'd', 'c']);
      expect(_preorder(folders, controller.orders), ['b', 'a', 'd', 'c']);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('${_orderKey}a1'), ['b', 'a', 'd', 'c']);
      expect(preferences.getStringList('${_orderKey}a2'), ['x2', 'x1']);
    });

    test('an account without loaded folders keeps its saved order', () async {
      SharedPreferences.setMockInitialValues({
        '${_orderKey}a1': ['b', 'a'],
      });
      await CustomFolderOrderController.instance.sync(const []);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('${_orderKey}a1'), ['b', 'a']);
    });

    test('a moved order survives a restart', () async {
      final folders = [
        _folder('a', 'Alfa'),
        _folder('b', 'Beta'),
        _folder('b1', 'Bir', parent: 'b'),
      ];
      final controller = CustomFolderOrderController.instance;
      await controller.sync(folders);
      expect(await controller.move(folders, 'b', -1), isTrue);

      CustomFolderOrderController.resetForTest();
      expect(controller.orders, isEmpty);
      await controller.sync(folders);

      expect(_preorder(folders, controller.orders), ['b', 'b1', 'a']);
    });
  });

  group('drawer custom folders', () {
    Future<_FakeRepo> pumpHome(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(412, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo([
        _folder('a', 'Alfa'),
        _folder('b', 'Beta'),
        _folder('b1', 'Bir', parent: 'b'),
        _folder('b2', 'İki', parent: 'b'),
        _folder('z', 'Zeta', account: 'a2'),
      ])..active = 'a1';
      AppConfig.mailRepositoryForTest = repo;
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> openDrawer(WidgetTester tester) async {
      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pumpAndSettle();
    }

    List<String> visibleOrder(WidgetTester tester, List<String> names) {
      final visible = names.where(
        (name) => find.text(name).evaluate().isNotEmpty,
      );
      return visible.toList()..sort(
        (a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy),
      );
    }

    testWidgets('reorders siblings, keeps the order across account switches '
        'and opens the folder mail screen', (tester) async {
      final repo = await pumpHome(tester);
      await openDrawer(tester);
      const names = ['Alfa', 'Beta', 'Bir', 'İki', 'Zeta'];
      expect(visibleOrder(tester, names), ['Alfa', 'Beta', 'Bir', 'İki']);
      expect(
        tester.getTopLeft(find.text('Bir')).dx,
        greaterThan(tester.getTopLeft(find.text('Beta')).dx),
        reason: 'children stay indented under their parent',
      );

      await tester.tap(find.byTooltip('Klasörleri sırala'));
      await tester.pumpAndSettle();
      // Rows: Alfa, Beta, Bir, İki → move Beta (with children) above Alfa,
      // then İki above Bir inside Beta.
      await tester.tap(find.byTooltip('Yukarı taşı').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Yukarı taşı').at(2));
      await tester.pumpAndSettle();
      expect(visibleOrder(tester, names), ['Beta', 'İki', 'Bir', 'Alfa']);

      repo.switchAccount('a2');
      await tester.pumpAndSettle();
      expect(visibleOrder(tester, names), ['Zeta']);
      repo.switchAccount('a1');
      await tester.pumpAndSettle();
      expect(visibleOrder(tester, names), ['Beta', 'İki', 'Bir', 'Alfa']);

      await tester.tap(find.byTooltip('Sıralamayı bitir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İki'));
      await tester.pumpAndSettle();

      final screen = tester.widget<CustomFolderMailScreen>(
        find.byType(CustomFolderMailScreen),
      );
      expect((screen.accountId, screen.folderId), ('a1', 'b2'));
    });
  });
}
