import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../services/api_auth_service.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/api_mail_service.dart';
import '../services/device_identifier_provider.dart';
import '../services/token_store.dart';
import 'mail_repository.dart';

/// Placeholder for the future real backend implementation.
///
/// All methods currently throw [UnimplementedError]. Once the backend
/// documentation/endpoints are available, implement each method here (mapping
/// the API JSON to our models) WITHOUT touching the UI.
class ApiMailRepository extends MailRepository {
  ApiMailRepository({ApiAuthService? authService, ApiMailService? mailService})
    : _authService = authService ?? _createAuthService() {
    _mailService = mailService ?? ApiMailService(_authService.client);
  }

  final ApiAuthService _authService;
  late final ApiMailService _mailService;
  MailAccount? _account;
  bool _loggedIn = false;
  final Map<MailFolder, String> _folderIds = {};
  final Map<MailFolder, List<Email>> _emails = {};
  final Map<MailFolder, int> _pages = {};

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
    await _loadMailbox();
    return _account!;
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
    await _loadMailbox();
    return _account!;
  }

  @override
  Future<void> removeAccount(String accountId) => _notImplemented();

  @override
  MailAccount? getAccount(String accountId) =>
      _account?.id == accountId ? _account : null;

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
    await _loadMailbox();
  }

  Future<void> _loadMailbox() async {
    final folders = await _mailService.getFolders();
    _folderIds.clear();
    for (final folder in folders) {
      final logical = switch (folder.type.toLowerCase()) {
        'inbox' => MailFolder.inbox,
        'sent' => MailFolder.sent,
        'drafts' => MailFolder.drafts,
        'trash' => MailFolder.trash,
        'junk' => MailFolder.spam,
        'spam' => MailFolder.spam,
        'archive' => MailFolder.archive,
        _ => null,
      };
      if (logical != null) _folderIds[logical] = folder.id;
    }
    notifyListeners();
  }

  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      List.unmodifiable(_emails[folder] ?? const []);

  @override
  List<Email> getAllEmails() =>
      _emails.values.expand((items) => items).toList(growable: false);

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    final folderId = _folderIds[folder];
    if (folderId == null) return const [];
    final page = (_pages[folder] ?? 0) + 1;
    final result = await _mailService.getMails(folderId: folderId, page: page);
    final current = _emails.putIfAbsent(folder, () => <Email>[]);
    final known = current.map((email) => email.id).toSet();
    final fresh = result.items.where((email) => known.add(email.id)).toList();
    current.addAll(fresh);
    _pages[folder] = result.page;
    notifyListeners();
    return List.unmodifiable(fresh);
  }

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    _pages[folder] = 0;
    _emails[folder] = [];
    await loadMoreEmails(folder);
  }

  @override
  Future<Email?> getEmail(String id) async {
    try {
      return await _mailService.getMail(id);
    } on ApiException catch (error) {
      if (error.code == 'mail_not_found' || error.status == 404) return null;
      rethrow;
    }
  }

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
