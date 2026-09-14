import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/widgets/mail_avatar.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const KaydetApp());
  await tester.enterText(find.byKey(const Key('email-field')), 'me@kaydet.app');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('password-field')), 'secret123');
  await tester.tap(find.byKey(const Key('signin-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppConfig.resetForTest());

  testWidgets('avatar tap enters selection mode and shows the selection bar',
      (tester) async {
    await _login(tester);

    await tester.tap(find.byType(MailAvatar).first);
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('select all selects every visible mail', (tester) async {
    await _login(tester);

    await tester.tap(find.byType(MailAvatar).first);
    await tester.pump();
    await tester.tap(find.text('Select all'));
    await tester.pump();

    expect(find.text('1 selected'), findsNothing);
    expect(find.textContaining('selected'), findsOneWidget);
  });

  testWidgets('tapping a mail opens the detail screen', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Fixing the CI pipeline'));
    await tester.pumpAndSettle();

    expect(find.text('Fixing the CI pipeline'), findsOneWidget);
    expect(find.text('David Chen'), findsWidgets);
    expect(find.textContaining('To:'), findsOneWidget);
  });

  testWidgets('search filters mails as you type', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pump();

    expect(find.text('Invoice #4821 for March'), findsOneWidget);
    expect(find.text('Fixing the CI pipeline'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pump();
    expect(find.textContaining('No results'), findsOneWidget);
  });

  testWidgets('FAB opens the compose screen', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();

    expect(find.text('New mail'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
  });

  testWidgets('bulk delete moves mail to trash', (tester) async {
    await _login(tester);

    final beforeTrash = AppConfig.mailRepository
        .getEmailsInFolder(MailFolder.trash)
        .length;

    // Enter selection mode
    await tester.tap(find.byType(MailAvatar).first);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    // Tap Delete in the bottom bar
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Back to normal mode
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);

    final afterTrash = AppConfig.mailRepository
        .getEmailsInFolder(MailFolder.trash)
        .length;
    expect(afterTrash, beforeTrash + 1);
  });

  testWidgets('compose send validates To field', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Compose'));
    await tester.pumpAndSettle();

    // Try to send without a recipient
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();

    expect(find.text('At least one recipient is required.'), findsOneWidget);
    expect(find.text('Inbox'), findsNothing); // still on compose
  });
}