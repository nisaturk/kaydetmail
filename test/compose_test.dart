import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/screens/compose_screen.dart';

Future<void> _openCompose(
  WidgetTester tester, {
  Future<List<Attachment>?> Function()? picker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ComposeScreen(pickAttachments: picker),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppConfig.resetForTest());

  testWidgets('paperclip shows picked files with name and size', (
    tester,
  ) async {
    await _openCompose(
      tester,
      picker: () async => const [
        Attachment(name: 'report.pdf', sizeBytes: 128 * 1024),
        Attachment(name: 'notes.txt', sizeBytes: 3 * 1024 * 1024),
      ],
    );

    await tester.tap(find.byTooltip('Dosya ekle'));
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('128 KB'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('attach-remove-report.pdf')),
      findsOneWidget,
    );
  });

  testWidgets('an attachment can be removed from the composer', (tester) async {
    await _openCompose(
      tester,
      picker: () async => const [
        Attachment(name: 'keep.pdf', sizeBytes: 1024),
        Attachment(name: 'drop.pdf', sizeBytes: 1024),
      ],
    );

    await tester.tap(find.byTooltip('Dosya ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attach-remove-drop.pdf')));
    await tester.pumpAndSettle();

    expect(find.text('keep.pdf'), findsOneWidget);
    expect(find.text('drop.pdf'), findsNothing);
  });

  testWidgets('send with attachments stores the metadata in the sent mail', (
    tester,
  ) async {
    await _openCompose(
      tester,
      picker: () async => const [
        Attachment(name: 'spec.pdf', sizeBytes: 2048, mimeType: 'pdf'),
      ],
    );

    await tester.enterText(find.byKey(const Key('to-field')), 'a@example.com');
    await tester.enterText(
      find.byKey(const Key('subject-field')),
      'Spec attached',
    );
    await tester.tap(find.byTooltip('Dosya ekle'));
    await tester.pumpAndSettle();
    expect(find.text('spec.pdf'), findsOneWidget);

    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Compose was popped back to where it was pushed from.
    expect(find.text('Yeni E-posta'), findsNothing);

    final sent = AppConfig.mailRepository
        .getEmailsInFolder(MailFolder.sent)
        .firstWhere((e) => e.subject == 'Spec attached');
    expect(sent.attachments.single.name, 'spec.pdf');
    expect(sent.attachments.single.sizeBytes, 2048);
    expect(sent.attachments.single.mimeType, 'pdf');
  });

  testWidgets('attachment-only compose keeps the smart-back draft dialog', (
    tester,
  ) async {
    await _openCompose(
      tester,
      picker: () async => const [
        Attachment(name: 'no-text.pdf', sizeBytes: 4096),
      ],
    );

    await tester.tap(find.byTooltip('Dosya ekle'));
    await tester.pumpAndSettle();

    // Close with content that is only attachments.
    await tester.tap(find.byTooltip('Kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Bu e-posta silinsin mi?'), findsOneWidget);
    expect(find.text('Taslağı Kaydet'), findsOneWidget);

    await tester.tap(find.text('Sil'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni E-posta'), findsNothing);
  });

  testWidgets('cc and bcc stay hidden until requested from the menu', (
    tester,
  ) async {
    await _openCompose(tester);

    expect(find.byKey(const Key('to-field')), findsOneWidget);
    expect(find.byKey(const Key('cc-field')), findsNothing);
    expect(find.byKey(const Key('bcc-field')), findsNothing);
    expect(find.byType(TextField), findsNWidgets(3)); // to, subject, body
    expect(find.byKey(const Key('cc-bcc-menu')), findsOneWidget);
  });

  testWidgets('menu reveals cc and bcc without losing entered values', (
    tester,
  ) async {
    await _openCompose(tester);

    await tester.tap(find.byKey(const Key('cc-bcc-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cc'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cc-field')), findsOneWidget);
    expect(find.byKey(const Key('bcc-field')), findsNothing);

    await tester.enterText(find.byKey(const Key('cc-field')), 'cc@example.com');
    await tester.pump();

    await tester.tap(find.byKey(const Key('cc-bcc-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bcc'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cc-field')), findsOneWidget);
    expect(find.byKey(const Key('bcc-field')), findsOneWidget);
    // Revealing Bcc must not erase the Cc content.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cc-field')))
          .controller!
          .text,
      'cc@example.com',
    );
  });

  testWidgets('long filenames do not overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;

    await _openCompose(
      tester,
      picker: () async => const [
        Attachment(
          name:
              'quarterly-revenue-and-sales-forcecast-report-2026-'
              'with-final-numbers-and-notes-from-the-accounting-team.docx',
          sizeBytes: 7 * 1024 * 1024,
        ),
      ],
    );

    await tester.tap(find.byTooltip('Dosya ekle'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ComposeScreen), findsOneWidget);

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpAndSettle();
  });
}
