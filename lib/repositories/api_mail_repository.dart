import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../services/api_auth_service.dart';
import '../services/api_client.dart';
import '../services/device_identifier_provider.dart';
import '../services/token_store.dart';
import 'mail_repository.dart';

/// Placeholder for the future real backend implementation.
///
/// All methods currently throw [UnimplementedError]. Once the backend
/// documentation/endpoints are available, implement each method here (mapping
/// the API JSON to our models) WITHOUT touching the UI.
class ApiMailRepository extends MailRepository {
  ApiMailRepository({ApiAuthService? authService})
    : _authService = authService ?? _createAuthService();

  final ApiAuthService _authService;
  MailAccount? _account;
  bool _loggedIn = false;

  static ApiAuthService _createAuthService() {
    final tokenStore = TokenStore();
    return ApiAuthService(
      client: ApiClient(tokenStore: tokenStore),
      tokenStore: tokenStore,
      deviceIdentifierProvider: PersistentDeviceIdentifierProvider(),
    );
  }

  Never _notImplemented() =>
      throw UnimplementedError('This mail endpoint is not implemented yet.');

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async {
    final discovery = await _authService.discover(email);
    await _connect(
      discoveryId: discovery.discoveryId,
      email: email,
      password: password,
      provider: discovery.provider,
    );
    return true;
  }

  @override
  Future<void> logout() async {
    await _authService.logout();
    _account = null;
    _loggedIn = false;
    notifyListeners();
  }

  @override
  String get currentUser => _account?.email ?? '';

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  List<MailAccount> get accounts => _account == null ? const [] : [_account!];

  @override
  String? get activeAccountId => _account?.id;

  @override
  Future<void> setActiveAccount(String? accountId) async {}

  @override
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
  }) async {
    final discovery = await _authService.discover(email);
    return _connect(
      discoveryId: discovery.discoveryId,
      email: email,
      password: password,
      provider: discovery.provider,
    );
  }

  Future<MailAccount> _connect({
    required String discoveryId,
    required String email,
    required String password,
    required AccountProvider provider,
  }) async {
    final tokens = await _authService.connect(
      discoveryId: discoveryId,
      password: password,
    );
    final account = MailAccount(
      id: tokens.mailAccountId,
      email: email,
      provider: provider,
    );
    _account = account;
    _loggedIn = true;
    notifyListeners();
    return account;
  }

  Future<MailAccount> connectManual(ManualConnectionRequest request) async {
    final tokens = await _authService.connectManualRequest(request);
    final account = MailAccount(
      id: tokens.mailAccountId,
      email: request.email,
      displayName: request.displayName,
      provider: AccountProvider.other,
    );
    _account = account;
    _loggedIn = true;
    notifyListeners();
    return account;
  }

  @override
  Future<void> removeAccount(String accountId) => _notImplemented();

  @override
  MailAccount? getAccount(String accountId) => _notImplemented();

  @override
  Future<void> restoreSession(String email) async {
    final accessToken = await _authService.tokenStore.readAccessToken();
    final refreshToken = await _authService.tokenStore.readRefreshToken();
    final accountId = await _authService.tokenStore.readMailAccountId();
    if (accessToken == null || refreshToken == null || accountId == null) {
      throw StateError('Secure API session is unavailable.');
    }
    _account = MailAccount(
      id: accountId,
      email: email,
      provider: AccountProvider.inferFromEmail(email),
    );
    _loggedIn = true;
    notifyListeners();
  }

  @override
  List<Email> getEmailsInFolder(MailFolder folder) => _notImplemented();

  @override
  List<Email> getAllEmails() => _notImplemented();

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) => _notImplemented();

  @override
  Future<void> refreshEmails(MailFolder folder) => _notImplemented();

  @override
  Future<Email?> getEmail(String id) => _notImplemented();

  @override
  List<Email> getThreadEmails(String threadId) => _notImplemented();

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
  }) => _notImplemented();

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
  }) => _notImplemented();

  @override
  Future<void> moveToTrash(List<String> ids) => _notImplemented();

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) =>
      _notImplemented();

  @override
  Future<void> markAsRead(List<String> ids) => _notImplemented();

  @override
  Future<void> markAsUnread(List<String> ids) => _notImplemented();

  @override
  Future<void> setPinned(List<String> ids, bool pinned) => _notImplemented();

  @override
  Future<void> setStarred(List<String> ids, bool starred) => _notImplemented();

  @override
  Future<void> markAsReplied(List<String> ids) => _notImplemented();

  @override
  Future<void> markAsForwarded(List<String> ids) => _notImplemented();

  @override
  List<MailLabel> getLabels() => _notImplemented();

  @override
  Future<MailLabel> createLabel({required String name, required Color color}) =>
      _notImplemented();

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) => _notImplemented();

  @override
  Future<void> deleteLabel(String labelId) => _notImplemented();

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _notImplemented();

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _notImplemented();
}
