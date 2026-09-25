import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/account_sync_scope.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/server_mail_rule.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/rules_settings_screen.dart';

class _FakeRepo extends MailRepository {
  _FakeRepo();

  final stored = <String, List<ServerMailRule>>{'acc-1': [], 'acc-2': []};
  bool failLoad = false;

  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'acc-1', email: 'first@example.test'),
    MailAccount(id: 'acc-2', email: 'second@example.test'),
  ];

  @override
  String? get activeAccountId => 'acc-1';

  @override
  MailAccount? getAccount(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  @override
  List<MailLabel> getLabelsForAccount(String id) => id == 'acc-1'
      ? const [MailLabel(id: 'label-1', name: 'İş', color: Colors.blue)]
      : const [];

  @override
  Future<AccountSyncScope> getSyncScope(String id) async =>
      const AccountSyncScope(
        scope: FolderSyncScope.inboxAndSent,
        folders: [
          SyncScopeFolder(
            id: 'folder-1',
            name: 'Archive',
            type: 'Archive',
            synced: true,
          ),
        ],
      );

  @override
  Future<List<ServerMailRule>> listRules(String id) async {
    if (failLoad) {
      throw StateError(
        'Eski kuralın etiketi bulunamadı. Kural cihazda korundu.',
      );
    }
    return List.of(stored[id]!);
  }

  @override
  Future<ServerMailRule> createRule(String id, ServerMailRule rule) async {
    final saved = ServerMailRule(
      id: 'new-${stored[id]!.length}',
      name: rule.name,
      enabled: rule.enabled,
      priority: rule.priority,
      logic: rule.logic,
      conditions: rule.conditions,
      actions: rule.actions,
    );
    stored[id]!.add(saved);
    return saved;
  }

  @override
  Future<ServerMailRule> updateRule(String id, ServerMailRule rule) async {
    stored[id]![stored[id]!.indexWhere((item) => item.id == rule.id)] = rule;
    return rule;
  }

  @override
  Future<void> deleteRule(String id, String ruleId) async =>
      stored[id]!.removeWhere((rule) => rule.id == ruleId);

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeRepo repo;

  setUp(() {
    AppConfig.resetForTest();
    repo = _FakeRepo();
    AppConfig.mailRepositoryForTest = repo;
  });
  tearDown(AppConfig.resetForTest);

  testWidgets('creates, edits, disables and deletes a server rule', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RulesSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Henüz kural yok'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-rule-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-name')), 'Bültenler');
    await tester.enterText(find.byKey(const Key('rule-priority')), '4');
    await tester.enterText(
      find.byKey(const Key('condition-value-0')),
      'offers',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();
    expect(repo.stored['acc-1']!.single.conditions.single.value, 'offers');
    expect(repo.stored['acc-1']!.single.priority, 4);
    expect(find.text('Bültenler'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(repo.stored['acc-1']!.single.enabled, false);
    await tester.tap(find.byTooltip('Düzenle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-name')), 'Faturalar');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-save-button')));
    await tester.pumpAndSettle();
    expect(repo.stored['acc-1']!.single.name, 'Faturalar');
    expect(repo.stored['acc-1']!.single.enabled, false);

    await tester.tap(find.byTooltip('Sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, sil'));
    await tester.pumpAndSettle();
    expect(repo.stored['acc-1'], isEmpty);
    expect(find.text('Henüz kural yok'), findsOneWidget);
  });

  testWidgets(
    'account switch isolates rules and a migration error stays visible',
    (tester) async {
      repo.stored['acc-2']!.add(
        const ServerMailRule(
          id: 'other',
          name: 'Diğer hesap',
          enabled: true,
          priority: 0,
          logic: 'Or',
          conditions: [RuleCondition('hasAttachment')],
          actions: [RuleAction('star')],
        ),
      );
      repo.failLoad = true;
      await tester.pumpWidget(const MaterialApp(home: RulesSettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kural cihazda korundu'), findsOneWidget);
      expect(find.byKey(const Key('add-rule-fab')), findsNothing);

      repo.failLoad = false;
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rules-account-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('second@example.test'));
      await tester.pumpAndSettle();
      expect(find.text('Diğer hesap'), findsOneWidget);
      expect(repo.stored['acc-1'], isEmpty);
    },
  );
}
