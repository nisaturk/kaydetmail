import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/widgets/mail_avatar.dart';

/// Widget-level account + regression tests (spec §21 items 28–35 and the
/// UI flows): drawer → Hesaplar → add → switch → unified, star/pin
/// persistence across navigation, all-account search, unified bulk actions,
/// compose account picker and settings.
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

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Gezinme menüsünü aç'));
  await tester.pumpAndSettle();
}

/// Taps a drawer entry scoped to the drawer itself, so folder labels that
/// also appear in the app bar behind the scrim stay unambiguous.
Future<void> _tapDrawerItem(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(Drawer), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Connects nisa@outlook.com through the real UI flow and lands back on the
/// accounts list with two connected accounts.
Future<void> _connectOutlook(WidgetTester tester) async {
  await _openDrawer(tester);
  await tester.tap(find.text('Hesaplar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Yeni hesap ekle'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('new-email-field')),
    'nisa@outlook.com',
  );
  await tester.tap(find.byKey(const Key('connect-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppConfig.resetForTest());

  group('accounts UI', () {
    testWidgets('drawer opens the accounts screen with one account', (
      tester,
    ) async {
      await _login(tester);
      await _openDrawer(tester);

      expect(find.text('Hesaplar'), findsOneWidget);
      expect(find.text('Tüm Gelen Kutuları'), findsOneWidget);
      await tester.tap(find.text('Hesaplar'));
      await tester.pumpAndSettle();

      expect(find.text('me@kaydet.app'), findsOneWidget);
      expect(find.text('Yeni hesap ekle'), findsOneWidget);
      // Single account: no unified row needed.
      expect(find.text('Tüm Gelen Kutuları'), findsNothing);
    });

    testWidgets('add-account flow connects outlook and switches mailbox', (
      tester,
    ) async {
      await _login(tester);
      await _connectOutlook(tester);

      expect(find.text('nisa@outlook.com'), findsWidgets);
      await tester.tap(find.text('nisa@outlook.com').first);
      await tester.pumpAndSettle();

      // Outlook mailbox: starter mail visible, scope shown in the app bar.
      expect(find.text('Sprint hedefleri netleşti'), findsOneWidget);
      expect(find.text('Invoice #4821 for March'), findsNothing);
      expect(find.text('nisa@outlook.com'), findsWidgets);
    });

    testWidgets('unified inbox shows both mailboxes with account labels', (
      tester,
    ) async {
      await _login(tester);
      await _connectOutlook(tester);
      // connectAccount activates the new account; go unified via the drawer.
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await tester.tap(find.text('Tüm Gelen Kutuları'));
      await tester.pumpAndSettle();

      expect(find.text('Sprint hedefleri netleşti'), findsOneWidget);
      // The primary mailbox mail sits further down the unified list.
      await tester.scrollUntilVisible(
        find.text('Invoice #4821 for March'),
        300,
      );
      await tester.pumpAndSettle();
      expect(find.text('Invoice #4821 for March'), findsOneWidget);
      // The unified rows name the originating mailbox.
      expect(find.text('nisa@outlook.com'), findsWidgets);
    });

    testWidgets('star from detail persists across account switching', (
      tester,
    ) async {
      await _login(tester);
      await _connectOutlook(tester);
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await tester.tap(find.text('Tüm Gelen Kutuları'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Sprint hedefleri netleşti'),
        300,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sprint hedefleri netleşti'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yıldızla'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();

      // Starred mail is in Yıldızlılar (unified scope).
      await _openDrawer(tester);
      await _tapDrawerItem(tester, 'Yıldızlılar');
      expect(find.text('Sprint hedefleri netleşti'), findsOneWidget);

      // outlook scope keeps it…
      await _openDrawer(tester);
      await tester.tap(find.text('Hesaplar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('nisa@outlook.com').first);
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await _tapDrawerItem(tester, 'Yıldızlılar');
      expect(find.text('Sprint hedefleri netleşti'), findsOneWidget);

      // …while the other account is unaffected.
      await _openDrawer(tester);
      await tester.tap(find.text('Hesaplar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('me@kaydet.app').first);
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await _tapDrawerItem(tester, 'Yıldızlılar');
      expect(find.text('Sprint hedefleri netleşti'), findsNothing);
    });
  });

  group('existing functionality with accounts', () {
    testWidgets('search spans accounts while scoped to one', (tester) async {
      await _login(tester);
      await _connectOutlook(tester);
      await tester.tap(find.text('me@kaydet.app').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Ara'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sprint');
      await tester.pump();

      expect(find.text('Sprint hedefleri netleşti'), findsWidgets);
    });

    testWidgets('bulk delete in unified touches only the selected mail', (
      tester,
    ) async {
      await _login(tester);
      await _connectOutlook(tester);
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await tester.tap(find.text('Tüm Gelen Kutuları'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MailAvatar).first);
      await tester.pump();
      expect(find.textContaining('seçili'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      // The other mailbox is intact.
      expect(find.text('Invoice #4821 for March'), findsOneWidget);
    });

    testWidgets('compose Kimden picker lists the connected accounts', (
      tester,
    ) async {
      await _login(tester);
      await _connectOutlook(tester);
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Yeni E-posta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('from-field')));
      await tester.pumpAndSettle();

      expect(find.text('me@kaydet.app'), findsWidgets);
      expect(find.text('nisa@outlook.com'), findsWidgets);
    });

    testWidgets('settings still opens with labels and toggles', (tester) async {
      await _login(tester);
      await _connectOutlook(tester);
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      await tester.tap(find.text('Ayarlar'));
      await tester.pumpAndSettle();

      expect(find.text('Etiketler'), findsOneWidget);
      expect(find.text('Bildirimler'), findsWidgets);
      expect(find.text('İş'), findsOneWidget);
    });
  });
}
