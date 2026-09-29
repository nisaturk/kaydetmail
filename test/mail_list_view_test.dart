import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_list_view.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/inbox_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/mail_selection_controller.dart';
import 'package:kaydetmail/utils/mail_ordering.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _mail(
  String id, {
  String sender = 'Ali',
  String subject = 'Konu',
  int day = 1,
  bool read = true,
  bool starred = false,
  bool attachment = false,
  bool pinned = false,
}) => Email(
  id: id,
  senderName: sender,
  senderEmail: '$id@example.com',
  recipients: const ['ben@example.com'],
  subject: subject,
  bodyText: '',
  timestamp: DateTime(2026, 9, day),
  isRead: read,
  isStarred: starred,
  hasAttachments: attachment,
  isPinned: pinned,
);

class _Repo extends MailRepository {
  _Repo(this.mails);
  final List<Email> mails;

  @override
  List<MailAccount> get accounts => const [];
  @override
  String get currentUser => 'ben@example.com';
  @override
  String? get activeAccountId => null;
  @override
  List<Email> getEmailsInFolder(MailFolder folder) => mails;
  @override
  List<Email> getScopedEmails() => mails;
  @override
  bool hasMoreEmails(MailFolder folder) => false;
  @override
  List<MailLabel> getLabels() => const [];
  @override
  Future<void> refreshEmails(MailFolder folder) async {}
  @override
  Future<void> syncFolder(MailFolder folder) async {}
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('filter and sort helpers', () {
    final mails = [
      _mail('new', sender: 'Zeynep', subject: 'b', day: 9, read: false),
      _mail('mid', sender: 'ali', subject: 'A', day: 5, starred: true),
      _mail('old', sender: 'Burak', subject: 'c', day: 1, attachment: true),
    ];

    test('each filter keeps only matching mails', () {
      List<String> ids(MailListFilter f) => [
        for (final m in applyMailListFilter(mails, f)) m.id,
      ];
      expect(ids(MailListFilter.all), ['new', 'mid', 'old']);
      expect(ids(MailListFilter.unread), ['new']);
      expect(ids(MailListFilter.starred), ['mid']);
      expect(ids(MailListFilter.attachments), ['old']);
    });

    test('sorts by every mode, case-insensitively and stably', () {
      List<String> ids(MailListSort s) => [
        for (final m in sortMailList(mails, s)) m.id,
      ];
      expect(ids(MailListSort.newest), ['new', 'mid', 'old']);
      expect(ids(MailListSort.oldest), ['old', 'mid', 'new']);
      expect(ids(MailListSort.unreadFirst), ['new', 'mid', 'old']);
      expect(ids(MailListSort.sender), ['mid', 'old', 'new']);
      expect(ids(MailListSort.subject), ['mid', 'new', 'old']);
    });

    test('pinned mail stays on top in every sort', () {
      final withPin = [
        ...mails,
        _mail('pin', sender: 'Zzz', day: 2, pinned: true),
      ];
      for (final sort in MailListSort.values) {
        expect(sortMailList(withPin, sort).first.id, 'pin', reason: '$sort');
      }
    });
  });

  group('inbox list view bar', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppSettingsController.resetForTest();
    });
    tearDown(AppConfig.resetForTest);

    Future<void> pump(WidgetTester tester, List<Email> mails) async {
      AppConfig.mailRepositoryForTest = _Repo(mails);
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
    }

    testWidgets('the unread chip hides read mail and can be cleared', (
      tester,
    ) async {
      await pump(tester, [
        _mail('a', subject: 'Okunmuş konu'),
        _mail('b', subject: 'Yeni konu', read: false),
      ]);
      expect(find.text('Okunmuş konu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mail-filter-unread')));
      await tester.pumpAndSettle();
      expect(find.text('Okunmuş konu'), findsNothing);
      expect(find.text('Yeni konu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mail-filter-all')));
      await tester.pumpAndSettle();
      expect(find.text('Okunmuş konu'), findsOneWidget);
    });

    testWidgets('a filter with no matches offers to clear itself', (
      tester,
    ) async {
      await pump(tester, [_mail('a', subject: 'Sadece okunmuş')]);

      await tester.tap(find.byKey(const Key('mail-filter-starred')));
      await tester.pumpAndSettle();
      expect(find.text('Bu filtreyle eşleşen posta yok'), findsOneWidget);

      await tester.tap(find.byKey(const Key('mail-filter-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Sadece okunmuş'), findsOneWidget);
    });

    testWidgets('the sort menu reorders the list', (tester) async {
      await pump(tester, [
        _mail('n', subject: 'Yeni', day: 9),
        _mail('o', subject: 'Eski', day: 1),
      ]);
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Yeni') < top('Eski'), isTrue);

      await tester.tap(find.byKey(const Key('mail-sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mail-sort-oldest')));
      await tester.pumpAndSettle();

      expect(top('Eski') < top('Yeni'), isTrue);
    });
  });
}
