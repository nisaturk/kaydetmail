import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/theme/app_theme.dart';
import 'package:kaydetmail/widgets/mail_list_item.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Email _unread(MailFolder folder) => Email(
  id: 'm1',
  senderName: 'Ben',
  senderEmail: 'me@example.com',
  recipients: const ['other@example.com'],
  subject: 'Konu',
  bodyText: 'Gövde',
  timestamp: DateTime(2026, 9, 27),
  isRead: false,
  folder: folder,
);

Future<void> _pump(WidgetTester tester, Email email) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: MailListItem(email: email)),
  ),
);

void main() {
  testWidgets('an unread draft shows no read state', (tester) async {
    await _pump(tester, _unread(MailFolder.drafts));

    expect(find.byIcon(LucideIcons.mail), findsNothing);
    expect(find.byIcon(LucideIcons.mailOpen), findsNothing);
    final subject = tester.widget<Text>(find.text('Konu'));
    expect(subject.style?.fontWeight, FontWeight.w400);
    expect(
      tester.getSemantics(find.byType(MailListItem)).label,
      isNot(contains('okun')),
    );
  });

  testWidgets('an unread inbox mail still shows it is unread', (tester) async {
    await _pump(tester, _unread(MailFolder.inbox));

    expect(find.byIcon(LucideIcons.mail), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(MailListItem)).label,
      contains('okunmadı'),
    );
  });
}
