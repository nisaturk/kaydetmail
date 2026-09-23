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

/// Everything one connected mailbox needs to operate independently: its own
/// authenticated HTTP session, its own folder/mail cache, and its own
/// client-only state (pins, replied/forwarded, labels). Multiple accounts
/// hold multiple [_Session]s side by side — connecting a second account
/// never touches the first one's tokens, mail, or flags.
class _Session {
  _Session({
    required this.authService,
    required this.mailService,
    required this.account,
  });

  MailAccount account;
  final ApiAuthService authService;
  final ApiMailService mailService;

  bool offline = false;
  String? deviceId;
  LocalMailFlagsStore? flagsStore;

  final Map<MailFolder, String> folderIds = {};
  final Map<String, MailFolder> folderTypeById = {};
  final Map<MailFolder, List<Email>> emails = {};
  final Map<MailFolder, int> pages = {};
  final Map<MailFolder, int> serverUnread = {};
  final Map<String, int> serverThreadSizes = {};

  Set<String> pinnedIds = {};
  final Set<String> starredIds = {};
  Set<String> repliedIds = {};
  Set<String> forwardedIds = {};

  List<MailLabel> labels = [];
  Map<String, List<String>> labelMap = {};

  // Debounced whole-mailbox cache write-behind, mirrored per account so one
  // account's writes never race another's.
  Timer? persistTimer;
  Map<String, Email> persisted = {};

  // Polls the backend every 15s while [offline] until a probe succeeds —
  // see [ApiMailRepository._scheduleReconnectRetry].
  Timer? reconnectTimer;

  /// Maps a raw API folder id back to our logical [MailFolder]. Custom
  /// server folders we don't track locally fall back to inbox.
  MailFolder resolveFolder(String folderId) =>
      folderTypeById[folderId] ?? MailFolder.inbox;

  /// Overlays the locally-persisted pin/reply/forward/label flags onto a
  /// mail freshly mapped from the API — the server has no concept of any of
  /// them, so every fetch would otherwise reset them.
  Email stampLocalFlags(Email email) => email.copyWith(
    isStarred: email.isStarred || starredIds.contains(email.id),
    isPinned: pinnedIds.contains(email.id),
    isReplied: email.isReplied || repliedIds.contains(email.id),
    isForwarded: forwardedIds.contains(email.id),
    labelIds: labelMap[email.id] ?? const [],
  );
}

/// [MailRepository] backed by the real backend. Pins, replied/forwarded flags
/// and labels have no API equivalent and are kept locally per account.
///
/// Every connected mailbox gets its own [_Session] — its own authenticated
/// client, its own folder/mail state, its own local flags — so accounts stay
/// fully independent: connecting or removing one never disturbs another.
/// [activeAccountId] just narrows which session(s) the public read/write
/// methods below operate on; `null` fans reads out across every session
/// (the unified mailbox) and routes writes to whichever session actually
/// owns the ids involved.
class ApiMailRepository extends MailRepository {
  ApiMailRepository({
    ApiAuthService? authService,
    ApiMailService? mailService,
    this._openCache,
    this._sessionFactory,
  }) : _initialAuthService = authService,
       _initialMailService = mailService;

  // Test seams: the first session created (via login/connect/restore) uses
  // the injected auth+mail service pair when present; every session after
  // that uses [_sessionFactory] when supplied, otherwise a real one.
  final ApiAuthService? _initialAuthService;
  final ApiMailService? _initialMailService;
  final ({ApiAuthService authService, ApiMailService mailService}) Function()?
  _sessionFactory;
  bool _initialConsumed = false;

  final Future<MailCache> Function()? _openCache;
  MailCache? _cache;

  /// Every connected account's session, keyed by account id, in connection
  /// order (a `Map` literal is insertion-ordered) — that order is also
  /// [accounts]' order and the order accounts restore in at app launch.
  final Map<String, _Session> _sessions = {};

  /// `null` selects the unified mailbox (every session); non-null narrows
  /// every read/write below to that one session.
  String? _activeAccountId;

  static ({ApiAuthService authService, ApiMailService mailService})
  _buildRealServices() {
    final auth = _createAuthService();
    return (authService: auth, mailService: ApiMailService(auth.client));
  }

  static ApiAuthService _createAuthService() {
    final tokenStore = TokenStore();
    return ApiAuthService(
      client: ApiClient(tokenStore: tokenStore),
      tokenStore: tokenStore,
      deviceIdentifierProvider: PersistentDeviceIdentifierProvider(),
    );
  }

