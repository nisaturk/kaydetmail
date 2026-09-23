import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/rules_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal repository double covering only what [RulesSettingsScreen] and
/// its editor sheet read: the account list/lookup and per-account labels.
/// Every other member is unused by this screen.
class _FakeRepo extends MailRepository {
  _FakeRepo({
    required this.accounts,
    required this.activeAccountId,
    this._labels = const {},
  });

  @override
  final List<MailAccount> accounts;

  @override
  final String? activeAccountId;

  final Map<String, List<MailLabel>> _labels;

  @override
  MailAccount? getAccount(String accountId) {
    for (final account in accounts) {
      if (account.id == accountId) return account;
    }
    return null;
  }

  @override
  List<MailLabel> getLabelsForAccount(String accountId) =>
      _labels[accountId] ?? const [];

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.resetForTest();
    AppConfig.mailRepositoryForTest = _FakeRepo(
      accounts: const [MailAccount(id: 'acc-1', email: 'a@example.com')],
      activeAccountId: 'acc-1',
      labels: const {
        'acc-1': [MailLabel(id: 'l1', name: 'İş', color: Colors.blue)],
      },
    );
  });

  tearDown(AppConfig.resetForTest);

  Widget harness() => const MaterialApp(home: RulesSettingsScreen());

  testWidgets('shows the empty state with no stored rules', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Henüz kural yok'), findsOneWidget);
  });

  testWidgets('creates a move-to-folder rule and lists it', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-rule-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('rule-sender-field')),
      'spam@ornek.com',
    );
    // "Klasöre taşı" is the default action; pick a target folder.
    await tester.tap(find.byKey(const Key('rule-folder-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-folder-trash')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Gönderen adresi "spam@ornek.com" içeriyor'),
      findsOneWidget,
    );
    expect(find.text('Çöp Kutusu klasörüne taşı'), findsOneWidget);
    expect(find.text('Henüz kural yok'), findsNothing);
  });

  testWidgets('creates a label rule, edits it, then deletes it', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-rule-fab')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('rule-sender-field')),
      'bildirim',
    );
    await tester.tap(find.byKey(const Key('rule-action-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-label-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-label-l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('"İş" olarak etiketle'), findsOneWidget);

    // Edit: reopen the same row and change the sender text.
    await tester.tap(find.byTooltip('Düzenle'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rule-sender-field')),
      'fatura',
    );
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Gönderen adresi "fatura" içeriyor'),
      findsOneWidget,
    );

    // Delete: confirm the dialog, back to the empty state.
    await tester.tap(find.byTooltip('Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, sil'));
    await tester.pumpAndSettle();

    expect(find.text('Henüz kural yok'), findsOneWidget);
  });

  testWidgets('save is blocked with an error when the sender field is empty', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('add-rule-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Gönderen adresi/adı boş olamaz.'), findsOneWidget);
    // The sheet stays open — nothing was persisted.
    expect(find.byKey(const Key('rule-save-button')), findsOneWidget);
  });
}
