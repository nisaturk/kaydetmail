import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/widgets/mail_list_item.dart';

Future<void> _login(
  WidgetTester tester, {
  String email = 'me@kaydet.app',
}) async {
  await tester.pumpWidget(const KaydetApp());
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
  await tester.ensureVisible(find.text('Login'));
  await tester.tap(find.text('Login'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

/// Sync read of a single mail's read-state, safe inside the fake-async zone
/// that `testWidgets` runs in (awaiting a mock `Future` would never resolve).
bool _readState(String id) => AppConfig.mailRepository
    .getEmailsInFolder(MailFolder.inbox)
    .firstWhere((e) => e.id == id)
    .isRead;

void main() {
  setUp(() {
    AppConfig.resetForTest();
    AppSettingsController.resetForTest();
  });

  group('smart back', () {
    testWidgets('Save draft closes compose, confirms and stores the draft',
        (tester) async {
      await _login(tester);
      await tester.tap(find.byTooltip('Compose'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(2), 'Draft body content');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save draft'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('New mail'), findsNothing);
      expect(find.text('Draft saved.'), findsOneWidget);
      final drafts =
          AppConfig.mailRepository.getEmailsInFolder(MailFolder.drafts);
      expect(
        drafts.where((e) => e.bodyText.contains('Draft body content')),
        isNotEmpty,
      );
    });

    testWidgets('Save draft also works for a subject-only mail',
        (tester) async {
      await _login(tester);
      await tester.tap(find.byTooltip('Compose'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(1), 'Subject only');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save draft'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('New mail'), findsNothing);
      final drafts =
          AppConfig.mailRepository.getEmailsInFolder(MailFolder.drafts);
      expect(drafts.map((e) => e.subject), contains('Subject only'));
    });

    testWidgets('Discard closes compose without saving', (tester) async {
      await _login(tester);
      await tester.tap(find.byTooltip('Compose'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(2), 'Will be discarded');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('New mail'), findsNothing);
      final drafts =
          AppConfig.mailRepository.getEmailsInFolder(MailFolder.drafts);
      expect(
        drafts.where((e) => e.bodyText.contains('Will be discarded')),
        isEmpty,
      );
    });
  });

  group('mail detail', () {
    testWidgets('opening a mail marks it as read', (tester) async {
      await _login(tester);

      expect(_readState('seed-finance-invoice'), isFalse);

      await tester.tap(find.text('Invoice #4821 for March'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(_readState('seed-finance-invoice'), isTrue);
    });

    testWidgets('mark as unread from detail stays unread', (tester) async {
      await _login(tester);

      await tester.tap(find.text('Fixing the CI pipeline'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as unread'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(_readState('seed-david-ci'), isFalse);

      // The auto-read-on-open reload must not flip it back.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(_readState('seed-david-ci'), isFalse);
    });
  });

  group('settings', () {
    testWidgets('created labels appear in settings and the repository',
        (tester) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.tap(find.text('New label'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Clients',
      );
      await tester.tap(find.text('Create'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Clients'), findsOneWidget);
      expect(
        AppConfig.mailRepository.getLabels().map((l) => l.name),
        contains('Clients'),
      );
    });

    testWidgets('notification and sync choices persist across visits',
        (tester) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(AppSettingsController.instance.notificationsEnabled, isFalse);

      await tester.ensureVisible(find.text('Every hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every hour'));
      await tester.pumpAndSettle();
      expect(AppSettingsController.instance.syncInterval, SyncInterval.everyHour);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openSettings(tester);

      expect(AppSettingsController.instance.notificationsEnabled, isFalse);
      expect(
        AppSettingsController.instance.syncInterval,
        SyncInterval.everyHour,
      );
    });
  });

  group('navigation', () {
    testWidgets('drawer switches folders and closes', (tester) async {
      await _login(tester);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sent'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Sent'),
        ),
        findsOneWidget,
      );
      expect(find.text('Re: Design review: onboarding flow'), findsOneWidget);
      expect(find.text('Logout'), findsNothing);
    });

    testWidgets('back navigation returns to a single home without duplicates',
        (tester) async {
      await _login(tester);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'invoice');
      await tester.pump();
      await tester.tap(find.text('Invoice #4821 for March'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Inbox'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('drawer shows the signed-in account', (tester) async {
      await _login(tester, email: 'other@example.com');

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.text('other@example.com'), findsOneWidget);
    });
  });

  group('responsive / overflow', () {
    testWidgets('small screen renders core screens without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;

      await _login(tester);

      await tester.tap(find.byTooltip('Compose'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(2),
        List.filled(50, 'long body text').join(' '),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'x' * 300);
      await tester.pump();

      // Reset view inside the test body so the tree settles before disposal.
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpAndSettle();
    });

    testWidgets('long sender and subject do not overflow the list row',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;

      final email = Email(
        id: 'long',
        senderName:
            'A Very Long Sender Name That Just Keeps Going And Going And Going',
        senderEmail: 'vlsn@example.com',
        recipients: const ['me@example.com'],
        subject: 'This is an exceedingly long subject line that should never '
            'overflow the row regardless of how much text is crammed into it',
        bodyText: 'body text ' * 30,
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [MailListItem(email: email)]),
        ),
      ));
      await tester.pump();

      // Reset view inside the test body so the tree settles before disposal.
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpAndSettle();
    });
  });
}