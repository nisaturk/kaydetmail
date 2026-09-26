import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
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

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';

  @override
  String? get activeAccountId => null;

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      folder == MailFolder.inbox && !calls.contains('trash') ? [email] : [];

  @override
  List<Email> getAllEmails() => [email];

  @override
  List<Email> getScopedEmails() => [email];

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
    email = email.copyWith(isRead: true);
    notifyListeners();
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    calls.add('trash');
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
  }) async {
    final repo = _FakeRepo();
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
    ];
    final folderPositions = [
      for (final label in folderLabels) tester.getTopLeft(find.text(label)).dy,
    ];
    for (var index = 1; index < folderPositions.length; index++) {
      expect(folderPositions[index - 1], lessThan(folderPositions[index]));
    }
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    for (final label in ['Hesapları eşitle', 'Klasörleri yönet', 'Ayarlar']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Ertelenenler'), findsNothing);
    expect(find.text('Arşiv'), findsNothing);
    expect(find.text('Yanıt Takibi'), findsNothing);
    expect(find.text('Zamanlanmış Gönderimler'), findsNothing);
  });
}
