import '../models/mail_account.dart';
import 'api_client.dart';
import 'device_identifier_provider.dart';
import 'token_store.dart';

class DiscoveryResponse {
  const DiscoveryResponse({
    required this.discoveryId,
    required this.email,
    required this.provider,
    required this.authenticationMethods,
    required this.manualSetupAvailable,
  });

  factory DiscoveryResponse.fromJson(Map<String, dynamic> json) =>
      DiscoveryResponse(
        discoveryId: json['discoveryId'] as String,
        email: json['email'] as String,
        provider: AccountProvider.fromBackend(json['provider'] as String),
        authenticationMethods: List<String>.from(
          json['authenticationMethods'] as List,
        ),
        manualSetupAvailable: json['manualSetupAvailable'] as bool,
      );

  final String discoveryId;
  final String email;
  final AccountProvider provider;
  final List<String> authenticationMethods;
  final bool manualSetupAvailable;
}

class TokenResponse {
  const TokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.mailAccountId,
    required this.accessTokenExpiresAt,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    mailAccountId: json['mailAccountId'] as String,
    accessTokenExpiresAt: DateTime.parse(
      json['accessTokenExpiresAt'] as String,
    ),
  );

  final String accessToken;
  final String refreshToken;
  final String mailAccountId;
  final DateTime accessTokenExpiresAt;
}

enum MailSecurity {
  sslOnConnect('SslOnConnect'),
  startTls('StartTls');

  const MailSecurity(this.apiValue);
  final String apiValue;
}

class ManualMailServer {
  const ManualMailServer({
    required this.host,
    required this.port,
    required this.security,
  });

  final String host;
  final int port;
  final MailSecurity security;

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'security': security.apiValue,
  };
}

class ManualConnectionRequest {
  const ManualConnectionRequest({
    required this.email,
    required this.username,
    required this.password,
    required this.imap,
    required this.smtp,
    required this.displayName,
  });

  final String email;
  final String username;
  final String password;
  final ManualMailServer imap;
  final ManualMailServer smtp;
  final String displayName;
}

class ApiAuthService {
  ApiAuthService({
    required this.client,
    required this.tokenStore,
    required this.deviceIdentifierProvider,
  });

  final ApiClient client;
  final TokenStore tokenStore;
  final DeviceIdentifierProvider deviceIdentifierProvider;

  Future<DiscoveryResponse> discover(String email) async {
    final json = await client.postJson('/api/accounts/discover', {
      'email': email,
    }, authenticated: false);
    return DiscoveryResponse.fromJson(json);
  }

  Future<TokenResponse> connect({
    required String discoveryId,
    required String password,
  }) async {
    final json = await client.postJson('/api/accounts/connect', {
      'discoveryId': discoveryId,
      'authentication': {'type': 'Password', 'password': password},
      'deviceIdentifier': await deviceIdentifierProvider.getIdentifier(),
    }, authenticated: false);
    return _save(TokenResponse.fromJson(json));
  }

  Future<TokenResponse> login({
    required String email,
    required String password,
  }) async {
    final json = await client.postJson('/api/accounts/login', {
      'email': email,
      'password': password,
      'deviceIdentifier': await deviceIdentifierProvider.getIdentifier(),
    }, authenticated: false);
    return _save(TokenResponse.fromJson(json));
  }

  Future<TokenResponse> connectManualRequest(ManualConnectionRequest request) =>
      connectManual(
        email: request.email,
        username: request.username,
        password: request.password,
        imap: request.imap,
        smtp: request.smtp,
        displayName: request.displayName,
      );

  Future<TokenResponse> connectManual({
    required String email,
    required String username,
    required String password,
    required ManualMailServer imap,
    required ManualMailServer smtp,
    required String displayName,
  }) async {
    final json = await client.postJson('/api/accounts/connect-manual', {
      'email': email,
      'username': username,
      'authentication': {'type': 'Password', 'password': password},
      'imap': imap.toJson(),
      'smtp': smtp.toJson(),
      'displayName': displayName,
      'deviceIdentifier': await deviceIdentifierProvider.getIdentifier(),
    }, authenticated: false);
    return _save(TokenResponse.fromJson(json));
  }

  Future<void> logout() async {
    final refreshToken = await tokenStore.readRefreshToken();
    try {
      if (refreshToken != null) {
        await client.postJson('/api/auth/logout', {
          'refreshToken': refreshToken,
        }, authenticated: false);
      }
    } finally {
      await tokenStore.clear();
    }
  }

  Future<TokenResponse> _save(TokenResponse response) async {
    await tokenStore.save(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      mailAccountId: response.mailAccountId,
    );
    return response;
  }
}
