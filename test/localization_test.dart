import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/l10n/l10n.dart';
import 'package:kaydetmail/screens/settings_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/utils/date_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/demo_mail_repository.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

final _placeholder = RegExp(r'\{([A-Za-z_]\w*)(?=[},])');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });
  tearDown(() {
    AppSettingsController.resetForTest();
    AppConfig.resetForTest();
  });

  test('Turkish and English define the same messages and placeholders', () {
    final tr = _arb('tr');
    final en = _arb('en');
    final messageKeys = tr.keys.where((k) => !k.startsWith('@'));
    expect(
      en.keys.where((k) => !k.startsWith('@')).toSet(),
      messageKeys.toSet(),
    );
    for (final key in messageKeys) {
      final names = (tr[key] as String)
          .split(RegExp(r'(?=\{)'))
          .expand((part) => _placeholder.allMatches(part))
          .map((m) => m.group(1)!)
          .toSet();
      final englishNames =
          _placeholder
              .allMatches(en[key] as String)
              .map((m) => m.group(1)!)
              .toSet()
            ..removeWhere((n) => n == 'other' || n == 'plural');
      expect(englishNames, names, reason: key);
      expect((en[key] as String).trim(), isNotEmpty, reason: key);
    }
  });

  test('l10nNow follows the chosen language and defaults to Turkish', () {
    expect(l10nNow.inbox, 'Gelen Kutusu');
    AppSettingsController.instance.locale = const Locale('en');
    expect(l10nNow.inbox, 'Inbox');
    expect(l10nNow.emailsDeleted(1), '1 email deleted');
    expect(l10nNow.emailsDeleted(3), '3 emails deleted');
  });

  test('dates use the language of the app', () {
    final time = DateTime(2026, 9, 14, 14, 30);
    expect(formatMailDateFull(time), 'Pzt, 14 Eyl 2026, 14:30');
    AppSettingsController.instance.locale = const Locale('en');
    expect(formatMailDateFull(time), 'Mon, 14 Sep 2026, 14:30');
  });

  test('an unsupported language is ignored', () {
    AppSettingsController.instance.locale = const Locale('de');
    expect(AppSettingsController.instance.locale, const Locale('tr'));
  });

  test('the chosen language is restored from preferences', () async {
    SharedPreferences.setMockInitialValues({'kaydet.language': 'en'});
    await AppSettingsController.instance.loadLanguage();
    expect(AppSettingsController.instance.locale, const Locale('en'));
  });

  testWidgets('choosing a language returns to the settings list in it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppConfig.mailRepositoryForTest = DemoMailRepository();
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: AppSettingsController.instance,
        builder: (_, _) => MaterialApp(
          locale: AppSettingsController.instance.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const GeneralSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Genel ayarlar'), findsOneWidget);

    await tester.tap(find.text('Dil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-en')));
    // The app root does this when the language changes (see _AuthGateState).
    unawaited(tester.binding.reassembleApplication());
    await tester.pumpAndSettle();

    expect(AppSettingsController.instance.locale, const Locale('en'));
    expect(find.text('General settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Dil'), findsNothing);
  });

  testWidgets('the app root reassembles itself when the language changes', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('home_widget/updates'),
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('home_widget/updates'),
        null,
      ),
    );
    AppConfig.mailRepositoryForTest = DemoMailRepository();
    await tester.pumpWidget(const KaydetApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Devam'), findsOneWidget);

    AppSettingsController.instance.locale = const Locale('en');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Devam'), findsNothing);
  });
}
