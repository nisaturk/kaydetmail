import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/demo_mail_repository.dart';

class _LabelRepo extends DemoMailRepository {
  final created = <({String name, Color color, String? accountId})>[];
  final updated = <({String id, Color color})>[];
  Object? failWith;

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
    String? accountId,
  }) async {
    if (failWith != null) throw failWith!;
    created.add((name: name, color: color, accountId: accountId));
    return MailLabel(id: 'new', name: name, color: color);
  }

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async => updated.add((id: id, color: color));
}

Future<void> _openLabelEditor(WidgetTester tester, _LabelRepo repo) async {
  tester.view
    ..physicalSize = const Size(800, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppConfig.mailRepositoryForTest = repo;
  await tester.pumpWidget(
    const MaterialApp(home: AccountSettingsScreen(accountId: 'acc-1')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Etiketler'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
  });

  testWidgets('a custom colour picked from the picker is saved with the label', (
    tester,
  ) async {
    final repo = _LabelRepo();
    await _openLabelEditor(tester, repo);

    await tester.tap(find.text('Yeni Etiket'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Fatura');
    await tester.tap(find.byKey(const Key('custom-color-swatch')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('color-picker-hex')),
      '#123ABC',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-picker-confirm')));
    await tester.pumpAndSettle();

    // The chosen colour now shows as its own selected swatch.
    expect(find.byKey(const Key('custom-color-current')), findsOneWidget);

    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    expect(repo.created, hasLength(1));
    expect(repo.created.single.name, 'Fatura');
    expect(repo.created.single.accountId, 'acc-1');
    expect(repo.created.single.color.toARGB32() & 0xFFFFFF, closeTo(0x123ABC, 0x0400));
  });

  testWidgets('cancelling the picker keeps the preset colour', (tester) async {
    final repo = _LabelRepo();
    await _openLabelEditor(tester, repo);

    await tester.tap(find.text('Yeni Etiket'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'İş');
    await tester.tap(find.byKey(const Key('custom-color-swatch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-color-current')), findsNothing);
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    expect(repo.created.single.color, SettingsScreen.labelColors.first);
  });

  testWidgets('a server failure re-enables the form with a message', (
    tester,
  ) async {
    final repo = _LabelRepo()..failWith = Exception('boom');
    await _openLabelEditor(tester, repo);

    await tester.tap(find.text('Yeni Etiket'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Hata');
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();

    // Dialog stays open (not stuck submitting) so the user can retry.
    expect(find.text('Yeni Etiket'), findsWidgets);
    repo.failWith = null;
    await tester.tap(find.text('Oluştur'));
    await tester.pumpAndSettle();
    expect(repo.created, hasLength(1));
  });
}
