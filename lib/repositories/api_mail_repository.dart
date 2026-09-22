import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_session.dart';
import '../services/api_auth_service.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/api_mail_service.dart';
import '../services/device_identifier_provider.dart';
import '../services/local_mail_flags_store.dart';
import '../services/mail_cache.dart';
import '../services/token_store.dart';
import 'mail_repository.dart';

/// [MailRepository] backed by the real backend. Pins, replied/forwarded flags
/// and labels have no API equivalent and are kept locally per account.
class ApiMailRepository extends MailRepository {
  ApiMailRepository({
    ApiAuthService? authService,
    ApiMailService? mailService,
    this._openCache,
  }) : _authService = authService ?? _createAuthService() {
    _mailService = mailService ?? ApiMailService(_authService.client);
  }

  final ApiAuthService _authService;
  final Future<MailCache> Function()? _openCache;
  MailCache? _cache;
  Timer? _persistTimer;
  Map<String, Email> _persisted = {};
  late final ApiMailService _mailService;
  MailAccount? _account;
  bool _loggedIn = false;
  bool _offline = false;
  final Map<MailFolder, String> _folderIds = {};
  final Map<String, MailFolder> _folderTypeById = {};
  final Map<MailFolder, List<Email>> _emails = {};
  final Map<MailFolder, int> _pages = {};
  String? _deviceId;
  LocalMailFlagsStore? _flagsStore;
  Set<String> _pinnedIds = {};
  final Set<String> _starredIds = {};
  final Map<String, int> _serverThreadSizes = {};
  Set<String> _repliedIds = {};
  Set<String> _forwardedIds = {};

  static ApiAuthService _createAuthService() {
    final tokenStore = TokenStore();
    return ApiAuthService(
      client: ApiClient(tokenStore: tokenStore),
      tokenStore: tokenStore,
      deviceIdentifierProvider: PersistentDeviceIdentifierProvider(),
    );
  }

  @override
  Future<bool> login({
    required String email,
    required String password,
    MailServerSettings? serverSettings,
  }) async {
    if (serverSettings != null) {
      await connectManual(
        ManualConnectionRequest(
          email: email,
          username: email,
          password: password,
          imap: ManualMailServer(
            host: serverSettings.imapServer,
            port: serverSettings.imapPort,
            security: _securityForPort(serverSettings.imapPort),
          ),
          smtp: ManualMailServer(
            host: serverSettings.smtpServer,
            port: serverSettings.smtpPort,
            security: _securityForPort(serverSettings.smtpPort),
          ),
          displayName: email,
        ),
      );
      return true;
    }
    final discovery = await _authService.discover(email);
    await _connect(
      discoveryId: discovery.discoveryId,
      email: email,
      password: password,
      provider: discovery.provider,
    );
    return true;
  }

  /// The backend only accepts two (port, security) pairings per protocol —
  /// 993/465 implicit TLS, 143/587 STARTTLS — anything else is rejected
  /// server-side as `mail_server_unsafe`.
  MailSecurity _securityForPort(int port) => (port == 993 || port == 465)
      ? MailSecurity.sslOnConnect
      : MailSecurity.startTls;

  @override
  Future<void> logout() async {
    // Drop the push registration first (best-effort — a failure here must
    // never block signing out), then revoke the session as before.
    final deviceId = _deviceId;
    _deviceId = null;
    if (deviceId != null) {
      try {
        await _mailService.unregisterDevice(deviceId);
      } catch (_) {
        // Logout still proceeds; the server registration expires on its own.
      }
    }
    await _authService.logout();
    _dropCache(_account?.id);
    _account = null;
    _loggedIn = false;
    _flagsStore = null;
    _pinnedIds = {};
    _starredIds.clear();
    _serverThreadSizes.clear();
    _repliedIds = {};
    _forwardedIds = {};
    _labels = [];
    _labelMap = {};
    notifyListeners();
  }

  /// Replaces the stored credentials via `POST /api/account/reconnect` and
  /// refreshes the cached account view. The session, flags and loaded mailbox
  /// survive — only the credentials change.
  @override
  Future<void> reconnect({required String password}) async {
    final account = await _mailService.reconnect(password: password);
    _account = account;
    notifyListeners();
  }

