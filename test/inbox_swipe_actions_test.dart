import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/screens/inbox_screen.dart';
import 'package:kaydetmail/widgets/app_drawer.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/mail_selection_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepo extends MailRepository {
  Email email = Email(
    id: 'm1',
    senderName: 'Gönderen',
    senderEmail: 'gonderen@example.com',
    recipients: const ['ben@example.com'],
    subject: 'Kaydırılacak',
    bodyText: 'Gövde',
    timestamp: DateTime(2026, 9, 26),
    isRead: false,
  );
  final List<String> calls = [];
  Object? moveError;
  List<Email> siblings = [];
  final List<String> trashedIds = [];
  final List<String> readIds = [];

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';

  @override
  String? get activeAccountId => null;

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      folder == MailFolder.inbox || folder == MailFolder.all
      ? getAllEmails()
            .where((mail) => folder == MailFolder.all || mail.folder == folder)
            .toList()
      : [];

  @override
  List<Email> getAllEmails() => [email, ...siblings];

  @override
  List<Email> getScopedEmails() => getAllEmails();

  @override
  List<Email> getThreadEmails(String threadId) =>
      getAllEmails().where((mail) => mail.threadId == threadId).toList();

  @override
  bool hasMoreEmails(MailFolder folder) => false;
  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async => const [];

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    calls.add('refresh:${folder.name}');
  }

  @override
  Future<void> syncFolder(MailFolder folder) async {
    calls.add('sync:${folder.name}');
  }

  @override
  List<MailLabel> getLabels() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {
    calls.add('read');
    readIds.addAll(ids);
    if (ids.contains(email.id)) email = email.copyWith(isRead: true);
    siblings = [
      for (final mail in siblings)
        ids.contains(mail.id) ? mail.copyWith(isRead: true) : mail,
    ];
    notifyListeners();
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    if (moveError case final error?) throw error;
    calls.add('trash');
    trashedIds.addAll(ids);
    if (ids.contains(email.id)) {
      email = email.copyWith(folder: MailFolder.trash);
    }
    siblings = [
      for (final mail in siblings)
        ids.contains(mail.id) ? mail.copyWith(folder: MailFolder.trash) : mail,
    ];
    notifyListeners();
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });
  tearDown(AppConfig.resetForTest);

  Future<_FakeRepo> pumpInbox(
    WidgetTester tester, {
    MailFolder folder = MailFolder.inbox,
    bool sameThread = false,
  }) async {
    final repo = _FakeRepo();
    if (sameThread) {
      repo.email = repo.email.copyWith(threadId: 'conversation');
      repo.siblings = [
        Email(
          id: 'm2',
          threadId: 'conversation',
          senderName: repo.email.senderName,
          senderEmail: repo.email.senderEmail,
          recipients: repo.email.recipients,
          subject: 'Aynı konuşmanın diğer iletisi',
          bodyText: repo.email.bodyText,
          timestamp: repo.email.timestamp,
          isRead: false,
        ),
      ];
    }
    AppConfig.mailRepositoryForTest = repo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InboxScreen(
            folder: folder,
            selection: MailSelectionController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return repo;
  }

  testWidgets('cached all mail opens without a sync or refresh', (
    tester,
  ) async {
    final repo = await pumpInbox(tester, folder: MailFolder.all);

    expect(repo.calls, isEmpty);
    expect(find.text('Kaydırılacak'), findsOneWidget);
  });

  testWidgets('a configured toggle-read swipe marks read and keeps the row', (
    tester,
  ) async {
    AppSettingsController.instance.swipeRight = SwipeGesture.toggleRead;
    final repo = await pumpInbox(tester);

    await tester.drag(find.text('Kaydırılacak'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(repo.calls, ['read']);
    expect(find.text('Kaydırılacak'), findsOneWidget);
  });

  testWidgets('the default left swipe still moves the mail to trash', (
    tester,
  ) async {
    final repo = await pumpInbox(tester);

    await tester.drag(find.text('Kaydırılacak'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(repo.calls, ['trash']);
  });

  testWidgets(
    'same-thread rows stay separate and swiping one keeps its sibling',
    (tester) async {
      final repo = await pumpInbox(tester, sameThread: true);
      expect(find.text('Kaydırılacak'), findsOneWidget);
      expect(find.text('Aynı konuşmanın diğer iletisi'), findsOneWidget);

      await tester.drag(find.text('Kaydırılacak'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(repo.trashedIds, ['m1']);
      expect(find.text('Kaydırılacak'), findsNothing);
      expect(find.text('Aynı konuşmanın diğer iletisi'), findsOneWidget);
      expect(repo.siblings.single.folder, MailFolder.inbox);
    },
  );

  testWidgets('toggle-read swipe does not mark its thread sibling read', (
    tester,
  ) async {
    AppSettingsController.instance.swipeRight = SwipeGesture.toggleRead;
    final repo = await pumpInbox(tester, sameThread: true);

    await tester.drag(find.text('Kaydırılacak'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(repo.readIds, ['m1']);
    expect(repo.email.isRead, isTrue);
    expect(repo.siblings.single.isRead, isFalse);
  });

  testWidgets('a failed swipe keeps an API message', (tester) async {
    final repo = await pumpInbox(tester);
    repo.moveError = const ApiException(
      status: 409,
      code: 'mail_operation_conflict',
    );

    await tester.drag(find.text('Kaydırılacak'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('Posta kutusu değişti. Yenileyip tekrar deneyin.'),
      findsOneWidget,
    );
  });

  testWidgets('a swipe set to off does nothing in that direction', (
    tester,
  ) async {
    AppSettingsController.instance.swipeLeft = SwipeGesture.none;
    final repo = await pumpInbox(tester);

    await tester.drag(find.text('Kaydırılacak'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(repo.calls, isEmpty);
    expect(find.text('Kaydırılacak'), findsOneWidget);
  });

  testWidgets(
    'refreshing empty virtual folders does not sync a server folder',
    (tester) async {
      for (final folder in [MailFolder.starred, MailFolder.snoozed]) {
        final repo = await pumpInbox(tester, folder: folder);

        await tester.tap(find.text('Yenile'));
        await tester.pumpAndSettle();

        expect(repo.calls, ['refresh:${folder.name}']);
        expect(find.text('Beklenmedik bir hata oluştu'), findsNothing);
      }
    },
  );

  testWidgets('drawer lists only the requested folders and lower shortcuts', (
    tester,
  ) async {
    AppConfig.mailRepositoryForTest = _FakeRepo();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(
            selectedFolder: MailFolder.inbox,
            onSelectFolder: (_) {},
            onLogout: () {},
            onOpenDestination: (_) {},
            onSyncAccounts: () {},
            onAddAccount: () {},
            onSelectCustomFolder: (_) {},
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    for (final label in [
      'Gelen Kutusu',
      'Giden Kutusu',
      'Tüm mailler',
      'Taslaklar',
      'Spam',
      'Çöp Kutusu',
      'Yıldızlılar',
      'Arşiv',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final folderLabels = [
      'Gelen Kutusu',
      'Giden Kutusu',
      'Tüm mailler',
      'Taslaklar',
      'Spam',
      'Çöp Kutusu',
      'Yıldızlılar',
      'Arşiv',
    ];
    final folderPositions = [
      for (final label in folderLabels) tester.getTopLeft(find.text(label)).dy,
    ];
    for (var index = 1; index < folderPositions.length; index++) {
      expect(folderPositions[index - 1], lessThan(folderPositions[index]));
    }
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    for (final label in ['Hesapları eşitle', 'Klasörleri yönet', 'Ayarlar']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ertelenenler'), findsNothing);
    expect(find.text('Zamanlanmış Gönderimler'), findsNothing);
  });
}
