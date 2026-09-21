import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/widgets/chat_thread.dart';

Email _mail(String id, String from, DateTime at, String body) => Email(
  id: id,
  senderName: from.split('@').first,
  senderEmail: from,
  recipients: const ['x@y.com'],
  subject: 's',
  bodyText: body,
  timestamp: at,
);

void main() {
  const me = 'me@a.com';
  final day1 = DateTime(2026, 9, 1, 10);
  final day2 = DateTime(2026, 9, 2, 9);

  Future<void> pump(
    WidgetTester tester,
    List<Email> messages, [
    List<String>? opened,
  ]) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatThread(
              messages: messages,
              isOwn: (e) => e.senderEmail == me,
              onOpen: (e) => opened?.add(e.id),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('own messages align right, others left', (tester) async {
    await pump(tester, [
      _mail('1', 'bob@b.com', day1, 'selam'),
      _mail('2', me, day1.add(const Duration(minutes: 5)), 'merhaba'),
    ]);
    final width = tester.getSize(find.byType(MaterialApp)).width;
    debugPrint(
      'W=$width chat=${tester.getSize(find.byType(ChatThread))} m=${tester.getRect(find.text("merhaba"))} s=${tester.getRect(find.text("selam"))}',
    );
    expect(tester.getCenter(find.text('selam')).dx, lessThan(width / 2));
    expect(tester.getCenter(find.text('merhaba')).dx, greaterThan(width / 2));
  });

  testWidgets('same-sender run shows the name once; days get a separator', (
    tester,
  ) async {
    await pump(tester, [
      _mail('1', 'bob@b.com', day1, 'bir'),
      _mail('2', 'bob@b.com', day1.add(const Duration(minutes: 1)), 'iki'),
      _mail('3', 'bob@b.com', day2, 'üç'),
    ]);
    // Grouped on day 1, regrouped on day 2.
    expect(find.text('bob'), findsNWidgets(2));
    expect(find.text('01.09.2026'), findsOneWidget);
    expect(find.text('02.09.2026'), findsOneWidget);
  });

  testWidgets('quoted history is hidden and tap opens the mail', (
    tester,
  ) async {
    final opened = <String>[];
    await pump(tester, [
      _mail('1', 'bob@b.com', day1, 'Tamam.\n> eski alıntı'),
    ], opened);
    expect(find.textContaining('eski alıntı'), findsNothing);
    await tester.tap(find.text('Tamam.'));
    expect(opened, ['1']);
  });
}
