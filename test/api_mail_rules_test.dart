import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_rule.dart';
import 'package:kaydetmail/models/server_mail_rule.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/local_mail_flags_store.dart';
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/mail_rules_store.dart';
import 'package:kaydetmail/services/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'legacy rules migrate once with backend labels and semantic folder actions',
    () async {
      final cache = MailCache.inMemory();
      await LocalMailFlagsStore('account-1', cache).writeLabelDefs([
        {'id': 'old-label', 'name': 'İş', 'color': 1},
      ]);
      await MailRulesStore.writeRules('account-1', [
        MailRule(
          id: 'legacy-label',
          condition: MailRuleCondition.senderContains('boss'),
          action: MailRuleAction.addLabel('old-label'),
        ),
        MailRule(
          id: 'legacy-move',
          condition: MailRuleCondition.senderContains('promo'),
          action: MailRuleAction.moveToFolder(MailFolder.archive),
        ),
      ]);
      final service = _RulesMailService()..failCreateFor = 'legacy-move';
      final repo = await _repository(service, cache);

      await expectLater(
        repo.listRules('account-1'),
        throwsA(isA<ApiException>()),
      );
      expect((await MailRulesStore.readRules('account-1')).map((r) => r.id), [
        'legacy-move',
      ]);

      service.failCreateFor = null;
      final rules = await repo.listRules('account-1');

      expect(rules, hasLength(2));
      expect(service.createdLegacyIds, ['legacy-label', 'legacy-move']);
      expect(rules.first.actions.single.labelId, 'server-label');
      expect(rules.last.actions.single.type, 'archive');
      expect(rules.map((r) => r.priority), [0, 1]);
      expect(await MailRulesStore.readRules('account-1'), isEmpty);
      await repo.listRules('account-1');
      expect(service.createdLegacyIds, hasLength(2));
    },
  );

  test(
    'unmappable legacy label rule stays on device with a visible error',
    () async {
      final cache = MailCache.inMemory();
      await MailRulesStore.writeRules('account-1', [
        MailRule(
          id: 'legacy-orphan',
          condition: MailRuleCondition.senderContains('x'),
          action: MailRuleAction.addLabel('deleted-label'),
        ),
      ]);
      final service = _RulesMailService();
      final repo = await _repository(service, cache);

      await expectLater(repo.listRules('account-1'), throwsStateError);
      expect(service.createdLegacyIds, isEmpty);
      expect(
        (await MailRulesStore.readRules('account-1')).single.id,
        'legacy-orphan',
      );
    },
  );
}

Future<ApiMailRepository> _repository(
  _RulesMailService service,
  MailCache cache,
) async {
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  await tokenStore.save(
    accountId: 'account-1',
    accessToken: 'access',
    refreshToken: 'refresh',
  );
  final repo = ApiMailRepository(
    authService: ApiAuthService(
      client: ApiClient(
        tokenStore: tokenStore,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      ),
      tokenStore: tokenStore,
      deviceIdentifierProvider: const MemoryDeviceIdentifierProvider('device'),
    ),
    mailService: service,
    openCache: () async => cache,
  );
  await repo.restoreSession('person@example.com');
  return repo;
}

class _RulesMailService extends ApiMailService {
  _RulesMailService()
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final List<ServerMailRule> rules = [];
  final List<String> createdLegacyIds = [];
  String? failCreateFor;

  @override
  Future<List<ApiMailFolder>> getFolders() async => [
    ApiMailFolder(
      id: 'folder-inbox',
      mailAccountId: 'account-1',
      name: 'Inbox',
      type: 'Inbox',
    ),
    ApiMailFolder(
      id: 'folder-archive',
      mailAccountId: 'account-1',
      name: 'Archive',
      type: 'Archive',
    ),
  ];

  @override
  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    bool? hasAttachments,
    String? search,
  }) async =>
      MailListPage(items: const [], page: page, pageSize: pageSize, total: 0);

  @override
  Future<List<Map<String, dynamic>>> getLabels() async => [
    {'id': 'server-label', 'name': 'iş', 'color': 1, 'sortOrder': 0},
  ];

  @override
  Future<Map<String, List<String>>> getLabelAssignments() async => {};

  @override
  Future<List<ServerMailRule>> getRules() async => List.of(rules);

  @override
  Future<ServerMailRule> createRule(
    ServerMailRule rule, {
    String? legacyId,
  }) async {
    if (legacyId == failCreateFor) throw const ApiException(status: 503);
    final existing = rules.indexWhere((r) => r.id == 'rule-$legacyId');
    if (existing >= 0) return rules[existing];
    createdLegacyIds.add(legacyId!);
    final saved = ServerMailRule(
      id: 'rule-$legacyId',
      name: rule.name,
      enabled: rule.enabled,
      priority: rule.priority,
      logic: rule.logic,
      conditions: rule.conditions,
      actions: rule.actions,
    );
    rules.add(saved);
    return saved;
  }
}

class _MemoryTokenStorage implements TokenStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
