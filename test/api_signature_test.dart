import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/repositories/api_mail_repository.dart';
import 'package:kaydetmail/services/api_auth_service.dart';
import 'package:kaydetmail/services/api_client.dart';
import 'package:kaydetmail/services/api_mail_service.dart';
import 'package:kaydetmail/services/device_identifier_provider.dart';
import 'package:kaydetmail/services/signature_store.dart';
import 'package:kaydetmail/services/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ApiMailRepository signature', () {
    test('setSignature updates the account and syncs to the backend', () async {
      final service = _FakeMailService(email: 'person@example.com');
      final repo = await _repository(service);

      await repo.setSignature('account-1', 'Saygılarımla,\nKişi');

      expect(service.updatedSignatures, ['Saygılarımla,\nKişi']);
      expect(repo.accounts.single.signature, 'Saygılarımla,\nKişi');
    });

    test('blank signature clears both locally and on the backend', () async {
      final service = _FakeMailService(
        email: 'person@example.com',
        remoteSignature: 'Var olan imza',
      );
      final repo = await _repository(service);
      expect(repo.accounts.single.signature, 'Var olan imza');

      await repo.setSignature('account-1', '   ');

      expect(service.updatedSignatures, [null]);
      expect(repo.accounts.single.signature, isNull);
    });

    test('unknown accountId throws ArgumentError', () async {
      final service = _FakeMailService(email: 'person@example.com');
      final repo = await _repository(service);

      expect(
        () => repo.setSignature('unknown-account', 'x'),
        throwsArgumentError,
      );
    });

    test(
      'login migrates a legacy local signature to the backend exactly once',
      () async {
        SharedPreferences.setMockInitialValues({});
        await SignatureStore.save('legacy@example.com', 'Eski cihaz imzası');
        final service = _FakeMailService(email: 'legacy@example.com');

        final repo = await _repository(service);
        // _migrateLegacySignature runs unawaited off session activation.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(service.updatedSignatures, ['Eski cihaz imzası']);
        expect(repo.accounts.single.signature, 'Eski cihaz imzası');
        expect(await SignatureStore.load('legacy@example.com'), '');
      },
    );

    test(
      'login does not overwrite an existing backend signature with a stale local one',
      () async {
        SharedPreferences.setMockInitialValues({});
        await SignatureStore.save('person@example.com', 'Eski cihaz imzası');
        final service = _FakeMailService(
          email: 'person@example.com',
          remoteSignature: 'Sunucu imzası',
        );

        final repo = await _repository(service);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(service.updatedSignatures, isEmpty);
        expect(repo.accounts.single.signature, 'Sunucu imzası');
      },
    );
  });
}

Future<ApiMailRepository> _repository(_FakeMailService service) async {
  final tokenStore = TokenStore(storage: _MemoryTokenStorage());
  await tokenStore.save(
    accountId: 'account-1',
    accessToken: 'access',
    refreshToken: 'refresh',
  );
  final authService = ApiAuthService(
    client: ApiClient(
      tokenStore: tokenStore,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    ),
    tokenStore: tokenStore,
    deviceIdentifierProvider: const MemoryDeviceIdentifierProvider('device-1'),
  );
  final repo = ApiMailRepository(authService: authService, mailService: service);
  await repo.restoreSession(service.email);
  return repo;
}

class _FakeMailService extends ApiMailService {
  _FakeMailService({required this.email, this.remoteSignature})
    : super(ApiClient(tokenStore: TokenStore(storage: _MemoryTokenStorage())));

  final String email;
  String? remoteSignature;
  final List<String?> updatedSignatures = [];

  @override
  Future<MailAccount> getAccount() async =>
      MailAccount(id: 'account-1', email: email, signature: remoteSignature);

  @override
  Future<void> updateSignature(String? signature) async {
    updatedSignatures.add(signature);
    remoteSignature = signature;
  }

  @override
  Future<List<ApiMailFolder>> getFolders() async => const [];
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
