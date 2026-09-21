import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';

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

Future<void> _openDrafts(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Gezinme menüsünü aç'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Taslaklar'));
  await tester.pumpAndSettle();
}

/// The compose body field is the last TextField on the editor surface.
Future<void> _editBody(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
}

void main() {
  setUp(() => AppConfig.resetForTest());

  group('draft editing (repository)', () {
    test(
      'saveDraft with a draftId updates the same draft, deleteDraft removes it',
      () async {
        final repo = AppConfig.mailRepository;
        final original = repo.getEmailsInFolder(MailFolder.drafts).first;

        final saved = await repo.saveDraft(
          to: original.recipients,
          cc: original.cc,
          bcc: original.bcc,
          subject: original.subject,
          body: 'Güncellendi.',
          attachments: original.attachments,
          draftId: original.id,
        );
        expect(saved.id, original.id);
        expect(saved.bodyText, 'Güncellendi.');
        expect(
          repo
              .getEmailsInFolder(MailFolder.drafts)
              .where((e) => e.id == original.id)
              .length,
          1,
          reason: 'saving an edited draft must not create a duplicate',
        );

        await repo.deleteDraft(original.id);
        expect(
          repo
              .getEmailsInFolder(MailFolder.drafts)
              .any((e) => e.id == original.id),
          isFalse,
        );
      },
    );
  });

  group('draft editing (widget)', () {
    testWidgets('tapping a draft opens the editor prefilled', (tester) async {
      await _login(tester);
      await _openDrafts(tester);

      await tester.tap(find.text('Draft: Budget proposal'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(3)); // to, subject, body
      expect(find.text('Taslağı Düzenle'), findsOneWidget);
      expect(find.text('h2-budget-draft.xlsx'), findsOneWidget);

      // Fields carry the draft's values.
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.first.controller!.text, 'finance@northstar.io');
      expect(fields[1].controller!.text, 'Draft: Budget proposal');
      expect(
        fields[2].controller!.text,
        contains('first pass at the H2 budget'),
      );
    });

    testWidgets('saving an edited draft keeps its id and updates the content', (
      tester,
    ) async {
      await _login(tester);
      await _openDrafts(tester);

      await tester.tap(find.text('Draft: Budget proposal'));
      await tester.pumpAndSettle();
      await _editBody(tester, 'Yeni halini buradan okuyun.');
      await tester.pump();

      // Smart-back dialog: close with "Taslağı Kaydet".
      await tester.tap(find.byTooltip('Kapat'));
      await tester.pumpAndSettle();
      expect(find.text('Bu e-posta silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('Taslağı Kaydet'));
      await tester.pumpAndSettle();

      final repo = AppConfig.mailRepository;
      final stored = repo
          .getEmailsInFolder(MailFolder.drafts)
          .firstWhere((e) => e.id == 'seed-draft-budget');
      expect(stored.bodyText, 'Yeni halini buradan okuyun.');
      expect(
        repo
            .getEmailsInFolder(MailFolder.drafts)
            .where((e) => e.id == 'seed-draft-budget')
            .length,
        1,
        reason: 'saving an edited draft must not create a duplicate',
      );
    });

    testWidgets('sending an edited draft files it out of Drafts', (
      tester,
    ) async {
      await _login(tester);
      await _openDrafts(tester);

      await tester.tap(find.text('Weekend plans'));
      await tester.pumpAndSettle();
      await _editBody(tester, 'Saat belli olunca yazarım.');
      await tester.tap(find.byTooltip('Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final repo = AppConfig.mailRepository;
      expect(
        repo
            .getEmailsInFolder(MailFolder.drafts)
            .any((e) => e.id == 'seed-draft-weekend'),
        isFalse,
      );
      final sent = repo
          .getEmailsInFolder(MailFolder.sent)
          .firstWhere((e) => e.subject == 'Weekend plans');
      expect(sent.bodyText, contains('Saat belli olunca yazarım.'));
      expect(sent.folder, MailFolder.sent);
    });
  });
}
