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
  final Map<String, MailFolder> _folderTypeById = {};
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
    await _activateAccount(account);
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
    await _activateAccount(account);
    return _account!;
  }

  /// Sets [account] as signed-in and loads its mailbox. Rolls the account
  /// state back on failure so a mailbox-load error (e.g. a transient network
  /// failure right after a successful login) never leaves the repository
  /// reporting `isLoggedIn == true` behind a login/restore failure shown to
  /// the user.
  Future<void> _activateAccount(MailAccount account) async {
    _account = account;
    _loggedIn = true;
    try {
      await _loadMailbox();
    } catch (_) {
      _account = null;
      _loggedIn = false;
      rethrow;
    }
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
    final account = MailAccount(
      id: accountId,
      email: email,
      provider: AccountProvider.inferFromEmail(email),
    );
    await _activateAccount(account);
  }

  Future<void> _loadMailbox() async {
    final folders = await _mailService.getFolders();
    _folderIds.clear();
    _folderTypeById.clear();
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
      if (logical != null) {
        _folderIds[logical] = folder.id;
        _folderTypeById[folder.id] = logical;
      }
    }
    notifyListeners();
  }

  /// Maps a raw API folder id back to our logical [MailFolder]. Custom
  /// server folders we don't track locally fall back to inbox, matching the
  /// filter already applied in [_loadMailbox].
  MailFolder _resolveFolder(String folderId) =>
      _folderTypeById[folderId] ?? MailFolder.inbox;

  /// Applies [update] in place to every cached mail in [ids], wherever its
  /// bucket, without changing which folder bucket it lives in.
  void _replaceMany(Iterable<String> ids, Email Function(Email) update) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    for (final folder in _emails.keys.toList()) {
      final list = _emails[folder]!;
      _emails[folder] = [
        for (final email in list)
          idSet.contains(email.id) ? update(email) : email,
      ];
    }
  }

  /// Moves every cached mail in [ids] into [targetFolder]'s bucket,
  /// stamping the new folder on each and dropping it from wherever it used
  /// to live. Mails not currently cached are ignored.
  void _moveMany(Iterable<String> ids, MailFolder targetFolder) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    final moved = <Email>[];
    for (final folder in _emails.keys.toList()) {
      if (folder == targetFolder) continue;
      final list = _emails[folder]!;
      final keep = <Email>[];
      for (final email in list) {
        if (idSet.contains(email.id)) {
          moved.add(email.copyWith(folder: targetFolder));
        } else {
          keep.add(email);
        }
      }
      _emails[folder] = keep;
    }
    if (moved.isNotEmpty) {
      _emails.putIfAbsent(targetFolder, () => <Email>[]).insertAll(0, moved);
    }
  }

  /// Ids from [ids] whose cached copy currently lives in Trash or Spam —
  /// the only two folders `restore` is valid from.
  List<String> _idsInTrashOrSpam(Iterable<String> ids) {
    final trashed = {for (final e in _emails[MailFolder.trash] ?? const []) e.id};
    final spammed = {for (final e in _emails[MailFolder.spam] ?? const []) e.id};
    return ids.where((id) => trashed.contains(id) || spammed.contains(id)).toList();
  }

  /// Applies a bulk action and updates the local cache only for the ids the
  /// server actually confirmed — a partial failure in [ids] never desyncs
  /// the ones that succeeded (see the API's bulk semantics).
  Future<void> _bulkAndApply(
    String action,
    List<String> ids,
    void Function(List<String> succeededIds) apply, {
    String? folderId,
  }) async {
    if (ids.isEmpty) return;
    final results = await _mailService.bulkAction(
      action,
      ids,
      folderId: folderId,
    );
    final succeeded = results
        .where((r) => r.success)
        .map((r) => r.mailId)
        .toList();
    apply(succeeded);
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
    final result = await _mailService.getMails(
      folderId: folderId,
      page: page,
      resolveFolder: _resolveFolder,
    );
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
      return await _mailService.getMail(id, resolveFolder: _resolveFolder);
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
  Future<void> moveToTrash(List<String> ids) => _bulkAndApply(
    'trash',
    ids,
    (succeeded) => _moveMany(succeeded, MailFolder.trash),
  );

  /// Mails currently in Trash/Spam go back through `restore` (the only
  /// action that reverses those two, per mail — no bulk variant); everything
  /// else moves via the bulk `move`/`archive` actions. Both branches can run
  /// in the same call when [ids] mixes trashed and non-trashed mails (e.g. a
  /// multi-select spanning folders).
  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    if (ids.isEmpty) return;
    final folderId = _folderIds[folder];
    if (folderId == null) {
      throw ArgumentError('Unknown target folder for this account: $folder');
    }

    final restoring = _idsInTrashOrSpam(ids);
    for (final id in restoring) {
      await _mailService.mailAction(id, 'restore');
    }
    if (restoring.isNotEmpty) _moveMany(restoring, folder);

    final rest = ids.where((id) => !restoring.contains(id)).toList();
    if (rest.isNotEmpty) {
      await _bulkAndApply(
        folder == MailFolder.archive ? 'archive' : 'move',
        rest,
        (succeeded) => _moveMany(succeeded, folder),
        folderId: folder == MailFolder.archive ? null : folderId,
      );
    }
    if (restoring.isNotEmpty) notifyListeners();
  }

  @override
  Future<void> markAsRead(List<String> ids) => _bulkAndApply(
    'read',
    ids,
    (succeeded) => _replaceMany(succeeded, (e) => e.copyWith(isRead: true)),
  );

  @override
  Future<void> markAsUnread(List<String> ids) => _bulkAndApply(
    'unread',
    ids,
    (succeeded) => _replaceMany(succeeded, (e) => e.copyWith(isRead: false)),
  );

  @override
  Future<void> setPinned(List<String> ids, bool pinned) => _notImplemented();

  /// No bulk star/unstar endpoint exists, so each id is a separate request.
  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      await _mailService.mailAction(id, starred ? 'star' : 'unstar');
    }
    _replaceMany(ids, (e) => e.copyWith(isStarred: starred));
    notifyListeners();
  }

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
