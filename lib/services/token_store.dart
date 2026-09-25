import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TokenStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Per-account credential storage. Every connected mailbox gets its own
/// access/refresh token pair under a namespaced key, so multiple accounts
/// hold independent, simultaneously-valid sessions on this device —
/// connecting a second account never evicts the first one's tokens.
///
/// [readAccountIds] is the source of truth for "which accounts are
/// currently connected on this device"; an id is removed only by [clear].
class TokenStore {
  TokenStore({TokenStorage? storage})
    : _storage = storage ?? SecureTokenStorage();

  static const _accountIdsKey = 'kaydet.auth.accountIds';

  // Pre-multi-account keys. Migrated into the namespaced scheme below the
  // first time this device's accounts are read, then removed — an upgrading
  // install keeps its one already-connected account.
  static const _legacyAccessTokenKey = 'kaydet.auth.accessToken';
  static const _legacyRefreshTokenKey = 'kaydet.auth.refreshToken';
  static const _legacyMailAccountIdKey = 'kaydet.auth.mailAccountId';

  final TokenStorage _storage;
  bool _legacyMigrated = false;

  String _accessKey(String accountId) => 'kaydet.auth.$accountId.accessToken';
  String _refreshKey(String accountId) => 'kaydet.auth.$accountId.refreshToken';

  Future<List<String>> _readAccountIdsRaw() async {
    final raw = await _storage.read(_accountIdsKey);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> _migrateLegacyOnce() async {
    if (_legacyMigrated) return;
    _legacyMigrated = true;
    final legacyAccess = await _storage.read(_legacyAccessTokenKey);
    final legacyRefresh = await _storage.read(_legacyRefreshTokenKey);
    final legacyAccountId = await _storage.read(_legacyMailAccountIdKey);
    if (legacyAccess != null &&
        legacyRefresh != null &&
        legacyAccountId != null) {
      final ids = await _readAccountIdsRaw();
      if (!ids.contains(legacyAccountId)) {
        await _storage.write(
          _accountIdsKey,
          jsonEncode([...ids, legacyAccountId]),
        );
      }
      await _storage.write(_accessKey(legacyAccountId), legacyAccess);
      await _storage.write(_refreshKey(legacyAccountId), legacyRefresh);
    }
    await Future.wait([
      _storage.delete(_legacyAccessTokenKey),
      _storage.delete(_legacyRefreshTokenKey),
      _storage.delete(_legacyMailAccountIdKey),
    ]);
  }

  /// Every account id with stored credentials, in the order they were first
  /// connected — also the order accounts restore in at app launch.
  Future<List<String>> readAccountIds() async {
    await _migrateLegacyOnce();
    return _readAccountIdsRaw();
  }

  Future<String?> readAccessToken(String accountId) =>
      _storage.read(_accessKey(accountId));

  Future<String?> readRefreshToken(String accountId) =>
      _storage.read(_refreshKey(accountId));

  Future<void> save({
    required String accountId,
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(_accessKey(accountId), accessToken),
      _storage.write(_refreshKey(accountId), refreshToken),
    ]);
    final ids = await readAccountIds();
    if (!ids.contains(accountId)) {
      await _storage.write(_accountIdsKey, jsonEncode([...ids, accountId]));
    }
  }

  /// Drops one account's credentials. Every other connected account's
  /// tokens are untouched.
  Future<void> clear(String accountId) async {
    await Future.wait([
      _storage.delete(_accessKey(accountId)),
      _storage.delete(_refreshKey(accountId)),
    ]);
    final ids = await readAccountIds();
    if (ids.remove(accountId)) {
      await _storage.write(_accountIdsKey, jsonEncode(ids));
    }
  }
}