  /// Upserts this device's push registration and remembers the id for
  /// [logout]. The platform name follows the documented values (`android`,
  /// `ios`, …) in lowercase.
  @override
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async {
    final registration = await _mailService.registerDevice(
      token: fcmToken,
      platform: defaultTargetPlatform.name.toLowerCase(),
      appVersion: appVersion,
      locale: locale,
    );
    _deviceId = registration.id;
  }

  @override
  String get currentUser => _account?.email ?? '';

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  bool get isOffline => _offline;

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
    final tokens = await _connectOrLogin(
      email: email,
      password: password,
      connect: () =>
          _authService.connect(discoveryId: discoveryId, password: password),
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
    final tokens = await _connectOrLogin(
      email: request.email,
      password: request.password,
      connect: () => _authService.connectManualRequest(request),
    );
    final account = MailAccount(
      id: tokens.mailAccountId,
      email: request.email,
      displayName: request.displayName,
      provider: AccountProvider.other,
    );
    await _activateAccount(account);
    return _account!;
  }

  /// The account may already be registered from another device — the server
  /// rejects a duplicate `connect`/`connect-manual` with
  /// `mail_account_already_exists` instead of silently logging in, so this
  /// falls back to the dedicated login endpoint for that one error.
  Future<TokenResponse> _connectOrLogin({
    required String email,
    required String password,
    required Future<TokenResponse> Function() connect,
  }) async {
    try {
      return await connect();
    } on ApiException catch (e) {
      if (e.code != 'mail_account_already_exists') rethrow;
      return _authService.login(email: email, password: password);
    }
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
      _cache ??= await _openCacheOrMemory();
      final flags = LocalMailFlagsStore(account.id, _cache!);
      await flags.migrateLegacyPrefs();
      _pinnedIds = await flags.readPinned();
      _repliedIds = await flags.readReplied();
      _forwardedIds = await flags.readForwarded();
      await flags.seedDefaultLabels();
      _labels = [
        for (final d in await flags.readLabelDefs())
          MailLabel(
            id: d['id'] as String,
            name: d['name'] as String,
            color: Color(d['color'] as int),
          ),
      ];
      _labelMap = await flags.readLabelMap();
      _flagsStore = flags;
      _hydrateFolderMapFromCache(account.id);
      final hydrated = await _hydrateFromCache(account.id);
      // Best-effort: enrich the token-derived account with the server view
      // (displayName, provider, status). A failed read never fails the login
      // itself — the token-derived account stays.
      // Independent requests: run them concurrently to save a round trip.
      final accountFuture = _mailService.getAccount().then<MailAccount?>(
        (a) => a,
        onError: (_) => null,
      );
      // A cached mailbox (mail and/or a previously-seen folder map) means
      // there is something to show even if the backend is unreachable right
      // now — that failure must not roll the whole login back. Nothing
      // cached at all means there is nothing to fall back to, so a mailbox
      // load failure there still fails the login as before.
      final hasCachedMailbox = hydrated || _folderIds.isNotEmpty;
      try {
        await _loadMailbox();
      } catch (_) {
        if (!hasCachedMailbox) rethrow;
        _offline = true;
        notifyListeners();
      }
      await _seedStarred();
      unawaited(_seedThreadSizes());
      _account = await accountFuture ?? _account;
      // Cached mail is already on screen; quietly bring it up to date.
      if (hydrated) {
        unawaited(refreshEmails(MailFolder.inbox).catchError((_) {}));
      }
    } catch (_) {
      _account = null;
      _loggedIn = false;
      _offline = false;
      _flagsStore = null;
      _pinnedIds = {};
      _starredIds.clear();
      _repliedIds = {};
      _forwardedIds = {};
      _labels = [];
      _labelMap = {};
      rethrow;
    }
  }

  /// SQLite is also the home of pins and labels, so a failure to open it must
  /// not break login: fall back to an in-memory database (nothing persists).
  Future<MailCache> _openCacheOrMemory() async {
    try {
      return await _openCache?.call() ?? MailCache.inMemory();
    } catch (_) {
      return MailCache.inMemory();
    }
  }

  /// Restores the last-known server-folder-id -> [MailFolder] mapping so
  /// cached mail stays actionable (open, move, sync) even before — or
  /// without ever reaching — a successful [_loadMailbox] this session.
  void _hydrateFolderMapFromCache(String accountId) {
    final saved = _cache?.loadFolders(accountId) ?? const {};
    if (saved.isEmpty) return;
    _folderIds.clear();
    _folderTypeById.clear();
    for (final entry in saved.entries) {
      MailFolder logical;
      try {
        logical = MailFolder.values.byName(entry.value);
      } catch (_) {
        continue;
      }
      _folderIds[logical] = entry.key;
      _folderTypeById[entry.key] = logical;
    }
  }

  /// Paints the last known mailbox from SQLite before any network call.
  /// Best-effort: a missing or corrupt cache just means a normal cold load.
  Future<bool> _hydrateFromCache(String accountId) async {
    try {
      _persisted = {};
      final cached = _cache?.load(accountId) ?? const <Email>[];
      if (cached.isEmpty) return false;
      _emails.clear();
      _pages.clear();
      for (final email in cached) {
        _emails
            .putIfAbsent(email.folder, () => <Email>[])
            .add(_stampLocalFlags(email));
      }
      for (final list in _emails.values) {
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // ponytail: whole-mailbox rewrite (<= ~100 rows/folder) debounced on every
  // change; switch to per-row upserts if mailboxes or write rates grow.
  @override
  void notifyListeners() {
    _touch();
    super.notifyListeners();
    final cache = _cache;
    final accountId = _account?.id;
    if (cache == null || accountId == null) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        // Emails are immutable, so identity tells us what changed.
        final current = <String, Email>{
          for (final e in _emails.entries)
            if (e.key != MailFolder.pinned)
              for (final m in e.value.take(100)) m.id: m,
        };
        final changed = [
          for (final m in current.values)
            if (!identical(_persisted[m.id], m)) m,
        ];
        final removed = _persisted.keys.where((id) => !current.containsKey(id));
        if (changed.isNotEmpty || removed.isNotEmpty) {
          cache.apply(accountId, changed, removed.toList());
          _persisted = current;
        }
      } catch (_) {
        // Cache is an optimization; never surface its failures.
      }
    });
  }

  void _dropCache(String? accountId) {
    _persistTimer?.cancel();
    _persisted = {};
    if (accountId != null) {
      try {
        _cache?.clear(accountId);
      } catch (_) {}
    }
    _emails.clear();
    _pages.clear();
  }

  /// Overlays the locally-persisted pin/reply/forward flags onto a mail
  /// freshly mapped from the API — the server has no concept of any of the
  /// three, so every fetch would otherwise reset them.
  Email _stampLocalFlags(Email email) => email.copyWith(
    // List responses carry no star state, so a fetched mail must never
    // clear a star we already know about.
    isStarred: email.isStarred || _starredIds.contains(email.id),
    isPinned: _pinnedIds.contains(email.id),
    isReplied: email.isReplied || _repliedIds.contains(email.id),
    isForwarded: _forwardedIds.contains(email.id),
    labelIds: _labelMap[email.id] ?? const [],
  );

  @override
  Future<void> removeAccount(String accountId) async {
    if (_account?.id != accountId) return;
    await _mailService.deleteAccount();
    await _authService.tokenStore.clear();
    _cache?.forgetAccount(accountId);
    _dropCache(_account?.id);
    _account = null;
    _loggedIn = false;
    _flagsStore = null;
    _pinnedIds = {};
    _starredIds.clear();
    _repliedIds = {};
    _forwardedIds = {};
    _labels = [];
    _labelMap = {};
    notifyListeners();
  }

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

  @override
  Future<List<MailSession>> getSessions() async {
    final sessions = await _mailService.getSessions();
    final myDeviceId = await _authService.deviceIdentifierProvider
        .getIdentifier();
    return sessions
        .map(
          (s) => s.copyWith(isCurrentDevice: s.deviceIdentifier == myDeviceId),
        )
        .toList();
  }

  @override
  Future<void> revokeSession(String sessionId) =>
      _mailService.deleteSession(sessionId);

  Future<void> _loadMailbox() async {
    final folders = await _mailService.getFolders();
    _folderIds.clear();
    _folderTypeById.clear();
    _serverUnread.clear();
    for (final folder in folders) {
      if (!folder.isAvailable) continue;
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
        final unread = folder.unreadCount;
        if (unread != null) _serverUnread[logical] = unread;
      }
    }
    _offline = false;
    _persistFolderMap();
    notifyListeners();
  }

  /// Best-effort: remembers the current folder map so [_hydrateFolderMapFromCache]
  /// can restore it on a future offline cold start.
  void _persistFolderMap() {
    final cache = _cache;
    final accountId = _account?.id;
    if (cache == null || accountId == null) return;
    try {
      cache.saveFolders(accountId, {
        for (final entry in _folderIds.entries) entry.value: entry.key.name,
      });
    } catch (_) {
      // Cache is an optimization; never surface its failures.
    }
  }

  final Map<MailFolder, int> _serverUnread = {};

  @override
  int unreadCount(MailFolder folder) =>
      _serverUnread[folder] ?? super.unreadCount(folder);

  /// Best-effort re-read of server counts after a mutation.
  Future<void> _refreshCounts() async {
    try {
      final folders = await _mailService.getFolders();
      for (final f in folders) {
        final logical = _folderTypeById[f.id];
        if (logical != null && f.unreadCount != null) {
          _serverUnread[logical] = f.unreadCount!;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// List endpoints omit star state, so ask the search endpoint for every
  /// flagged mail once and remember the ids. Missing mails are added to their
  /// folder so "Yıldızlılar" is complete even before those folders paginate.
  /// Best-effort: failure just leaves stars to detail loads.
  Future<void> _seedStarred() async {
    try {
      final flagged = await _mailService.search(
        query: '',
        flagged: true,
        pageSize: 100,
        resolveFolder: _resolveFolder,
      );
      _starredIds
        ..clear()
        ..addAll(flagged.map((e) => e.id));
      for (final mail in flagged) {
        final list = _emails.putIfAbsent(mail.folder, () => <Email>[]);
        if (list.every((e) => e.id != mail.id)) {
          list.add(_stampLocalFlags(mail));
        }
      }
      _replaceMany(_starredIds, (e) => e.copyWith(isStarred: true));
    } catch (_) {}
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
    _touch();
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
    _touch();
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
    final trashed = {
      for (final e in _emails[MailFolder.trash] ?? const []) e.id,
    };
    final spammed = {
      for (final e in _emails[MailFolder.spam] ?? const []) e.id,
    };
    return ids
        .where((id) => trashed.contains(id) || spammed.contains(id))
        .toList();
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
    unawaited(_refreshCounts());
  }

  static bool _highlighted(Email e) => e.isPinned || e.isStarred;

  /// [MailFolder.pinned] is virtual — "Yıldızlılar" surfaces every pinned or
  /// starred mail regardless of its real folder — so it's built by scanning
  /// every cached bucket rather than a fetched one. Every folder additionally
  /// floats highlighted mails above the rest, newest-first within each
  /// group, matching [MailRepository.getEmailsInFolder]'s documented order.
  @override
  List<Email> getEmailsInFolder(MailFolder folder) =>
      _folderViews[folder] ??= _buildFolderView(folder);

  // Sorted views are rebuilt lazily, once per change, instead of on every
  // widget rebuild. Anything that mutates [_emails] must call [_touch].
  final Map<MailFolder, List<Email>> _folderViews = {};
  List<Email>? _allView;
  void _touch() {
    _folderViews.clear();
    _allView = null;
  }

  List<Email> _buildFolderView(MailFolder folder) {
    final result = folder == MailFolder.pinned
        ? _emails.values.expand((list) => list).where(_highlighted).toList()
        : List<Email>.of(_emails[folder] ?? const []);
    result.sort((a, b) {
      final ha = _highlighted(a);
      final hb = _highlighted(b);
      if (ha != hb) return ha ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return List.unmodifiable(result);
  }

  @override
  List<Email> getAllEmails() => _allView ??= _emails.values
      .expand((items) => items)
      .toList(growable: false);

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
    final fresh = result.items
        .where((email) => known.add(email.id))
        .map(_stampLocalFlags)
        .toList();
    current.addAll(fresh);
    _pages[folder] = result.page;
    _offline = false;
    notifyListeners();
    return List.unmodifiable(fresh);
  }

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    final folderId = _folderIds[folder];
    if (folderId == null) return;
    // Fetch first, swap after: the current list stays on screen meanwhile.
    final result = await _mailService.getMails(
      folderId: folderId,
      page: 1,
      resolveFolder: _resolveFolder,
    );
    final old = {for (final e in _emails[folder] ?? const <Email>[]) e.id: e};
    _offline = false;
    _emails[folder] = [
      for (final e in result.items)
        // List items carry no body or star state; keep what we already know.
        _stampLocalFlags(
          old[e.id] == null
              ? e
              : e.copyWith(
                  bodyText: old[e.id]!.bodyText.isEmpty
                      ? e.bodyText
                      : old[e.id]!.bodyText,
                  isStarred: old[e.id]!.isStarred,
                ),
        ),
    ];
    _pages[folder] = result.page;
    notifyListeners();
  }

  /// Copies cached mails into [folder] server-side, then reloads that folder
  /// so the new copies reconcile with real server ids.
  Future<void> copyMails(List<String> ids, MailFolder folder) async {
    if (ids.isEmpty) return;
    final folderId = _folderIds[folder];
    if (folderId == null) {
      throw ArgumentError('Unknown target folder for this account: $folder');
    }
    for (final id in ids) {
      await _mailService.copyMail(id, folderId);
    }
    await refreshEmails(folder);
  }

  /// Re-discovers the server folder tree, then re-resolves the local folder
  /// mapping. Returns the server-reported folder count.
  Future<int> refreshFolders() async {
    final count = await _mailService.refreshFolders();
    await _loadMailbox();
    return count;
  }

  /// Triggers a server sync of [folder] (pull-to-refresh). No completion
  /// notification exists — callers re-fetch the list afterwards (spec §2).
  /// Unknown folders throw [ArgumentError], matching [moveToFolder].
  @override
  Future<void> syncFolder(MailFolder folder) async {
    final folderId = _folderIds[folder];
    if (folderId == null) {
      throw ArgumentError('Unknown folder for this account: $folder');
    }
    await _mailService.syncFolderId(folderId);
  }

  @override
  Future<Email?> getEmail(String id) async {
    try {
      final email = _stampLocalFlags(
        await _mailService.getMail(id, resolveFolder: _resolveFolder),
      );
      _upsertDetail(email);
      return email;
    } on ApiException catch (error) {
      if (error.code == 'mail_not_found' || error.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> downloadAttachment(
    String mailId,
    Attachment attachment,
  ) async {
    // Locally picked attachments carry no server id — there is nothing to
    // download; hand back the bytes we already hold.
    if (attachment.id == null || attachment.id!.isEmpty) {
      return attachment.bytes ?? Uint8List(0);
    }
    return _mailService.downloadAttachment(mailId, attachment.id!);
  }

  /// Stores a full detail object in the in-memory cache without notifying:
  /// replaces the cached copy in whichever bucket holds it, or files it
  /// under its own folder when unknown. Never creates duplicates, so a
  /// detail fetch never corrupts the folder lists.
  void _upsertDetail(Email email) {
    _touch();
    for (final folder in _emails.keys.toList()) {
      final list = _emails[folder]!;
      final index = list.indexWhere((e) => e.id == email.id);
      if (index >= 0) {
        _emails[folder] = [...list]..[index] = email;
        return;
      }
    }
    _emails.putIfAbsent(email.folder, () => <Email>[]).insert(0, email);
  }

  /// Synchronously available snapshot of the cache — whatever detail fetches
  /// have enriched so far. Remote conversations load via [fetchThreadEmails].
  @override
  List<Email> getThreadEmails(String threadId) {
    if (threadId.isEmpty) return const [];
    final thread = <Email>[];
    for (final list in _emails.values) {
      thread.addAll(list.where((e) => e.threadId == threadId));
    }
    thread.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(thread);
  }

  @override
  int serverThreadSize(String threadId) => _serverThreadSizes[threadId] ?? 0;

  /// Best-effort: message counts per conversation, so an inbox row shows the
  /// whole thread even when the replies live in an unloaded folder.
  Future<void> _seedThreadSizes() async {
    try {
      final page = await _mailService.getConversations(pageSize: 100);
      for (final c in page.items) {
        _serverThreadSizes[c.id] = c.messageCount;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Server-side conversation list (`GET /api/conversations`) for views that
  /// need subject-level metadata. Thread bodies still resolve through
  /// [fetchThreadEmails], which already prefers the server conversation and
  /// falls back to the local `threadId` grouping when it is unavailable.
  Future<ConversationListPage> getConversations({
    int page = 1,
    int pageSize = 50,
  }) => _mailService.getConversations(page: page, pageSize: pageSize);

  /// Loads the full server conversation in one `?include=body` request; only
  /// messages with attachments get a detail fetch (recipients + attachment
  /// list). An unreadable detail falls back to the summary. The
  /// result is deduplicated and sorted oldest → newest. A conversation-level
  /// failure propagates so the caller can keep its already-loaded mail.
  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async {
    if (threadId.isEmpty) return const [];
    final conversation = await _mailService.getConversationWithBodies(threadId);
    final results = await Future.wait(
      conversation.messages.map((raw) async {
        final id = raw['id'] as String?;
        if (id == null || id.isEmpty) return null;
        final summary = _mailService.mapConversationMessage({
          ...raw,
          'conversationId': threadId,
        }, _resolveFolder);
        if (raw['hasAttachments'] != true) return summary;
        try {
          return await _mailService.getMail(id, resolveFolder: _resolveFolder);
        } catch (_) {
          return summary;
        }
      }),
    );
    final seen = <String>{};
    final thread = <Email>[];
    for (final mail in results) {
      if (mail == null || !seen.add(mail.id)) continue;
      final stamped = _stampLocalFlags(mail);
      thread.add(stamped);
      _upsertDetail(stamped);
    }
    thread.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(thread);
  }

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
  }) async {
    final result = await _mailService.sendMail(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      attachments: attachments,
      replySourceMailId: inReplyToId,
      idempotencyKey: _newIdempotencyKey(),
    );
    // The endpoint confirms send/save outcome but never returns the created
    // mail — build the local copy from what we sent and echo it into the
    // Sent cache so the UI reflects it before the next refresh reconciles.
    final id = result.mailId ?? 'sent-${DateTime.now().microsecondsSinceEpoch}';
    final email = Email(
      id: id,
      senderName: _account?.displayName ?? '',
      senderEmail: from ?? _account?.email ?? '',
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.sent,
      attachments: attachments,
      accountId: _account?.id ?? '',
      threadId: (threadId == null || threadId.isEmpty)
          ? (result.conversationId ?? 't-$id')
          : threadId,
      inReplyToId: inReplyToId,
    );
    if (result.sentCopySaved) {
      _emails.putIfAbsent(MailFolder.sent, () => <Email>[]).insert(0, email);
      notifyListeners();
    }
    return email;
  }

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
    String? draftId,
  }) async {
    // Editing an existing draft goes through PUT /drafts/{id}, which returns
    // a NEW mailId — the old id is invalid afterwards, so the cache drops it
    // and stores the draft under the new one instead of duplicating it.
    if (draftId != null) {
      final result = await _mailService.updateDraft(
        draftId,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        attachments: attachments,
        replySourceMailId: inReplyToId,
      );
      final newId = result.mailId ?? draftId;
      final drafts = _emails.putIfAbsent(MailFolder.drafts, () => <Email>[]);
      final oldIndex = drafts.indexWhere((e) => e.id == draftId);
      final previous = oldIndex >= 0 ? drafts[oldIndex] : null;
      final updated = Email(
        id: newId,
        senderName: _account?.displayName ?? previous?.senderName ?? '',
        senderEmail: from ?? _account?.email ?? previous?.senderEmail ?? '',
        recipients: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        timestamp: DateTime.now(),
        isRead: true,
        folder: MailFolder.drafts,
        attachments: attachments,
        accountId: _account?.id ?? previous?.accountId ?? '',
        threadId: (threadId == null || threadId.isEmpty)
            ? (previous?.threadId.isNotEmpty == true
                  ? previous!.threadId
                  : 't-$newId')
            : threadId,
        inReplyToId: inReplyToId ?? previous?.inReplyToId,
      );
      if (oldIndex >= 0) {
        drafts[oldIndex] = updated;
      } else {
        drafts.insert(0, updated);
      }
      notifyListeners();
      return updated;
    }
    final result = await _mailService.createDraft(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      attachments: attachments,
      replySourceMailId: inReplyToId,
    );
    // Reconciliation can still be pending right after APPEND — fall back to
    // a local id so the draft is still usable; refreshEmails(drafts) will
    // reconcile it with the server's real id on the next sync.
    final id =
        result.mailId ?? 'draft-${DateTime.now().microsecondsSinceEpoch}';
    final email = Email(
      id: id,
      senderName: _account?.displayName ?? '',
      senderEmail: from ?? _account?.email ?? '',
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: _account?.id ?? '',
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
      inReplyToId: inReplyToId,
    );
    _emails.putIfAbsent(MailFolder.drafts, () => <Email>[]).insert(0, email);
    notifyListeners();
    return email;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    await _mailService.deleteDraft(draftId);
    final drafts = _emails[MailFolder.drafts];
    drafts?.removeWhere((e) => e.id == draftId);
    notifyListeners();
  }

  /// Sends a draft via `POST /api/drafts/{id}/send`. A fresh
  /// `Idempotency-Key` per attempt makes a network-timeout retry safe. Never
  /// retries `delivery_unknown` automatically — the [ApiException] propagates
  /// so the UI can say "check Sent". `draftRemoved == false` still counts as
  /// sent (spec §5): the draft just stays in the Drafts bucket.
  Future<Email?> sendDraft(String draftId) async {
    final draft = _findCached(draftId);
    final result = await _mailService.sendDraft(
      draftId,
      idempotencyKey: _newIdempotencyKey(),
    );
    if (!result.sent) return null;
    if (result.draftRemoved) {
      _emails[MailFolder.drafts]?.removeWhere((e) => e.id == draftId);
    }
    final echo =
        (draft ??
                Email(
                  id: draftId,
                  senderName: _account?.displayName ?? '',
                  senderEmail: _account?.email ?? '',
                  recipients: const [],
                  subject: '',
                  bodyText: '',
                  timestamp: DateTime.now(),
                  folder: MailFolder.sent,
                  accountId: _account?.id ?? '',
                ))
            .copyWith(folder: MailFolder.sent, timestamp: DateTime.now());
    _emails.putIfAbsent(MailFolder.sent, () => <Email>[]).insert(0, echo);
    notifyListeners();
    return echo;
  }

  Email? _findCached(String id) {
    for (final list in _emails.values) {
      for (final email in list) {
        if (email.id == id) return email;
      }
    }
    return null;
  }

  /// Prefill data for the reply/reply-all/forward screen (see
  /// [ApiMailService.getComposePrefill]).
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String kind) =>
      _mailService.getComposePrefill(sourceMailId, kind);

  /// Server-side full-text + filtered search (`GET /api/search`) over cached
  /// server mail — reaches mail not yet loaded into the local buckets. The
  /// sync in-screen search ([MailRepository.searchEmails]) stays client-side
  /// over loaded mail; callers needing the full corpus use this instead.
  Future<List<Email>> searchServer({
    required String query,
    String? folderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    int page = 1,
    int pageSize = 20,
  }) async {
    final results = await _mailService.search(
      query: query,
      resolveFolder: _resolveFolder,
      folderId: folderId,
      conversationId: conversationId,
      from: from,
      to: to,
      fromDate: fromDate,
      toDate: toDate,
      isRead: isRead,
      flagged: flagged,
      hasAttachment: hasAttachment,
      page: page,
      pageSize: pageSize,
    );
    return results.map(_stampLocalFlags).toList();
  }

  /// A client-generated UUID v4 for the `Idempotency-Key` header — stable
  /// per send attempt so a network-timeout retry never double-sends.
  String _newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  @override
  Future<void> moveToTrash(List<String> ids) => _bulkAndApply(
    'trash',
    ids,
    (succeeded) => _moveMany(succeeded, MailFolder.trash),
  );

  /// Mails currently in Trash/Spam go back through bulk `restore` (the only
  /// action that reverses those two); everything else moves via the bulk `move`/`archive` actions. Both branches can run
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
    await _bulkAndApply(
      'restore',
      restoring.toList(),
      (succeeded) => _moveMany(succeeded, folder),
    );

    final rest = ids.where((id) => !restoring.contains(id)).toList();
    if (rest.isNotEmpty) {
      await _bulkAndApply(
        folder == MailFolder.archive ? 'archive' : 'move',
        rest,
        (succeeded) => _moveMany(succeeded, folder),
        folderId: folder == MailFolder.archive ? null : folderId,
      );
    }
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

  /// Pinning never reaches the network — see [LocalMailFlagsStore]. Pinning
  /// beyond [MailRepository.maxPinnedMails] is silently capped; unpinning
  /// always applies.
  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    final store = _flagsStore;
    if (store == null) return;
    if (pinned) {
      var free = MailRepository.maxPinnedMails - _pinnedIds.length;
      for (final id in ids) {
        if (free <= 0) break;
        if (_pinnedIds.add(id)) free--;
      }
    } else {
      _pinnedIds.removeAll(ids);
    }
    await store.writePinned(_pinnedIds);
    _replaceMany(ids, (e) => e.copyWith(isPinned: _pinnedIds.contains(e.id)));
    notifyListeners();
  }

  @override
  Future<void> setStarred(List<String> ids, bool starred) =>
      _bulkAndApply(starred ? 'star' : 'unstar', ids, (succeeded) {
        starred
            ? _starredIds.addAll(succeeded)
            : _starredIds.removeAll(succeeded);
        _replaceMany(succeeded, (e) => e.copyWith(isStarred: starred));
      });

  /// Marks that the user opened the reply screen. The "replied" flag itself
  /// is local-only (see [LocalMailFlagsStore]), but opening a reply also
  /// reads the mail, which the API *does* track — so that half goes through
  /// the real `read` action instead of being faked locally.
  @override
  Future<void> markAsReplied(List<String> ids) async {
    if (ids.isEmpty) return;
    final store = _flagsStore;
    if (store == null) return;
    await markAsRead(ids);
    _repliedIds.addAll(ids);
    await store.writeReplied(_repliedIds);
    _replaceMany(ids, (e) => e.copyWith(isReplied: true));
    notifyListeners();
  }

  /// Marks that the user opened the forward screen — same split as
  /// [markAsReplied]: "forwarded" is local-only, the resulting read state
  /// goes through the real `read` action.
  @override
  Future<void> markAsForwarded(List<String> ids) async {
    if (ids.isEmpty) return;
    final store = _flagsStore;
    if (store == null) return;
    await markAsRead(ids);
    _forwardedIds.addAll(ids);
    await store.writeForwarded(_forwardedIds);
    _replaceMany(ids, (e) => e.copyWith(isForwarded: true));
    notifyListeners();
  }

  // Labels are client-side only (the API has none); persisted per account.
  List<MailLabel> _labels = [];
  Map<String, List<String>> _labelMap = {};

  static String _canonicalName(String name) =>
      name.trim().replaceAll('İ', 'i').toLowerCase();

  void _assertLabelNameIsFree(String name, {String? selfId}) {
    final canonical = _canonicalName(name);
    if (canonical.isEmpty) throw ArgumentError('Etiket adı boş olamaz.');
    if (_labels.any(
      (l) => l.id != selfId && _canonicalName(l.name) == canonical,
    )) {
      throw ArgumentError('Bu isimde bir etiket zaten var.');
    }
  }

  Future<void> _persistLabels() async {
    final store = _flagsStore;
    if (store == null) return;
    await store.writeLabelDefs([
      for (final l in _labels)
        {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
    ]);
    await store.writeLabelMap(_labelMap);
  }

  void _restampLabels(Iterable<String> ids) => _replaceMany(
    ids.toList(),
    (e) => e.copyWith(labelIds: _labelMap[e.id] ?? const []),
  );

  @override
  List<MailLabel> getLabels() => List.unmodifiable(_labels);

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
  }) async {
    _assertLabelNameIsFree(name);
    final label = MailLabel(
      id: 'label-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      color: color,
    );
    _labels = [..._labels, label];
    await _persistLabels();
    notifyListeners();
    return label;
  }

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {
    final index = _labels.indexWhere((l) => l.id == id);
    if (index < 0) return;
    _assertLabelNameIsFree(name, selfId: id);
    _labels = [..._labels]
      ..[index] = MailLabel(id: id, name: name.trim(), color: color);
    await _persistLabels();
    notifyListeners();
  }

  @override
  Future<void> deleteLabel(String labelId) async {
    if (!_labels.any((l) => l.id == labelId)) return;
    _labels = _labels.where((l) => l.id != labelId).toList();
    final touched = [
      for (final e in _labelMap.entries)
        if (e.value.contains(labelId)) e.key,
    ];
    for (final id in touched) {
      _labelMap[id] = _labelMap[id]!.where((l) => l != labelId).toList();
    }
    await _persistLabels();
    _restampLabels(touched);
    notifyListeners();
  }

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    for (final id in emailIds) {
      final cur = _labelMap[id] ?? const <String>[];
      _labelMap[id] = [...cur, ...labelIds.where((l) => !cur.contains(l))];
    }
    await _persistLabels();
    _restampLabels(emailIds);
    notifyListeners();
  }

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    for (final id in emailIds) {
      _labelMap[id] = (_labelMap[id] ?? const <String>[])
          .where((l) => !labelIds.contains(l))
          .toList();
    }
    await _persistLabels();
    _restampLabels(emailIds);
    notifyListeners();
  }
}
