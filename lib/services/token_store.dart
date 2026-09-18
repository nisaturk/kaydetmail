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

class TokenStore {
  TokenStore({TokenStorage? storage})
    : _storage = storage ?? SecureTokenStorage();

  static const _accessTokenKey = 'kaydet.auth.accessToken';
  static const _refreshTokenKey = 'kaydet.auth.refreshToken';
  static const _mailAccountIdKey = 'kaydet.auth.mailAccountId';

  final TokenStorage _storage;

  Future<String?> readAccessToken() => _storage.read(_accessTokenKey);
  Future<String?> readRefreshToken() => _storage.read(_refreshTokenKey);
  Future<String?> readMailAccountId() => _storage.read(_mailAccountIdKey);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String mailAccountId,
  }) async {
    await Future.wait([
      _storage.write(_accessTokenKey, accessToken),
      _storage.write(_refreshTokenKey, refreshToken),
      _storage.write(_mailAccountIdKey, mailAccountId),
    ]);
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(_accessTokenKey),
      _storage.delete(_refreshTokenKey),
      _storage.delete(_mailAccountIdKey),
    ]);
  }
}
