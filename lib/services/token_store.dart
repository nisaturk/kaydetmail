import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'kaydet.api.accessToken';
  static const _refreshKey = 'kaydet.api.refreshToken';
  static const _accountIdKey = 'kaydet.api.mailAccountId';

  final FlutterSecureStorage _storage;

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);
  Future<String?> readMailAccountId() => _storage.read(key: _accountIdKey);

  Future<void> save({
    required String accessToken,
    required String refreshToken,
    String? mailAccountId,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    if (mailAccountId == null || mailAccountId.isEmpty) {
      await _storage.delete(key: _accountIdKey);
    } else {
      await _storage.write(key: _accountIdKey, value: mailAccountId);
    }
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
      _storage.delete(key: _accountIdKey),
    ]);
  }
}
