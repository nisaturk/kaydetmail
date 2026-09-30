import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/custom_folder_mail_screen.dart';
import 'package:kaydetmail/screens/home_screen.dart';
import 'package:kaydetmail/screens/inbox_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/widgets/app_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BackTestRepository extends MailRepository {
  _BackTestRepository(this.emails);

  final List<Email> emails;

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';
  @override
  String? get activeAccountId => null;
  @override
  bool get isOffline => false;
  @override
  List<Email> getEmailsInFolder(MailFolder folder) => emails;
  @override
  List<Email> getAllEmails() => emails;
  @override
  List<Email> getScopedEmails() => emails;
  @override
  List<Email> cachedCustomFolderMails(String accountId, String folderId) =>
      emails;
  @override
  List<Email> getThreadEmails(String threadId) => const [];
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });
  tearDown(AppConfig.resetForTest);

  Future<void> pumpHome(
    WidgetTester tester, {
    List<Email> emails = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppConfig.mailRepositoryForTest = _BackTestRepository(emails);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openDrawer(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  List<Email> backTestEmails() => [
    for (final id in ['first', 'second'])
      Email(
        id: id,
        senderName: 'Gönderen',
        senderEmail: 'gonderen@example.com',
        recipients: const ['ben@example.com'],
        subject: 'Geri testi $id',
        bodyText: 'Gövde',
        timestamp: DateTime(2026, 9, 26),
        isRead: true,
      ),
  ];

  List<MethodCall> capturePlatformExits(WidgetTester tester) {
    final exits = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call);
        return null;
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    return exits;
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  const exitPrompt = 'Çıkmak için geri tuşuna tekrar basın.';

  testWidgets('system back clears bulk selection before arming root exit', (
    tester,
  ) async {
    await pumpHome(tester, emails: backTestEmails());
    final exits = capturePlatformExits(tester);
    await tester.longPress(find.text('Geri testi first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Geri testi second'));
    await tester.pumpAndSettle();
    final selection = tester
        .widget<InboxScreen>(find.byType(InboxScreen))
        .selection;
    expect(selection.count, 2);

    await systemBack(tester);
    expect(selection.isActive, isFalse);
    expect(selection.selectedIds, isEmpty);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text(exitPrompt), findsNothing);
    expect(exits, isEmpty);

    await systemBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(exitPrompt), findsOneWidget);
    expect(exits, isEmpty);
    await systemBack(tester);
    expect(exits, hasLength(1));
  });

  testWidgets('root exit confirmation expires after two seconds', (
    tester,
  ) async {
    await pumpHome(tester);
    final exits = capturePlatformExits(tester);
    await systemBack(tester);
    expect(find.text(exitPrompt), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(exitPrompt), findsNothing);

    await systemBack(tester);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsOneWidget);
    await systemBack(tester);
    expect(exits, hasLength(1));
  });

  testWidgets('entering selection cancels an already armed root exit', (
    tester,
  ) async {
    await pumpHome(tester, emails: backTestEmails());
    final exits = capturePlatformExits(tester);
    await systemBack(tester);
    await tester.longPress(find.text('Geri testi first'));
    await tester.pumpAndSettle();
    expect(find.text(exitPrompt), findsNothing);

    await systemBack(tester);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsNothing);
    await systemBack(tester);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('drawer back closes the drawer without arming root exit', (
    tester,
  ) async {
    await pumpHome(tester);
    final exits = capturePlatformExits(tester);
    await systemBack(tester);
    await openDrawer(tester);
    expect(find.text(exitPrompt), findsNothing);
    await systemBack(tester);
    expect(find.byType(AppDrawer), findsNothing);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsNothing);

    await systemBack(tester);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('custom folder back dismisses selection then pops to home', (
    tester,
  ) async {
    await pumpHome(tester, emails: backTestEmails());
    final exits = capturePlatformExits(tester);
    final context = tester.element(find.byType(HomeScreen));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CustomFolderMailScreen(
          accountId: 'account-1',
          folderId: 'folder-1',
          name: 'Özel klasör',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Geri testi first'));
    await tester.pumpAndSettle();
    final selection = tester
        .widget<InboxScreen>(find.byType(InboxScreen))
        .selection;

    await systemBack(tester);
    expect(selection.isActive, isFalse);
    expect(selection.selectedIds, isEmpty);
    expect(find.text('Özel klasör'), findsOneWidget);
    expect(find.text(exitPrompt), findsNothing);
    await systemBack(tester);
    expect(find.byType(CustomFolderMailScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsNothing);
  });

  testWidgets('bulk action sheet back closes sheet before clearing selection', (
    tester,
  ) async {
    await pumpHome(tester, emails: backTestEmails());
    final exits = capturePlatformExits(tester);
    await tester.longPress(find.text('Geri testi first'));
    await tester.pumpAndSettle();
    final selection = tester
        .widget<InboxScreen>(find.byType(InboxScreen))
        .selection;
    await tester.tap(find.byTooltip('Diğer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ertele'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(selection.selectedIds, {'first'});
    expect(selection.isActive, isTrue);
    expect(exits, isEmpty);
    expect(find.text(exitPrompt), findsNothing);
    await systemBack(tester);
    expect(selection.selectedIds, isEmpty);
    expect(selection.isActive, isFalse);
    expect(exits, isEmpty);
  });
}
