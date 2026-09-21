import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/widgets/mail_avatar.dart';

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

void main() {
  setUp(() => AppConfig.resetForTest());

  testWidgets('tapping an avatar does NOT enter selection mode', (
    tester,
  ) async {
    await _login(tester);

    await tester.tap(find.byType(MailAvatar).first);
    await tester.pump();

    expect(find.textContaining('seçili'), findsNothing);
    expect(find.text('Gelen Kutusu'), findsOneWidget);
  });

  testWidgets(
    'long-pressing an avatar enters selection mode with a top toolbar',
    (tester) async {
      await _login(tester);

      await tester.longPress(find.byType(MailAvatar).first);
      await tester.pump();

      expect(find.text('1 seçili'), findsOneWidget);
      expect(find.text('Tümünü seç'), findsOneWidget);

      // Bulk actions live in the top toolbar — never as a bottom bar.
      expect(find.byTooltip('Sil'), findsOneWidget);
      expect(find.byTooltip('Arşivle'), findsOneWidget);
      expect(find.byTooltip('Etiketle'), findsOneWidget);
      expect(find.text('Sil'), findsNothing);
      expect(find.text('Arşivle'), findsNothing);
      expect(find.text('Etiketle'), findsNothing);

      // Single-message actions stay out of the selection toolbar.
      expect(find.text('Okundu'), findsNothing);
      expect(find.text('Okunmadı'), findsNothing);
      expect(find.text('Yıldızla'), findsNothing);
      expect(find.text('Sabitle'), findsNothing);
      expect(find.text('Taşı'), findsNothing);

      await tester.tap(find.byTooltip('Seçimi iptal et'));
      await tester.pump();
      expect(find.text('Gelen Kutusu'), findsOneWidget);
      expect(find.text('1 seçili'), findsNothing);
    },
  );

  testWidgets('select all selects every visible mail', (tester) async {
    await _login(tester);

    await tester.longPress(find.byType(MailAvatar).first);
    await tester.pump();
    await tester.tap(find.text('Tümünü seç'));
    await tester.pump();

    expect(find.text('1 seçili'), findsNothing);
    expect(find.textContaining('seçili'), findsOneWidget);
  });

  testWidgets('tapping a mail opens the detail screen', (tester) async {
    await _login(tester);

    await tester.tap(find.text('Fixing the CI pipeline'));
    await tester.pumpAndSettle();

    expect(find.text('Fixing the CI pipeline'), findsOneWidget);
    expect(find.text('David Chen'), findsWidgets);
    expect(find.textContaining('Alıcı:'), findsOneWidget);
  });

  testWidgets('search filters mails as you type', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Ara'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'invoice');
    await tester.pump();

    expect(find.text('Invoice #4821 for March'), findsOneWidget);
    expect(find.text('Fixing the CI pipeline'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz-no-match');
    await tester.pump();
    expect(find.textContaining('sonuç yok'), findsOneWidget);
  });

  testWidgets('FAB opens the compose screen', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Yeni E-posta'));
    await tester.pumpAndSettle();

    expect(find.text('Yeni E-posta'), findsOneWidget);
    expect(find.text('Kimden'), findsOneWidget);
    expect(find.text('Kime'), findsOneWidget);
    expect(find.text('Konu'), findsOneWidget);
  });

  testWidgets('bulk delete moves mail to trash with undo feedback', (
    tester,
  ) async {
    await _login(tester);

    final beforeTrash = AppConfig.mailRepository
        .getEmailsInFolder(MailFolder.trash)
        .length;

    // Enter selection mode with a long press.
    await tester.longPress(find.byType(MailAvatar).first);
    await tester.pump();
    expect(find.text('1 seçili'), findsOneWidget);

    // Tap Delete in the top selection toolbar.
    await tester.tap(find.byTooltip('Sil'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Compact feedback with Undo, then back to normal mode.
    expect(find.text('1 e-posta silindi'), findsOneWidget);
    expect(find.text('Geri al'), findsOneWidget);
    expect(find.text('Gelen Kutusu'), findsOneWidget);
    expect(find.text('1 seçili'), findsNothing);

    final afterTrash = AppConfig.mailRepository
        .getEmailsInFolder(MailFolder.trash)
        .length;
    expect(afterTrash, beforeTrash + 1);

    // Undo restores the mail out of Trash.
    await tester.tap(find.text('Geri al'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      AppConfig.mailRepository.getEmailsInFolder(MailFolder.trash).length,
      beforeTrash,
    );
  });

  testWidgets('bulk archive moves mail to archive with undo feedback', (
    tester,
  ) async {
    await _login(tester);

    await tester.longPress(find.byType(MailAvatar).first);
    await tester.pump();
    expect(find.text('1 seçili'), findsOneWidget);

    await tester.tap(find.byTooltip('Arşivle'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('1 e-posta arşivlendi'), findsOneWidget);
    expect(find.text('Geri al'), findsOneWidget);
    expect(find.text('Gelen Kutusu'), findsOneWidget);

    await tester.tap(find.text('Geri al'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Geri al'), findsNothing);
  });

  testWidgets('compose send validates To field', (tester) async {
    await _login(tester);

    await tester.tap(find.byTooltip('Yeni E-posta'));
    await tester.pumpAndSettle();

    // Try to send without a recipient
    await tester.tap(find.byTooltip('Gönder'));
    await tester.pump();

    expect(find.text('En az bir alıcı yazmalısınız.'), findsOneWidget);
    expect(find.text('Gelen Kutusu'), findsNothing); // still on compose
  });
}
