import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/widgets/mail_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Gezinme menüsünü aç'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ayarlar'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
  });

  group('settings: label editor', () {
    testWidgets('creates a label and it appears everywhere', (tester) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.tap(find.text('Yeni Etiket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Proje');
      await tester.tap(find.text('Oluştur'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        AppConfig.mailRepository.getLabels().map((l) => l.name),
        contains('Proje'),
      );
      expect(find.text('Proje'), findsOneWidget);
    });

    testWidgets('renames an existing label', (tester) async {
      await _login(tester);
      await _openSettings(tester);
      final label = AppConfig.mailRepository.getLabels().first;

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, label.name),
          matching: find.byTooltip('Düzenle'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Yeni İsim');
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Yeni İsim'), findsOneWidget);
      expect(find.text(label.name), findsNothing);
      expect(
        AppConfig.mailRepository.getLabels().any((l) => l.id == label.id),
        isTrue,
      );
    });

    testWidgets('rejects a duplicate label name', (tester) async {
      await _login(tester);
      await _openSettings(tester);
      final first = AppConfig.mailRepository.getLabels()[0].name;
      final second = AppConfig.mailRepository.getLabels()[1].name;

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, second),
          matching: find.byTooltip('Düzenle'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, first);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      // Still on the dialog, error shown, label unchanged.
      expect(find.text('Bu isimde bir etiket zaten var.'), findsOneWidget);
      expect(
        AppConfig.mailRepository.getLabels().any((l) => l.name == second),
        isTrue,
      );
    });

    testWidgets('empty label name is rejected', (tester) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.tap(find.text('Yeni Etiket'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.tap(find.text('Oluştur'));
      await tester.pumpAndSettle();

      expect(find.text('Etiket adı boş olamaz.'), findsOneWidget);
    });

    testWidgets('deleting a label removes it and asks for confirmation', (
      tester,
    ) async {
      await _login(tester);
      await _openSettings(tester);
      final label = AppConfig.mailRepository.getLabels().first;

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, label.name),
          matching: find.byTooltip('Düzenle'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.text('Etiketi sil?'), findsOneWidget);
      // Two dialogs overlap, each with its own "Vazgeç" — cancel the top one.
      await tester.tap(find.text('Vazgeç').last);
      await tester.pumpAndSettle();
      // Cancelled: label still there, editor still open.
      expect(
        AppConfig.mailRepository.getLabels().any((l) => l.id == label.id),
        isTrue,
      );

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evet, sil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        AppConfig.mailRepository.getLabels().any((l) => l.id == label.id),
        isFalse,
      );
    });
  });

  group('settings: server + swipe sections', () {
    testWidgets('sunucu adresi section shows the current address', (
      tester,
    ) async {
      await _login(tester);
      await _openSettings(tester);

      expect(find.text('Sunucu adresi'), findsOneWidget);
      expect(find.text('http://localhost:5071'), findsOneWidget);
    });

    testWidgets('a new server address is applied and persisted', (
      tester,
    ) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.tap(find.text('Sunucu adresi'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'https://mail.example.com/',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(
        AppSettingsController.instance.serverBaseUrl,
        'https://mail.example.com',
      );
      expect(find.text('https://mail.example.com'), findsOneWidget);
      expect(
        AppSettingsController.instance.serverBaseUrl,
        'https://mail.example.com',
      );
    });

    testWidgets('kaydırarak sil toggle reflects the setting', (tester) async {
      await _login(tester);
      await _openSettings(tester);

      await tester.scrollUntilVisible(
        find.text('Kaydırarak sil'),
        150,
        scrollable: find.descendant(
          of: find.byKey(const Key('settings-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kaydırarak sil'), findsOneWidget);
      await tester.tap(find.text('Kaydırarak sil'));
      await tester.pumpAndSettle();
      expect(AppSettingsController.instance.swipeDeleteEnabled, isFalse);
    });
  });

  group('individual mail labeling', () {
    testWidgets('labeling a mail from its detail menu applies the label', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      // Pick a readable entry near the top (pinned float to the top).
      await tester.scrollUntilVisible(
        find.text('Invoice #4821 for March'),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice #4821 for March'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Etiketle'));
      await tester.pumpAndSettle();
      expect(find.text('Etiketler'), findsOneWidget);

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Kişisel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final mail = repo.getAllEmails().firstWhere(
        (e) => e.id == 'seed-finance-invoice',
      );
      expect(mail.labelIds, contains('lab-personal'));
    });
  });

  group('bulk label bar', () {
    testWidgets('Etiketle from the bulk bar applies to selected mails', (
      tester,
    ) async {
      await _login(tester);

      // Select a row via avatar long-press; Etiketle lives in the top
      // selection toolbar now.
      await tester.longPress(find.byType(MailAvatar).first);
      await tester.pump();
      expect(find.text('1 seçili'), findsOneWidget);

      await tester.tap(find.byTooltip('Etiketle'));
      await tester.pumpAndSettle();
      expect(find.text('Etiketler'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Seyahat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final repo = AppConfig.mailRepository;
      final selected = repo.getEmailsInFolder(MailFolder.inbox).first;
      expect(selected.labelIds, contains('lab-travel'));
    });
  });
}
