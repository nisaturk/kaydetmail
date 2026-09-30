import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/scheduled_send.dart';
import 'package:kaydetmail/screens/scheduled_sends_screen.dart';
import 'package:kaydetmail/widgets/app_drawer.dart';

import 'support/demo_mail_repository.dart';

class _ScheduledRepo extends DemoMailRepository {
  ScheduledSendStatus status = ScheduledSendStatus.pending;

  @override
  List<ScheduledSend> getScheduledSends() => [
    ScheduledSend(
      id: 'scheduled-1',
      to: const ['recipient@example.com'],
      subject: 'Zamanlanan ileti',
      sendAt: DateTime(2026, 10, 1, 12),
      status: status,
      createdAt: DateTime(2026, 9, 30),
    ),
  ];

  @override
  Future<void> refreshScheduledSends() async {
    await Future<void>.value();
    notifyListeners();
  }
}

void main() {
  tearDown(AppConfig.resetForTest);

  testWidgets('drawer opens scheduled messages with content and outcome', (
    tester,
  ) async {
    final repo = _ScheduledRepo();
    AppConfig.mailRepositoryForTest = repo;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            drawer: AppDrawer(
              selectedFolder: MailFolder.inbox,
              onSelectFolder: (_) {},
              onLogout: () {},
              onSyncAccounts: () {},
              onAddAccount: () {},
              onSelectCustomFolder: (_) {},
              onOpenDestination: (destination) {
                Navigator.of(context).pop();
                if (destination == DrawerDestination.scheduled) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScheduledSendsScreen(),
                    ),
                  );
                }
              },
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zamanlanmış Gönderimler'));
    await tester.pumpAndSettle();
    expect(find.text('Zamanlanan ileti'), findsOneWidget);
    expect(find.text('recipient@example.com'), findsOneWidget);
    expect(find.textContaining('Zamanlandı'), findsOneWidget);

    repo.status = ScheduledSendStatus.sent;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.textContaining('Gönderildi'), findsOneWidget);
    expect(find.textContaining('Zamanlandı'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
