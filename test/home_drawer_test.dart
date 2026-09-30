import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/home_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/widgets/app_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends MailRepository {
  final List<String> calls = [];
  Object? syncError;
  final List<String> conflicts = [];
  List<Email> emails = [];
  final List<String> trashedIds = [];

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';
  @override
  String? get activeAccountId => null;
  @override
  bool get isOffline => false;
  @override
  List<String> get offlineMutationConflicts => List.unmodifiable(conflicts);

  @override
  void dismissMutationConflict(String id) {
    conflicts.remove(id);
    notifyListeners();
  }

  @override
  List<Email> getEmailsInFolder(MailFolder folder) => emails
      .where((mail) => folder == MailFolder.all || mail.folder == folder)
      .toList();
  @override
  List<Email> getAllEmails() => emails;
  @override
  List<Email> getScopedEmails() => emails;
  @override
  List<Email> getThreadEmails(String threadId) =>
      emails.where((mail) => mail.threadId == threadId).toList();
  @override
  int unreadCount(MailFolder folder) =>
      getEmailsInFolder(folder).where((mail) => !mail.isRead).length;

  @override
  Future<void> moveToTrash(List<String> ids) async {
    trashedIds.addAll(ids);
    emails = [
      for (final mail in emails)
        ids.contains(mail.id) ? mail.copyWith(folder: MailFolder.trash) : mail,
    ];
    notifyListeners();
  }

  @override
  bool hasMoreEmails(MailFolder folder) => false;
  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async => const [];
  @override
  List<MailLabel> getLabels() => const [];

  @override
  Future<void> syncFolder(MailFolder folder) async {
    calls.add('sync:${folder.name}');
    final error = syncError;
    if (error != null) throw error;
  }

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    calls.add('refresh:${folder.name}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });
  tearDown(AppConfig.resetForTest);

  Future<_FakeRepo> pumpHome(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    double textScale = 1,
    List<Email> emails = const [],
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..emails = emails;
    AppConfig.mailRepositoryForTest = repo;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets(
    'multi-select delete leaves an unselected thread sibling in inbox',
    (tester) async {
      Email message(String id, String subject, String threadId) => Email(
        id: id,
        senderName: 'Gönderen',
        senderEmail: 'gonderen@example.com',
        recipients: const ['ben@example.com'],
        subject: subject,
        bodyText: 'Gövde',
        timestamp: DateTime(2026, 9, 26),
        threadId: threadId,
        isRead: true,
      );
      final repo = await pumpHome(
        tester,
        emails: [
          message('m1', 'Seçilen ileti', 'same-thread'),
          message('m2', 'Seçilmeyen kardeş ileti', 'same-thread'),
          message('m3', 'Başka seçilen ileti', 'other-thread'),
        ],
      );

      await tester.longPress(find.text('Seçilen ileti'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Başka seçilen ileti'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sil'));
      await tester.pumpAndSettle();

      expect(repo.trashedIds, unorderedEquals(['m1', 'm3']));
      expect(repo.getEmailsInFolder(MailFolder.inbox).map((mail) => mail.id), [
        'm2',
      ]);
      expect(find.text('Seçilmeyen kardeş ileti'), findsOneWidget);
      expect(find.text('Seçilen ileti'), findsNothing);
      expect(find.text('Başka seçilen ileti'), findsNothing);
    },
  );

  Future<void> openDrawer(WidgetTester tester) async {
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('Hesapları eşitle runs the global sync', (tester) async {
    final repo = await pumpHome(tester);
    repo.calls.clear();
    await openDrawer(tester);

    await tester.tap(find.text('Hesapları eşitle'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['sync:all', 'refresh:all']);
    expect(find.byType(AppDrawer), findsNothing, reason: 'drawer closes');
    expect(find.text('Hesaplar eşitlendi.'), findsOneWidget);
  });

  testWidgets('a failed global sync is reported, not shown as success', (
    tester,
  ) async {
    final repo = await pumpHome(tester);
    repo.syncError = StateError('boom');
    await openDrawer(tester);

    await tester.tap(find.text('Hesapları eşitle'));
    await tester.pumpAndSettle();

    expect(repo.calls, isNot(contains('refresh:all')));
    expect(find.text('Hesaplar eşitlendi.'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('conflicts dismiss once without listener reentrancy', (
    tester,
  ) async {
    final repo = await pumpHome(tester);
    repo.conflicts.addAll(['first', 'second']);

    repo.notifyListeners();
    await tester.pumpAndSettle();

    expect(repo.conflicts, isEmpty);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Hesap ve uygulama sits below the folders at the drawer bottom '
      'on a tall screen', (tester) async {
    await pumpHome(tester, size: const Size(412, 1400));
    await openDrawer(tester);

    final lastFolderBottom = tester.getBottomLeft(find.text('Arşiv')).dy;
    final starredBottom = tester.getBottomLeft(find.text('Yıldızlılar')).dy;
    final archiveTop = tester.getTopLeft(find.text('Arşiv')).dy;
    final headingTop = tester.getTopLeft(find.text('Hesap ve uygulama')).dy;
    final logoutBottom = tester.getBottomLeft(find.text('Çıkış Yap')).dy;
    final drawerBottom = tester.getBottomLeft(find.byType(AppDrawer)).dy;

    expect(archiveTop, greaterThan(starredBottom));
    expect(headingTop, greaterThan(lastFolderBottom + 200));
    expect(drawerBottom - logoutBottom, lessThan(40));
  });

  testWidgets('drawer and home shell lay out without overflow on small, '
      'landscape and tablet screens with large text', (tester) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);
    const sizes = [
      Size(320, 568), // small phone
      Size(640, 320), // landscape phone
      Size(900, 700), // tablet: rail instead of drawer
      Size(1366, 1024), // master/detail
    ];
    for (final size in sizes) {
      for (final scale in [1.0, 1.3, 2.0]) {
        await pumpHome(tester, size: size, textScale: scale);
        if (size.width < 840) await openDrawer(tester);
        final logout = find.text('Çıkış Yap');
        await tester.scrollUntilVisible(
          logout,
          100,
          scrollable: find
              .descendant(
                of: find.byType(AppDrawer),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(logout, findsOneWidget);
        final error = tester.takeException();
        if (error is FlutterError) {
          fail(
            'overflow at $size, text scale $scale:\n${error.toStringDeep()}',
          );
        }
        expect(error, isNull, reason: 'overflow at $size, text scale $scale');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