  /// The auth+mail service pair for the NEXT session to activate. The first
  /// call consumes whatever was injected at construction (falling back to a
  /// real pair); every call after that asks [_sessionFactory] (tests) or
  /// builds another real pair (production) — connecting a third, fourth, …
  /// account always gets its own independent client.
  ({ApiAuthService authService, ApiMailService mailService}) _nextServices() {
    if (!_initialConsumed) {
      _initialConsumed = true;
      final auth = _initialAuthService ?? _createAuthService();
      final mail = _initialMailService ?? ApiMailService(auth.client);
      return (authService: auth, mailService: mail);
    }
    final factory = _sessionFactory;
    if (factory != null) return factory();
    return _buildRealServices();
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
    final services = _nextServices();
    final discovery = await services.authService.discover(email);
    await _connect(
      services: services,
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
    for (final session in _sessions.values.toList()) {
      await _unregisterDeviceFor(session);
      await session.authService.logout();
      session.persistTimer?.cancel();
      _cancelReconnectRetry(session);
      _cache?.clear(session.account.id);
      _sessions.remove(session.account.id);
    }
    _activeAccountId = null;
    _touch();
    notifyListeners();
  }

  Future<void> _unregisterDeviceFor(_Session session) async {
    final deviceId = session.deviceId;
    if (deviceId == null) return;
    session.deviceId = null;
    try {
      await session.mailService.unregisterDevice(deviceId);
    } catch (_) {
      // Best-effort — the server registration expires on its own.
    }
  }

  /// Removes every connected account's push registration (e.g. the user
  /// turned notifications off in Settings). Safe to call when nothing is
  /// registered — a no-op then.
  @override
  Future<void> unregisterDevice() async {
    await Future.wait(_sessions.values.map(_unregisterDeviceFor));
  }

  /// Starts polling the backend every 15s while [session] is offline; stops
  /// as soon as a probe succeeds. Without this, `isOffline` (and the
  /// "Bağlantı yok" banner) only clears the next time the user happens to
  /// trigger a successful `refreshEmails`/`loadMoreEmails`/`_loadMailbox`
  /// call for that account — e.g. a manual pull-to-refresh or an app
  /// restart — even though the backend may already be reachable again.
  void _scheduleReconnectRetry(_Session session) {
    session.reconnectTimer?.cancel();
    session.reconnectTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _retryConnection(session);
    });
  }

  void _cancelReconnectRetry(_Session session) {
    session.reconnectTimer?.cancel();
    session.reconnectTimer = null;
  }

  Future<void> _retryConnection(_Session session) async {
    if (!session.offline) {
      _cancelReconnectRetry(session);
      return;
    }
    try {
      await _loadMailbox(session);
    } catch (_) {
      return; // Still offline; the timer fires again on the next tick.
    }
    // Bring every already-loaded folder's mail up to date now that the
    // backend is reachable again.
    for (final folder in session.emails.keys.toList()) {
      unawaited(_refreshEmailsFor(session, folder).catchError((_) {}));
    }
  }

  /// Replaces the stored credentials via `POST /api/account/reconnect` for
  /// whichever account the caller is currently looking at (falling back to
  /// the first connected account) and refreshes the cached account view.
  /// The session, flags and loaded mailbox survive — only the credentials
  /// change.
  @override
  Future<void> reconnect({required String password}) async {
    final session = _primarySession;
    final account = await session.mailService.reconnect(password: password);
    session.account = account;
    _touch();
    notifyListeners();
  }

  /// Upserts this device's push registration for every connected account and
  /// remembers each registration id for [logout]. Best-effort per account —
  /// one account's registration failing never blocks the others.
  @override
  Future<void> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async {
    await Future.wait(
      _sessions.values.map((session) async {
        try {
          final registration = await session.mailService.registerDevice(
            token: fcmToken,
            platform: defaultTargetPlatform.name.toLowerCase(),
            appVersion: appVersion,
            locale: locale,
          );
          session.deviceId = registration.id;
        } catch (_) {}
      }),
    );
  }

  @override
  String get currentUser {
    final active = _activeAccountId;
    if (active != null) return _sessions[active]?.account.email ?? '';
    return _sessions.values.firstOrNull?.account.email ?? '';
  }

  @override
  bool get isLoggedIn => _sessions.isNotEmpty;

  @override
  bool get isOffline =>
      _scopedSessions.isNotEmpty && _scopedSessions.every((s) => s.offline);

  @override
  List<MailAccount> get accounts =>
      _sessions.values.map((s) => s.account).toList(growable: false);

  @override
  String? get activeAccountId => _activeAccountId;

  @override
  Future<void> setActiveAccount(String? accountId) async {
    if (accountId != null && !_sessions.containsKey(accountId)) return;
    _activeAccountId = accountId;
    _touch();
    notifyListeners();
  }

  @override
  Future<MailAccount> connectAccount({
    required String email,
    required String password,
  }) async {
    final services = _nextServices();
    final discovery = await services.authService.discover(email);
    final account = await _connect(
      services: services,
      discoveryId: discovery.discoveryId,
      email: email,
      password: password,
      provider: discovery.provider,
    );
    // A freshly added account surfaces immediately via the unified mailbox
    // rather than staying hidden behind whatever single account was active.
    _activeAccountId = null;
    _touch();
    notifyListeners();
    return account;
  }

  Future<MailAccount> _connect({
    required ({ApiAuthService authService, ApiMailService mailService})
    services,
    required String discoveryId,
    required String email,
    required String password,
    required AccountProvider provider,
  }) async {
    final tokens = await _connectOrLogin(
      authService: services.authService,
      email: email,
      password: password,
      connect: () => services.authService.connect(
        discoveryId: discoveryId,
        password: password,
      ),
    );
    final account = MailAccount(
      id: tokens.mailAccountId,
      email: email,
      provider: provider,
    );
    return _activateSession(
      account,
      authService: services.authService,
      mailService: services.mailService,
    );
  }

  Future<MailAccount> connectManual(ManualConnectionRequest request) async {
    final services = _nextServices();
    final tokens = await _connectOrLogin(
      authService: services.authService,
      email: request.email,
      password: request.password,
      connect: () => services.authService.connectManualRequest(request),
    );
    final account = MailAccount(
      id: tokens.mailAccountId,
      email: request.email,
      displayName: request.displayName,
      provider: AccountProvider.other,
    );
    return _activateSession(
      account,
      authService: services.authService,
      mailService: services.mailService,
    );
  }

  /// The account may already be registered from another device — the server
  /// rejects a duplicate `connect`/`connect-manual` with
  /// `mail_account_already_exists` instead of silently logging in, so this
  /// falls back to the dedicated login endpoint for that one error.
  Future<TokenResponse> _connectOrLogin({
    required ApiAuthService authService,
    required String email,
    required String password,
    required Future<TokenResponse> Function() connect,
  }) async {
    try {
      return await connect();
    } on ApiException catch (e) {
      if (e.code != 'mail_account_already_exists') rethrow;
      return authService.login(email: email, password: password);
    }
  }

  /// Registers [account] as one more connected session and loads its
  /// mailbox. Rolls the session back out on failure so a mailbox-load error
  /// (e.g. a transient network failure right after a successful login) never
  /// leaves a half-initialized account behind.
  Future<MailAccount> _activateSession(
    MailAccount account, {
    required ApiAuthService authService,
    required ApiMailService mailService,
  }) async {
    final session = _Session(
      authService: authService,
      mailService: mailService,
      account: account,
    );
    _sessions[account.id] = session;
    try {
      _cache ??= await _openCacheOrMemory();
      final flags = LocalMailFlagsStore(account.id, _cache!);
      await flags.migrateLegacyPrefs();
      session.pinnedIds = await flags.readPinned();
      session.repliedIds = await flags.readReplied();
      session.forwardedIds = await flags.readForwarded();
      await flags.seedDefaultLabels();
      session.labels = [
        for (final d in await flags.readLabelDefs())
          MailLabel(
            id: d['id'] as String,
            name: d['name'] as String,
            color: Color(d['color'] as int),
          ),
      ];
      session.labelMap = await flags.readLabelMap();
      session.flagsStore = flags;
      _hydrateFolderMapFromCache(session);
      final hydrated = await _hydrateFromCache(session);
      // Best-effort: enrich the token-derived account with the server view
      // (displayName, provider, status). A failed read never fails the login
      // itself — the token-derived account stays.
      final accountFuture = mailService.getAccount().then<MailAccount?>(
        (a) => a,
        onError: (_) => null,
      );
      // A cached mailbox (mail and/or a previously-seen folder map) means
      // there is something to show even if the backend is unreachable right
      // now — that failure must not roll the whole login back.
      final hasCachedMailbox = hydrated || session.folderIds.isNotEmpty;
      try {
        await _loadMailbox(session);
      } catch (_) {
        if (!hasCachedMailbox) rethrow;
        session.offline = true;
        _scheduleReconnectRetry(session);
        notifyListeners();
      }
      await _seedStarred(session);
      unawaited(_seedThreadSizes(session));
      session.account = await accountFuture ?? session.account;
      // Cached mail is already on screen; quietly bring it up to date.
      if (hydrated) {
        unawaited(
          _refreshEmailsFor(session, MailFolder.inbox).catchError((_) {}),
        );
      }
      notifyListeners();
      return session.account;
    } catch (_) {
      _cancelReconnectRetry(session);
      _sessions.remove(account.id);
      _touch();
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
  void _hydrateFolderMapFromCache(_Session session) {
    final saved = _cache?.loadFolders(session.account.id) ?? const {};
    if (saved.isEmpty) return;
    session.folderIds.clear();
    session.folderTypeById.clear();
    for (final entry in saved.entries) {
      MailFolder logical;
      try {
        logical = MailFolder.values.byName(entry.value);
      } catch (_) {
        continue;
      }
      session.folderIds[logical] = entry.key;
      session.folderTypeById[entry.key] = logical;
    }
  }

  /// Paints the last known mailbox from SQLite before any network call.
  /// Best-effort: a missing or corrupt cache just means a normal cold load.
  Future<bool> _hydrateFromCache(_Session session) async {
    try {
      session.persisted = {};
      final cached = _cache?.load(session.account.id) ?? const <Email>[];
      if (cached.isEmpty) return false;
      session.emails.clear();
      session.pages.clear();
      for (final email in cached) {
        session.emails
            .putIfAbsent(email.folder, () => <Email>[])
            .add(session.stampLocalFlags(email));
      }
      for (final list in session.emails.values) {
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
    if (cache == null) return;
    for (final session in _sessions.values) {
      session.persistTimer?.cancel();
      session.persistTimer = Timer(const Duration(milliseconds: 800), () {
        try {
          // Emails are immutable, so identity tells us what changed.
          final current = <String, Email>{
            for (final e in session.emails.entries)
              if (e.key != MailFolder.starred)
                for (final m in e.value.take(100)) m.id: m,
          };
          final changed = [
            for (final m in current.values)
              if (!identical(session.persisted[m.id], m)) m,
          ];
          final removed = session.persisted.keys.where(
            (id) => !current.containsKey(id),
          );
          if (changed.isNotEmpty || removed.isNotEmpty) {
            cache.apply(session.account.id, changed, removed.toList());
            session.persisted = current;
          }
        } catch (_) {
          // Cache is an optimization; never surface its failures.
        }
      });
    }
  }

  @override
  Future<void> removeAccount(String accountId) async {
    final session = _sessions[accountId];
    if (session == null) return;
    await session.mailService.deleteAccount();
    await session.authService.tokenStore.clear(accountId);
    await _unregisterDeviceFor(session);
    session.persistTimer?.cancel();
    _cancelReconnectRetry(session);
    _sessions.remove(accountId);
    if (_activeAccountId == accountId) _activeAccountId = null;
    _touch();
    notifyListeners();
  }

  @override
  MailAccount? getAccount(String accountId) => _sessions[accountId]?.account;

  @override
  Future<void> restoreSession(String email) async {
    final services = _nextServices();
    final accountIds = await services.authService.tokenStore.readAccountIds();
    final candidateId = accountIds.firstWhere(
      (id) => !_sessions.containsKey(id),
      orElse: () => '',
    );
    if (candidateId.isEmpty) {
      throw StateError('Secure API session is unavailable.');
    }
    final accessToken = await services.authService.tokenStore.readAccessToken(
      candidateId,
    );
    final refreshToken = await services.authService.tokenStore.readRefreshToken(
      candidateId,
    );
    if (accessToken == null || refreshToken == null) {
      throw StateError('Secure API session is unavailable.');
    }
    services.authService.client.bindAccount(candidateId);
    final account = MailAccount(
      id: candidateId,
      email: email,
      provider: AccountProvider.inferFromEmail(email),
    );
    await _activateSession(
      account,
      authService: services.authService,
      mailService: services.mailService,
    );
  }

  /// Device sessions of whichever account is currently active (falling back
  /// to the first connected account).
  @override
  Future<List<MailSession>> getSessions() async {
    final session = _sessions[_activeAccountId] ?? _sessions.values.firstOrNull;
    if (session == null) return const [];
    final sessions = await session.mailService.getSessions();
    final myDeviceId = await session.authService.deviceIdentifierProvider
        .getIdentifier();
    return sessions
        .map(
          (s) => s.copyWith(isCurrentDevice: s.deviceIdentifier == myDeviceId),
        )
        .toList();
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    final session = _sessions[_activeAccountId] ?? _sessions.values.firstOrNull;
    if (session == null) return;
    await session.mailService.deleteSession(sessionId);
  }

  Future<void> _loadMailbox(_Session session) async {
    final folders = await session.mailService.getFolders();
    session.folderIds.clear();
    session.folderTypeById.clear();
    session.serverUnread.clear();
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
        session.folderIds[logical] = folder.id;
        session.folderTypeById[folder.id] = logical;
        final unread = folder.unreadCount;
        if (unread != null) session.serverUnread[logical] = unread;
      }
    }
    _cancelReconnectRetry(session);
    session.offline = false;
    _persistFolderMap(session);
    notifyListeners();
  }

  /// Best-effort: remembers the current folder map so
  /// [_hydrateFolderMapFromCache] can restore it on a future offline cold
  /// start.
  void _persistFolderMap(_Session session) {
    final cache = _cache;
    if (cache == null) return;
    try {
      cache.saveFolders(session.account.id, {
        for (final entry in session.folderIds.entries)
          entry.value: entry.key.name,
      });
    } catch (_) {
      // Cache is an optimization; never surface its failures.
    }
  }

  @override
  int unreadCount(MailFolder folder) => _scopedSessions.fold(
    0,
    (sum, s) =>
        sum +
        (s.serverUnread[folder] ??
            (s.emails[folder]?.where((e) => !e.isRead).length ?? 0)),
  );

  /// Best-effort re-read of server counts after a mutation.
  Future<void> _refreshCountsFor(_Session session) async {
    try {
      final folders = await session.mailService.getFolders();
      for (final f in folders) {
        final logical = session.folderTypeById[f.id];
        if (logical != null && f.unreadCount != null) {
          session.serverUnread[logical] = f.unreadCount!;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// List endpoints omit star state, so ask the search endpoint for every
  /// flagged mail once and remember the ids. Missing mails are added to their
  /// folder so "Yıldızlılar" is complete even before those folders paginate.
  /// Best-effort: failure just leaves stars to detail loads.
  Future<void> _seedStarred(_Session session) async {
    try {
      final flagged = await session.mailService.search(
        query: '',
        flagged: true,
        pageSize: 100,
        resolveFolder: session.resolveFolder,
      );
      session.starredIds
        ..clear()
        ..addAll(flagged.map((e) => e.id));
      for (final mail in flagged) {
        final list = session.emails.putIfAbsent(mail.folder, () => <Email>[]);
        if (list.every((e) => e.id != mail.id)) {
          list.add(session.stampLocalFlags(mail));
        }
      }
      _replaceMany(
        session,
        session.starredIds,
        (e) => e.copyWith(isStarred: true),
      );
    } catch (_) {}
  }

  /// Applies [update] in place to every cached mail in [ids] within
  /// [session], wherever its bucket, without changing which folder bucket it
  /// lives in.
  void _replaceMany(
    _Session session,
    Iterable<String> ids,
    Email Function(Email) update,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    for (final folder in session.emails.keys.toList()) {
      final list = session.emails[folder]!;
      session.emails[folder] = [
        for (final email in list)
          idSet.contains(email.id) ? update(email) : email,
      ];
    }
  }

  /// Moves every cached mail in [ids] into [targetFolder]'s bucket within
  /// [session], stamping the new folder on each and dropping it from
  /// wherever it used to live. Mails not currently cached are ignored.
  void _moveMany(
    _Session session,
    Iterable<String> ids,
    MailFolder targetFolder,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    final moved = <Email>[];
    for (final folder in session.emails.keys.toList()) {
      if (folder == targetFolder) continue;
      final list = session.emails[folder]!;
      final keep = <Email>[];
      for (final email in list) {
        if (idSet.contains(email.id)) {
          moved.add(email.copyWith(folder: targetFolder));
        } else {
          keep.add(email);
        }
      }
      session.emails[folder] = keep;
    }
    if (moved.isNotEmpty) {
      session.emails
          .putIfAbsent(targetFolder, () => <Email>[])
          .insertAll(0, moved);
    }
  }

  /// Ids from [ids] whose cached copy currently lives in Trash or Spam —
  /// the only two folders `restore` is valid from.
  List<String> _idsInTrashOrSpam(_Session session, Iterable<String> ids) {
    final trashed = {
      for (final e in session.emails[MailFolder.trash] ?? const []) e.id,
    };
    final spammed = {
      for (final e in session.emails[MailFolder.spam] ?? const []) e.id,
    };
    return ids
        .where((id) => trashed.contains(id) || spammed.contains(id))
        .toList();
  }

  /// Applies a bulk action within [session] and updates the local cache only
  /// for the ids the server actually confirmed — a partial failure in [ids]
  /// never desyncs the ones that succeeded (see the API's bulk semantics).
  Future<void> _bulkAndApply(
    _Session session,
    String action,
    List<String> ids,
    void Function(List<String> succeededIds) apply, {
    String? folderId,
  }) async {
    if (ids.isEmpty) return;
    final results = await session.mailService.bulkAction(
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
    unawaited(_refreshCountsFor(session));
  }

  static bool _pinned(Email email) => email.isPinned;

  /// Sessions the public read/write methods operate on: just the active one
  /// when scoped, every connected session when unified (`null`).
  Iterable<_Session> get _scopedSessions {
    final id = _activeAccountId;
    if (id == null) return _sessions.values;
    final s = _sessions[id];
    return s == null ? const [] : [s];
  }

  /// The session bulk actions default to when nothing else identifies one:
  /// the active account when scoped, otherwise the first connected account.
  /// Throws if nothing is connected — callers only reach this while logged
  /// in.
  _Session get _primarySession {
    final active = _activeAccountId;
    if (active != null) {
      final s = _sessions[active];
      if (s != null) return s;
    }
    return _sessions.values.first;
  }

  /// The session that currently caches a mail with [id], if any.
  _Session? _sessionOwning(String id) {
    for (final s in _sessions.values) {
      for (final list in s.emails.values) {
        if (list.any((e) => e.id == id)) return s;
      }
    }
    return null;
  }

  /// The session that currently caches any message of [threadId], if any.
  _Session? _sessionForThread(String threadId) {
    for (final s in _sessions.values) {
      if (s.emails.values.any(
        (list) => list.any((e) => e.threadId == threadId),
      )) {
        return s;
      }
    }
    return null;
  }

  /// The session that owns label [labelId], if any.
  _Session? _sessionForLabel(String labelId) {
    for (final s in _sessions.values) {
      if (s.labels.any((l) => l.id == labelId)) return s;
    }
    return null;
  }

  /// Splits a mixed-account id list by which session actually caches each
  /// id. Unknown ids (not cached anywhere) are dropped — bulk endpoints only
  /// ever act on mail the UI already showed the user.
  Map<_Session, List<String>> _groupBySession(List<String> ids) {
    final grouped = <_Session, List<String>>{};
    for (final id in ids) {
      final session = _sessionOwning(id);
      if (session == null) continue;
      grouped.putIfAbsent(session, () => <String>[]).add(id);
    }
    return grouped;
  }

  /// The session a compose action should send/save from: an explicit
  /// account id first, then the picked sender address, otherwise whatever
  /// [_primarySession] resolves to.
  _Session _sessionForCompose({String? from, String? fromAccountId}) {
    if (fromAccountId != null) {
      final s = _sessions[fromAccountId];
      if (s != null) return s;
    }
    if (from != null) {
      for (final s in _sessions.values) {
        if (s.account.email == from) return s;
      }
    }
    return _primarySession;
  }

  final Map<String, List<Email>> _viewCache = {};

  // Anything that mutates a session's [_Session.emails] map, or that
  // switches [_activeAccountId], must call [_touch] so the next read
  // rebuilds instead of serving a stale view.
  void _touch() => _viewCache.clear();

  /// [MailFolder.starred] is virtual — "Yıldızlılar" surfaces starred mail
  /// regardless of its real folder. Pinning remains independent: pinned mail
  /// floats above the rest inside whichever folder it already belongs to.
  /// The unified mailbox (`activeAccountId == null`) merges every session's
  /// mail into one such view.
  @override
  List<Email> getEmailsInFolder(MailFolder folder) {
    final key = 'folder:${folder.name}:${_activeAccountId ?? ''}';
    return _viewCache.putIfAbsent(key, () => _buildFolderView(folder));
  }

  List<Email> _buildFolderView(MailFolder folder) {
    final sessions = _scopedSessions;
    final result = folder == MailFolder.starred
        ? [
            for (final s in sessions)
              ...s.emails.values
                  .expand((list) => list)
                  .where((e) => e.isStarred),
          ]
        : [for (final s in sessions) ...(s.emails[folder] ?? const <Email>[])];
    result.sort((a, b) {
      final ha = _pinned(a);
      final hb = _pinned(b);
      if (ha != hb) return ha ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return List.unmodifiable(result);
  }

  @override
  List<Email> getAllEmails() {
    const key = 'all:global';
    return _viewCache.putIfAbsent(
      key,
      () => [
        for (final s in _sessions.values) ...s.emails.values.expand((l) => l),
      ],
    );
  }

  @override
  List<Email> getScopedEmails() {
    final key = 'all:${_activeAccountId ?? ''}';
    return _viewCache.putIfAbsent(
      key,
      () => [
        for (final s in _scopedSessions) ...s.emails.values.expand((l) => l),
      ],
    );
  }

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    final results = await Future.wait(
      _scopedSessions.map((s) => _loadMoreFor(s, folder)),
    );
    return results.expand((r) => r).toList();
  }

  Future<List<Email>> _loadMoreFor(_Session session, MailFolder folder) async {
    final folderId = session.folderIds[folder];
    if (folderId == null) return const [];
    final page = (session.pages[folder] ?? 0) + 1;
    final result = await session.mailService.getMails(
      folderId: folderId,
      page: page,
      resolveFolder: session.resolveFolder,
    );
    final current = session.emails.putIfAbsent(folder, () => <Email>[]);
    final known = current.map((email) => email.id).toSet();
    final fresh = result.items
        .where((email) => known.add(email.id))
        .map(session.stampLocalFlags)
        .toList();
    current.addAll(fresh);
    session.pages[folder] = result.page;
    _cancelReconnectRetry(session);
    session.offline = false;
    notifyListeners();
    return List.unmodifiable(fresh);
  }

  @override
  Future<void> refreshEmails(MailFolder folder) =>
      Future.wait(_scopedSessions.map((s) => _refreshEmailsFor(s, folder)));

  Future<void> _refreshEmailsFor(_Session session, MailFolder folder) async {
    final folderId = session.folderIds[folder];
    if (folderId == null) return;
    // Fetch first, swap after: the current list stays on screen meanwhile.
    final result = await session.mailService.getMails(
      folderId: folderId,
      page: 1,
      resolveFolder: session.resolveFolder,
    );
    final old = {
      for (final e in session.emails[folder] ?? const <Email>[]) e.id: e,
    };
    _cancelReconnectRetry(session);
    session.offline = false;
    final refreshed = [
      for (final e in result.items)
        // List items carry no body or star state; keep what we already know.
        session.stampLocalFlags(
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
    // Refresh only re-fetches page 1. Mail paged in earlier via
    // loadMoreEmails is still real and must not vanish just because this
    // pass didn't re-verify it — losing it also breaks threadStatusOf's
    // cross-message reply/forward aggregation for any thread whose
    // answered/forwarded message lived past page 1.
    final refreshedIds = refreshed.map((e) => e.id).toSet();
    final stale = old.values
        .where((e) => !refreshedIds.contains(e.id))
        .map(session.stampLocalFlags);
    session.emails[folder] = [...refreshed, ...stale]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    session.pages[folder] = max(session.pages[folder] ?? 1, result.page);
    notifyListeners();
  }

  /// Copies cached mails into [folder] server-side, then reloads that folder
  /// so the new copies reconcile with real server ids.
  Future<void> copyMails(List<String> ids, MailFolder folder) async {
    if (ids.isEmpty) return;
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final folderId = session.folderIds[folder];
      if (folderId == null) {
        throw ArgumentError('Unknown target folder for this account: $folder');
      }
      for (final id in entry.value) {
        await session.mailService.copyMail(id, folderId);
      }
      await _refreshEmailsFor(session, folder);
    }
  }

  /// Re-discovers the server folder tree for the primary session, then
  /// re-resolves the local folder mapping. Returns the server-reported
  /// folder count.
  Future<int> refreshFolders() async {
    final session = _primarySession;
    final count = await session.mailService.refreshFolders();
    await _loadMailbox(session);
    return count;
  }

  /// Triggers a server sync of [folder] (pull-to-refresh). No completion
  /// notification exists — callers re-fetch the list afterwards. Unknown
  /// folders throw [ArgumentError], matching [moveToFolder].
  @override
  Future<void> syncFolder(MailFolder folder) async {
    final sessions = _scopedSessions.toList();
    if (sessions.isEmpty) return;
    var any = false;
    for (final session in sessions) {
      final folderId = session.folderIds[folder];
      if (folderId == null) continue;
      any = true;
      await session.mailService.syncFolderId(folderId);
    }
    if (!any) {
      throw ArgumentError('Unknown folder for this account: $folder');
    }
  }

  @override
  Future<Email?> getEmail(String id) async {
    final owner = _sessionOwning(id);
    final candidates = owner != null ? [owner] : _scopedSessions.toList();
    var sawNotFound = false;
    for (final session in candidates) {
      try {
        final email = session.stampLocalFlags(
          await session.mailService.getMail(
            id,
            resolveFolder: session.resolveFolder,
          ),
        );
        _upsertDetail(session, email);
        return email;
      } on ApiException catch (error) {
        if (error.code == 'mail_not_found' || error.status == 404) {
          sawNotFound = true;
          continue;
        }
        rethrow;
      }
    }
    if (sawNotFound || candidates.isEmpty) return null;
    return null;
  }

  @override
  Future<Uint8List> downloadAttachment(
    String mailId,
    Attachment attachment,
  ) async {
    final id = attachment.id;
    if (id == null) {
      // Not yet uploaded — the bytes already live in the attachment object.
      return attachment.bytes ?? Uint8List(0);
    }
    final owner = _sessionOwning(mailId) ?? _primarySession;
    return owner.mailService.downloadAttachment(mailId, id);
  }

  /// Stores a full detail object in [session]'s in-memory cache without
  /// notifying: replaces the cached copy in whichever bucket holds it, or
  /// files it under its own folder when unknown. Never creates duplicates,
  /// so a detail fetch never corrupts the folder lists.
  void _upsertDetail(_Session session, Email email) {
    _touch();
    for (final folder in session.emails.keys.toList()) {
      final list = session.emails[folder]!;
      final index = list.indexWhere((e) => e.id == email.id);
      if (index >= 0) {
        session.emails[folder] = [...list]..[index] = email;
        return;
      }
    }
    session.emails.putIfAbsent(email.folder, () => <Email>[]).insert(0, email);
  }

  /// Synchronously available snapshot of the cache — whatever detail fetches
  /// have enriched so far. Remote conversations load via [fetchThreadEmails].
  /// Searches every connected account, not just the active scope — a thread
  /// belongs to exactly one account, and the caller already knows which
  /// mail/thread it wants regardless of the current mailbox view.
  @override
  List<Email> getThreadEmails(String threadId) {
    if (threadId.isEmpty) return const [];
    final thread = <Email>[];
    for (final session in _sessions.values) {
      for (final list in session.emails.values) {
        thread.addAll(list.where((e) => e.threadId == threadId));
      }
    }
    thread.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(thread);
  }

  @override
  int serverThreadSize(String threadId) {
    for (final session in _sessions.values) {
      final size = session.serverThreadSizes[threadId];
      if (size != null) return size;
    }
    return 0;
  }

  /// Best-effort: message counts per conversation, so an inbox row shows the
  /// whole thread even when the replies live in an unloaded folder.
  Future<void> _seedThreadSizes(_Session session) async {
    try {
      final page = await session.mailService.getConversations(pageSize: 100);
      for (final c in page.items) {
        session.serverThreadSizes[c.id] = c.messageCount;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Server-side conversation list (`GET /api/conversations`) for the
  /// primary session.
  Future<ConversationListPage> getConversations({
    int page = 1,
    int pageSize = 50,
  }) => _primarySession.mailService.getConversations(
    page: page,
    pageSize: pageSize,
  );

  /// Loads the full server conversation in one `?include=body` request; only
  /// messages with attachments get a detail fetch (recipients + attachment
  /// list). An unreadable detail falls back to the summary. The
  /// result is deduplicated and sorted oldest → newest. A conversation-level
  /// failure propagates so the caller can keep its already-loaded mail.
  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async {
    if (threadId.isEmpty) return const [];
    final session = _sessionForThread(threadId) ?? _sessions.values.firstOrNull;
    if (session == null) return const [];
    final conversation = await session.mailService.getConversationWithBodies(
      threadId,
    );
    final results = await Future.wait(
      conversation.messages.map((raw) async {
        final id = raw['id'] as String?;
        if (id == null || id.isEmpty) return null;
        final summary = session.mailService.mapConversationMessage({
          ...raw,
          'conversationId': threadId,
        }, session.resolveFolder);
        if (raw['hasAttachments'] != true) return summary;
        try {
          return await session.mailService.getMail(
            id,
            resolveFolder: session.resolveFolder,
          );
        } catch (_) {
          return summary;
        }
      }),
    );
    final seen = <String>{};
    final thread = <Email>[];
    for (final mail in results) {
      if (mail == null || !seen.add(mail.id)) continue;
      final stamped = session.stampLocalFlags(mail);
      thread.add(stamped);
      _upsertDetail(session, stamped);
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
    final session = _sessionForCompose(
      from: from,
      fromAccountId: fromAccountId,
    );
    final result = await session.mailService.sendMail(
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
      senderName: session.account.displayName ?? '',
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.sent,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty)
          ? (result.conversationId ?? 't-$id')
          : threadId,
      inReplyToId: inReplyToId,
    );
    if (result.sentCopySaved) {
      session.emails
          .putIfAbsent(MailFolder.sent, () => <Email>[])
          .insert(0, email);
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
    final session = draftId != null
        ? (_sessionOwning(draftId) ??
              _sessionForCompose(from: from, fromAccountId: fromAccountId))
        : _sessionForCompose(from: from, fromAccountId: fromAccountId);
    // Editing an existing draft goes through PUT /drafts/{id}, which returns
    // a NEW mailId — the old id is invalid afterwards, so the cache drops it
    // and stores the draft under the new one instead of duplicating it.
    if (draftId != null) {
      final result = await session.mailService.updateDraft(
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
      final drafts = session.emails.putIfAbsent(
        MailFolder.drafts,
        () => <Email>[],
      );
      final oldIndex = drafts.indexWhere((e) => e.id == draftId);
      final previous = oldIndex >= 0 ? drafts[oldIndex] : null;
      final updated = Email(
        id: newId,
        senderName: session.account.displayName ?? previous?.senderName ?? '',
        senderEmail: from ?? session.account.email,
        recipients: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        timestamp: DateTime.now(),
        isRead: true,
        folder: MailFolder.drafts,
        attachments: attachments,
        accountId: session.account.id,
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
    final result = await session.mailService.createDraft(
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
      senderName: session.account.displayName ?? '',
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
      inReplyToId: inReplyToId,
    );
    session.emails
        .putIfAbsent(MailFolder.drafts, () => <Email>[])
        .insert(0, email);
    notifyListeners();
    return email;
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    final session = _sessionOwning(draftId) ?? _primarySession;
    await session.mailService.deleteDraft(draftId);
    session.emails[MailFolder.drafts]?.removeWhere((e) => e.id == draftId);
    notifyListeners();
  }

  /// Sends a draft via `POST /api/drafts/{id}/send`. A fresh
  /// `Idempotency-Key` per attempt makes a network-timeout retry safe. Never
  /// retries `delivery_unknown` automatically — the [ApiException] propagates
  /// so the UI can say "check Sent". `draftRemoved == false` still counts as
  /// sent: the draft just stays in the Drafts bucket.
  Future<Email?> sendDraft(String draftId) async {
    final session = _sessionOwning(draftId) ?? _primarySession;
    final draft = _findCached(draftId);
    final result = await session.mailService.sendDraft(
      draftId,
      idempotencyKey: _newIdempotencyKey(),
    );
    if (!result.sent) return null;
    if (result.draftRemoved) {
      session.emails[MailFolder.drafts]?.removeWhere((e) => e.id == draftId);
    }
    final echo =
        (draft ??
                Email(
                  id: draftId,
                  senderName: session.account.displayName ?? '',
                  senderEmail: session.account.email,
                  recipients: const [],
                  subject: '',
                  bodyText: '',
                  timestamp: DateTime.now(),
                  folder: MailFolder.sent,
                  accountId: session.account.id,
                ))
            .copyWith(folder: MailFolder.sent, timestamp: DateTime.now());
    session.emails
        .putIfAbsent(MailFolder.sent, () => <Email>[])
        .insert(0, echo);
    notifyListeners();
    return echo;
  }

  Email? _findCached(String id) {
    for (final session in _sessions.values) {
      for (final list in session.emails.values) {
        for (final email in list) {
          if (email.id == id) return email;
        }
      }
    }
    return null;
  }

  /// Prefill data for the reply/reply-all/forward screen (see
  /// [ApiMailService.getComposePrefill]).
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String kind) {
    final session = _sessionOwning(sourceMailId) ?? _primarySession;
    return session.mailService.getComposePrefill(sourceMailId, kind);
  }

  /// Server-side full-text + filtered search (`GET /api/search`) over cached
  /// server mail, fanned out across every account in scope — reaches mail
  /// not yet loaded into the local buckets. The sync in-screen search
  /// ([MailRepository.searchEmails]) stays client-side over loaded mail.
  @override
  Future<List<Email>> searchEmailsOnServer({
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
    final all = <Email>[];
    for (final session in _sessions.values) {
      final results = await session.mailService.search(
        query: query,
        resolveFolder: session.resolveFolder,
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
      all.addAll(results.map(session.stampLocalFlags));
    }
    return all;
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
  Future<void> moveToTrash(List<String> ids) async {
    await Future.wait(
      _groupBySession(ids).entries.map(
        (e) => _bulkAndApply(
          e.key,
          'trash',
          e.value,
          (succeeded) => _moveMany(e.key, succeeded, MailFolder.trash),
        ),
      ),
    );
  }

  /// Mails currently in Trash/Spam go back through bulk `restore` (the only
  /// action that reverses those two); everything else moves via the bulk
  /// `move`/`archive` actions. Both branches can run per account when [ids]
  /// mixes trashed and non-trashed mails across multiple connected accounts.
  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) async {
    if (ids.isEmpty) return;
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final folderId = session.folderIds[folder];
      if (folderId == null) {
        throw ArgumentError('Unknown target folder for this account: $folder');
      }
      final idsForSession = entry.value;
      final restoring = _idsInTrashOrSpam(session, idsForSession);
      await _bulkAndApply(
        session,
        'restore',
        restoring.toList(),
        (succeeded) => _moveMany(session, succeeded, folder),
      );

      final rest = idsForSession
          .where((id) => !restoring.contains(id))
          .toList();
      if (rest.isNotEmpty) {
        await _bulkAndApply(
          session,
          folder == MailFolder.archive ? 'archive' : 'move',
          rest,
          (succeeded) => _moveMany(session, succeeded, folder),
          folderId: folder == MailFolder.archive ? null : folderId,
        );
      }
    }
  }

  @override
  Future<void> markAsRead(List<String> ids) async {
    await Future.wait(
      _groupBySession(ids).entries.map(
        (e) => _bulkAndApply(
          e.key,
          'read',
          e.value,
          (succeeded) =>
              _replaceMany(e.key, succeeded, (m) => m.copyWith(isRead: true)),
        ),
      ),
    );
  }

  @override
  Future<void> markAsUnread(List<String> ids) async {
    await Future.wait(
      _groupBySession(ids).entries.map(
        (e) => _bulkAndApply(
          e.key,
          'unread',
          e.value,
          (succeeded) =>
              _replaceMany(e.key, succeeded, (m) => m.copyWith(isRead: false)),
        ),
      ),
    );
  }

  /// Pinning never reaches the network — see [LocalMailFlagsStore]. The
  /// `maxPinnedMails` cap is global across every connected account; pinning
  /// only changes sort priority inside a mail's existing folder.
  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    final grouped = _groupBySession(ids);
    if (pinned) {
      var free = MailRepository.maxPinnedMails - _totalPinnedCount();
      for (final entry in grouped.entries) {
        final session = entry.key;
        final store = session.flagsStore;
        if (store == null) continue;
        for (final id in entry.value) {
          if (free <= 0) break;
          if (session.pinnedIds.add(id)) free--;
        }
        await store.writePinned(session.pinnedIds);
        _replaceMany(
          session,
          entry.value,
          (e) => e.copyWith(isPinned: session.pinnedIds.contains(e.id)),
        );
      }
    } else {
      for (final entry in grouped.entries) {
        final session = entry.key;
        final store = session.flagsStore;
        if (store == null) continue;
        session.pinnedIds.removeAll(entry.value);
        await store.writePinned(session.pinnedIds);
        _replaceMany(session, entry.value, (e) => e.copyWith(isPinned: false));
      }
    }
    notifyListeners();
  }

  int _totalPinnedCount() =>
      _sessions.values.fold(0, (sum, s) => sum + s.pinnedIds.length);

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    await Future.wait(
      _groupBySession(ids).entries.map((e) {
        final session = e.key;
        return _bulkAndApply(session, starred ? 'star' : 'unstar', e.value, (
          succeeded,
        ) {
          starred
              ? session.starredIds.addAll(succeeded)
              : session.starredIds.removeAll(succeeded);
          _replaceMany(
            session,
            succeeded,
            (m) => m.copyWith(isStarred: starred),
          );
        });
      }),
    );
  }

  /// Marks that the user opened the reply screen. The "replied" flag itself
  /// is local-only (see [LocalMailFlagsStore]), but opening a reply also
  /// reads the mail, which the API *does* track — so that half goes through
  /// the real `read` action instead of being faked locally.
  @override
  Future<void> markAsReplied(List<String> ids) async {
    if (ids.isEmpty) return;
    await markAsRead(ids);
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final store = session.flagsStore;
      if (store == null) continue;
      session.repliedIds.addAll(entry.value);
      await store.writeReplied(session.repliedIds);
      _replaceMany(session, entry.value, (e) => e.copyWith(isReplied: true));
    }
    notifyListeners();
  }

  /// Marks that the user opened the forward screen — same split as
  /// [markAsReplied]: "forwarded" is local-only, the resulting read state
  /// goes through the real `read` action.
  @override
  Future<void> markAsForwarded(List<String> ids) async {
    if (ids.isEmpty) return;
    await markAsRead(ids);
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final store = session.flagsStore;
      if (store == null) continue;
      session.forwardedIds.addAll(entry.value);
      await store.writeForwarded(session.forwardedIds);
      _replaceMany(session, entry.value, (e) => e.copyWith(isForwarded: true));
    }
    notifyListeners();
  }

  static String _canonicalName(String name) =>
      name.trim().replaceAll('İ', 'i').toLowerCase();

  void _assertLabelNameIsFree(_Session session, String name, {String? selfId}) {
    final canonical = _canonicalName(name);
    if (canonical.isEmpty) throw ArgumentError('Etiket adı boş olamaz.');
    if (session.labels.any(
      (l) => l.id != selfId && _canonicalName(l.name) == canonical,
    )) {
      throw ArgumentError('Bu isimde bir etiket zaten var.');
    }
  }

  Future<void> _persistLabels(_Session session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeLabelDefs([
      for (final l in session.labels)
        {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
    ]);
    await store.writeLabelMap(session.labelMap);
  }

  void _restampLabels(_Session session, Iterable<String> ids) => _replaceMany(
    session,
    ids.toList(),
    (e) => e.copyWith(labelIds: session.labelMap[e.id] ?? const []),
  );

  /// Labels from every account in scope — the unified view unions them
  /// (dedup by id; account-local ids never collide in practice).
  @override
  List<MailLabel> getLabels() {
    final seen = <String>{};
    final result = <MailLabel>[];
    for (final session in _scopedSessions) {
      for (final label in session.labels) {
        if (seen.add(label.id)) result.add(label);
      }
    }
    return List.unmodifiable(result);
  }

  @override
  List<MailLabel> getLabelsForAccount(String accountId) =>
      List.unmodifiable(_sessions[accountId]?.labels ?? const <MailLabel>[]);

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
  }) async {
    final session = _primarySession;
    _assertLabelNameIsFree(session, name);
    final label = MailLabel(
      id: 'label-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      color: color,
    );
    session.labels = [...session.labels, label];
    await _persistLabels(session);
    notifyListeners();
    return label;
  }

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) async {
    final session = _sessionForLabel(id);
    if (session == null) return;
    final index = session.labels.indexWhere((l) => l.id == id);
    if (index < 0) return;
    _assertLabelNameIsFree(session, name, selfId: id);
    session.labels = [...session.labels]
      ..[index] = MailLabel(id: id, name: name.trim(), color: color);
    await _persistLabels(session);
    notifyListeners();
  }

  @override
  Future<void> deleteLabel(String labelId) async {
    final session = _sessionForLabel(labelId);
    if (session == null) return;
    session.labels = session.labels.where((l) => l.id != labelId).toList();
    final touched = [
      for (final e in session.labelMap.entries)
        if (e.value.contains(labelId)) e.key,
    ];
    for (final id in touched) {
      session.labelMap[id] = session.labelMap[id]!
          .where((l) => l != labelId)
          .toList();
    }
    await _persistLabels(session);
    _restampLabels(session, touched);
    notifyListeners();
  }

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    for (final entry in _groupBySession(emailIds).entries) {
      final session = entry.key;
      final ownedLabelIds = {
        for (final label in session.labels)
          if (labelIds.contains(label.id)) label.id,
      };
      if (ownedLabelIds.isEmpty) continue;
      for (final id in entry.value) {
        final cur = session.labelMap[id] ?? const <String>[];
        session.labelMap[id] = [
          ...cur,
          ...ownedLabelIds.where((labelId) => !cur.contains(labelId)),
        ];
      }
      await _persistLabels(session);
      _restampLabels(session, entry.value);
    }
    notifyListeners();
  }

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) async {
    for (final entry in _groupBySession(emailIds).entries) {
      final session = entry.key;
      for (final id in entry.value) {
        session.labelMap[id] = (session.labelMap[id] ?? const <String>[])
            .where((l) => !labelIds.contains(l))
            .toList();
      }
      await _persistLabels(session);
      _restampLabels(session, entry.value);
    }
    notifyListeners();
  }
}
