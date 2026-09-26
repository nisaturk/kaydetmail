import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/inbox_screen.dart';
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
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError(
    invocation.memberName.toString(),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });
  tearDown(AppConfig.resetForTest);

  Future<_FakeRepo> pumpInbox(WidgetTester tester) async {
    final repo = _FakeRepo();
    AppConfig.mailRepositoryForTest = repo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InboxScreen(
            folder: MailFolder.inbox,
            selection: MailSelectionController(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
}
