import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_rule.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/services/mail_rules_engine.dart';
import 'package:kaydetmail/services/mail_rules_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _email({
  required String id,
  required String senderEmail,
  String senderName = 'Gönderen',
  String accountId = 'acc-1',
  List<String> labelIds = const [],
}) => Email(
  id: id,
  senderName: senderName,
  senderEmail: senderEmail,
  recipients: const ['me@example.com'],
  subject: 'Konu',
  bodyText: 'Gövde',
  timestamp: DateTime(2026, 1, 1),
  accountId: accountId,
  labelIds: labelIds,
);

/// Minimal repository double exercising only the three methods the engine
/// actually calls. Every other member is unused by this test — a real
/// implementation would need the full contract, but forwarding those to
/// [noSuchMethod] keeps this fake honest about what the engine touches.
class _FakeRepo extends MailRepository {
  _FakeRepo(this.inbox);

  List<Email> inbox;
  final List<(List<String> ids, MailFolder folder)> moveCalls = [];
  final List<(List<String> ids, List<String> labelIds)> labelCalls = [];

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      folder == MailFolder.inbox ? List.unmodifiable(inbox) : const [];

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    moveCalls.add((ids, folder));
    inbox = inbox.where((e) => !ids.contains(e.id)).toList();
  }

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    labelCalls.add((emailIds, labelIds));
    inbox = [
      for (final e in inbox)
        emailIds.contains(e.id)
            ? e.copyWith(labelIds: {...e.labelIds, ...labelIds}.toList())
            : e,
    ];
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MailRule JSON', () {
    test('round-trips a moveToFolder rule', () {
      final rule = MailRule(
        id: 'r1',
        condition: MailRuleCondition.senderContains('spam@ornek.com'),
        action: MailRuleAction.moveToFolder(MailFolder.trash),
      );
      final decoded = MailRule.fromJson(rule.toJson());
      expect(decoded.id, 'r1');
      expect(decoded.condition.value, 'spam@ornek.com');
      expect(decoded.action.type, MailRuleActionType.moveToFolder);
      expect(decoded.action.folder, MailFolder.trash);
    });

    test('round-trips an addLabel rule', () {
      final rule = MailRule(
        id: 'r2',
        condition: MailRuleCondition.senderContains('bildirim'),
        action: MailRuleAction.addLabel('label-1'),
      );
      final decoded = MailRule.fromJson(rule.toJson());
      expect(decoded.action.type, MailRuleActionType.addLabel);
      expect(decoded.action.labelId, 'label-1');
    });
  });

  group('MailRuleCondition.matches', () {
    test('matches sender email or name case-insensitively', () {
      final condition = MailRuleCondition.senderContains('AcMe');
      expect(
        condition.matches(_email(id: '1', senderEmail: 'billing@acme.com')),
        isTrue,
      );
      expect(
        condition.matches(
          _email(id: '2', senderEmail: 'x@other.com', senderName: 'Acme Inc'),
        ),
        isTrue,
      );
      expect(
        condition.matches(_email(id: '3', senderEmail: 'x@other.com')),
        isFalse,
      );
    });

    test('never matches an empty value', () {
      final condition = MailRuleCondition.senderContains('   ');
      expect(
        condition.matches(_email(id: '1', senderEmail: 'anyone@example.com')),
        isFalse,
      );
    });
  });

  group('MailRulesStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('CRUD round-trips and stays scoped per account', () async {
      final rule = await MailRulesStore.addRule(
        accountId: 'a',
        condition: MailRuleCondition.senderContains('x'),
        action: MailRuleAction.moveToFolder(MailFolder.archive),
      );
      expect(await MailRulesStore.readRules('a'), [rule]);
      expect(await MailRulesStore.readRules('b'), isEmpty);

      final updated = rule.copyWith(
        action: MailRuleAction.moveToFolder(MailFolder.spam),
      );
      await MailRulesStore.updateRule('a', updated);
      expect((await MailRulesStore.readRules('a')).single.action.folder, MailFolder.spam);

      await MailRulesStore.deleteRule('a', rule.id);
      expect(await MailRulesStore.readRules('a'), isEmpty);
    });

    test('unknown/corrupt storage reads as empty', () async {
      expect(await MailRulesStore.readRules('missing-account'), isEmpty);
    });
  });

  group('MailRulesEngine.evaluateNewMail', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('moves matching inbox mail and leaves the rest', () async {
      await MailRulesStore.addRule(
        accountId: 'acc-1',
        condition: MailRuleCondition.senderContains('newsletter'),
        action: MailRuleAction.moveToFolder(MailFolder.archive),
      );
      final repo = _FakeRepo([
        _email(id: 'm1', senderEmail: 'newsletter@shop.com'),
        _email(id: 'm2', senderEmail: 'friend@example.com'),
      ]);

      await MailRulesEngine.instance.evaluateNewMail(repo);

      expect(repo.moveCalls.length, 1);
      expect(repo.moveCalls.single.$1, ['m1']);
      expect(repo.moveCalls.single.$2, MailFolder.archive);
      expect(repo.inbox.map((e) => e.id), ['m2']);
    });

    test('addLabel is idempotent across repeated ticks', () async {
      await MailRulesStore.addRule(
        accountId: 'acc-1',
        condition: MailRuleCondition.senderContains('bildirim'),
        action: MailRuleAction.addLabel('lbl-1'),
      );
      final repo = _FakeRepo([
        _email(id: 'm1', senderEmail: 'bildirim@servis.com'),
      ]);

      await MailRulesEngine.instance.evaluateNewMail(repo);
      expect(repo.labelCalls.length, 1);
      expect(repo.labelCalls.single.$1, ['m1']);
      expect(repo.labelCalls.single.$2, ['lbl-1']);
      expect(repo.inbox.single.labelIds, ['lbl-1']);

      // Second tick: mail is still in Inbox (label actions don't move it)
      // but already carries the label, so it must not be re-applied.
      await MailRulesEngine.instance.evaluateNewMail(repo);
      expect(repo.labelCalls.length, 1);
    });

    test('rules only apply within their own account', () async {
      await MailRulesStore.addRule(
        accountId: 'acc-1',
        condition: MailRuleCondition.senderContains('promo'),
        action: MailRuleAction.moveToFolder(MailFolder.trash),
      );
      final repo = _FakeRepo([
        _email(id: 'm1', senderEmail: 'promo@shop.com', accountId: 'acc-2'),
      ]);

      await MailRulesEngine.instance.evaluateNewMail(repo);

      expect(repo.moveCalls, isEmpty);
      expect(repo.inbox.map((e) => e.id), ['m1']);
    });

    test('empty inbox is a no-op', () async {
      final repo = _FakeRepo(const []);
      await MailRulesEngine.instance.evaluateNewMail(repo);
      expect(repo.moveCalls, isEmpty);
      expect(repo.labelCalls, isEmpty);
    });
  });
}
