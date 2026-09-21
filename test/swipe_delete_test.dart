import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const KaydetApp());
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('email-field')), 'me@kaydet.app');
  await tester.tap(find.text('Devam'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('password-field')), 'secret123');
  await tester.tap(find.byKey(const Key('signin-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

/// Swipes a row left far enough to trigger Dismissible.
Future<void> _swipeLeft(WidgetTester tester, Finder target) async {
  await tester.drag(target, const Offset(-600, 0));
  // Finish the dismiss animation (confirmDismiss fires here).
  await tester.pumpAndSettle();
  // Let the repository's move latency elapse so the undo snackbar shows.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Swipes a row right far enough to trigger Dismissible.
Future<void> _swipeRight(WidgetTester tester, Finder target) async {
  await tester.drag(target, const Offset(600, 0));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Finder _settingsScrollable() => find.descendant(
  of: find.byKey(const Key('settings-list')),
  matching: find.byType(Scrollable),
);

Future<void> _disableSwipe(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Gezinme menüsünü aç'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ayarlar'));
  await tester.pumpAndSettle();

  await tester.scrollUntilVisible(
    find.text('Kaydırarak sil'),
    150,
    scrollable: _settingsScrollable(),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Kaydırarak sil'));
  await tester.pumpAndSettle();
  expect(AppSettingsController.instance.swipeDeleteEnabled, isFalse);

  await tester.tap(find.byTooltip('Geri'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppConfig.resetForTest();
    AppSettingsController.resetForTest();
  });

  group('swipe-to-delete', () {
    testWidgets('swiping a standalone mail moves it to trash with undo', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      // A non-thread-relevant, non-pinned mail near the top.
      final target = repo.getEmailsInFolder(MailFolder.inbox).first;

      await tester.scrollUntilVisible(find.text(target.subject), 200);
      await tester.pumpAndSettle();
      await _swipeLeft(tester, find.text(target.subject));

      // Moved to trash; the row disappears; user is offered undo.
      expect(find.text('1 e-posta silindi'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
      expect(find.text(target.subject), findsNothing);
      expect(
        repo.getEmailsInFolder(MailFolder.trash).map((e) => e.id),
        contains(target.id),
      );

      // Undo restores the mail to its previous folder and re-shows the row.
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(
        repo.getEmailsInFolder(target.folder).map((e) => e.id),
        contains(target.id),
      );
      expect(find.text(target.subject), findsOneWidget);
    });

    testWidgets('swiping a conversation moves every member to trash', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final thread = repo.getThreadEmails('thread-onboarding');
      expect(thread.length, greaterThan(1));

      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      await _swipeLeft(tester, find.text('Re: Design review: onboarding flow'));

      expect(find.text('Re: Design review: onboarding flow'), findsNothing);
      expect(
        repo
            .getThreadEmails('thread-onboarding')
            .every((e) => e.folder == MailFolder.trash),
        isTrue,
      );

      // Undo puts every member back where it was.
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      final sent = repo.getEmailsInFolder(MailFolder.sent);
      expect(inbox.map((e) => e.id), contains('seed-alice-onboarding'));
      expect(sent.map((e) => e.id), contains('seed-sent-onboarding'));
    });

    testWidgets('swipe keeps standing messages intact', (tester) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final standing = repo.getEmailsInFolder(MailFolder.inbox).first;

      await tester.scrollUntilVisible(find.text(standing.subject), 200);
      await tester.pumpAndSettle();
      await _swipeLeft(tester, find.text(standing.subject));

      // Labels/read/star/pin survive a trash+undo round trip.
      final before = repo.getAllEmails().firstWhere((e) => e.id == standing.id);

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      final after = repo.getAllEmails().firstWhere((e) => e.id == standing.id);
      expect(after.labelIds, before.labelIds);
      expect(after.isRead, before.isRead);
      expect(after.isPinned, before.isPinned);
      expect(after.isStarred, before.isStarred);
    });

    testWidgets('swipe-to-delete off: dragging a row leaves it in place', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      await _disableSwipe(tester);

      final target = repo.getEmailsInFolder(MailFolder.inbox).first;
      await tester.scrollUntilVisible(find.text(target.subject), 200);
      await tester.pumpAndSettle();

      await tester.drag(find.text(target.subject), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text(target.subject), findsOneWidget);
      expect(
        repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
        contains(target.id),
      );
    });
  });

  group('swipe-to-archive', () {
    testWidgets('swiping right archives with undo and does not delete', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final target = repo.getEmailsInFolder(MailFolder.inbox).first;

      await tester.scrollUntilVisible(find.text(target.subject), 200);
      await tester.pumpAndSettle();
      await _swipeRight(tester, find.text(target.subject));

      expect(find.text('1 e-posta arşivlendi'), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
      expect(find.text(target.subject), findsNothing);
      expect(
        repo.getEmailsInFolder(MailFolder.archive).map((e) => e.id),
        contains(target.id),
      );
      // Right swipe archives — it must not delete.
      expect(
        repo.getEmailsInFolder(MailFolder.trash).map((e) => e.id),
        isNot(contains(target.id)),
      );

      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(
        repo.getEmailsInFolder(target.folder).map((e) => e.id),
        contains(target.id),
      );
      expect(find.text(target.subject), findsOneWidget);
    });

    testWidgets('swiping left does not archive', (tester) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final target = repo.getEmailsInFolder(MailFolder.inbox).first;

      await tester.scrollUntilVisible(find.text(target.subject), 200);
      await tester.pumpAndSettle();
      await _swipeLeft(tester, find.text(target.subject));

      expect(find.text('1 e-posta silindi'), findsOneWidget);
      expect(
        repo.getEmailsInFolder(MailFolder.archive).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });

    testWidgets('swiping a conversation right archives every member', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final thread = repo.getThreadEmails('thread-onboarding');
      expect(thread.length, greaterThan(1));

      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      await _swipeRight(
        tester,
        find.text('Re: Design review: onboarding flow'),
      );

      expect(find.text('Re: Design review: onboarding flow'), findsNothing);
      expect(
        repo
            .getThreadEmails('thread-onboarding')
            .every((e) => e.folder == MailFolder.archive),
        isTrue,
      );

      // One Undo restores every member to its previous folder.
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      final sent = repo.getEmailsInFolder(MailFolder.sent);
      expect(inbox.map((e) => e.id), contains('seed-alice-onboarding'));
      expect(sent.map((e) => e.id), contains('seed-sent-onboarding'));
    });

    testWidgets('swipe off: dragging right also leaves the row in place', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      await _disableSwipe(tester);

      final target = repo.getEmailsInFolder(MailFolder.inbox).first;
      await tester.scrollUntilVisible(find.text(target.subject), 200);
      await tester.pumpAndSettle();

      await tester.drag(find.text(target.subject), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(find.text(target.subject), findsOneWidget);
      expect(
        repo.getEmailsInFolder(MailFolder.archive).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });
  });
}
