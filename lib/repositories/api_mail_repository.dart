import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/account_notification_settings.dart';
import '../models/account_sync_scope.dart';
import '../models/compose_prefill.dart';
import '../models/compose_limits.dart';
import '../models/email.dart';
import '../models/mail_header_entry.dart';
import '../models/mail_security.dart';
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../models/mail_custom_folder.dart';
import '../models/mail_folder_info.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_signature.dart';
import '../models/mail_session.dart';
import '../models/mail_template.dart';
import '../models/manual_contact.dart';
import '../models/remote_search_result.dart';
import '../models/scheduled_send.dart';
import '../utils/idempotency_key.dart';
import '../models/scheduled_send_detail.dart';
import '../models/trusted_sender.dart';
import '../utils/mail_ordering.dart';
import '../services/account_data_purger.dart';
import '../services/api_auth_service.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/api_mail_service.dart';
import '../services/device_identifier_provider.dart';
import '../services/local_mail_flags_store.dart';
import '../services/mail_cache.dart';
import '../models/attachment_download_state.dart';
import '../services/attachment_download_manager.dart';
import '../services/attachment_auto_download_policy.dart';
import '../services/token_store.dart';
import '../services/session_store.dart';
import 'api/account_session.dart';
import 'api/account_settings_module.dart';
import 'api/scheduled_send_module.dart';
import 'api/session_registry.dart';
import 'api/signature_module.dart';
import 'api/template_module.dart';
import 'mail_repository.dart';

const _allMailSourceFolders = [
  MailFolder.inbox,
  MailFolder.sent,
  MailFolder.drafts,
  MailFolder.spam,
  MailFolder.trash,
  MailFolder.archive,
];

typedef _MailLocationSnapshot = ({
  Map<MailFolder, (Email, int)> folders,
  Map<String, (Email, int)> customFolders,
});

/// [MailRepository] backed by the real backend. Pins, snoozes, labels and
/// manual contacts are backend-owned with an offline device cache and queue;
/// replied/forwarded-from-app flags stay local per account.
///
/// Every connected mailbox gets its own [AccountSession] — its own authenticated
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
    this._snoozeExpiryCheckInterval = const Duration(seconds: 30),
    AttachmentDownloadManager? attachmentDownloadManager,
    AttachmentAutoDownloader? attachmentAutoDownloader,
    AccountDataPurger? accountDataPurger,
  }) : _initialAuthService = authService,
       _initialMailService = mailService,
       _attachmentDownloadManager =
           attachmentDownloadManager ?? AttachmentDownloadManager.instance,
       _attachmentAutoDownloader =
           attachmentAutoDownloader ?? AttachmentAutoDownloader(),
       _accountDataPurger =
           accountDataPurger ??
           AccountDataPurger(
             attachments:
                 attachmentDownloadManager ??
                 AttachmentDownloadManager.instance,
           );

  // Test seams: the first session created (via login/connect/restore) uses
  // the injected auth+mail service pair when present; every session after
  // that uses [_sessionFactory] when supplied, otherwise a real one.
  final ApiAuthService? _initialAuthService;
  final ApiMailService? _initialMailService;
  final ({ApiAuthService authService, ApiMailService mailService}) Function()?
  _sessionFactory;
  bool _initialConsumed = false;

  final Future<MailCache> Function()? _openCache;
  final AttachmentDownloadManager _attachmentDownloadManager;
  final AttachmentAutoDownloader _attachmentAutoDownloader;
  final AccountDataPurger _accountDataPurger;
  MailCache? _cache;

  /// Every connected account's session, keyed by account id, in connection
  /// order (a `Map` literal is insertion-ordered) — that order is also
  /// [accounts]' order and the order accounts restore in at app launch.
  final SessionRegistry _registry = SessionRegistry();
  Map<String, AccountSession> get _sessions => _registry.sessions;
  final Map<String, ComposeLimits> _composeLimits = {};
  final Set<String> _remoteImageMailIds = {};

  /// `null` selects the unified mailbox (every session); non-null narrows
  /// every read/write below to that one session.
  String? get _activeAccountId => _registry.activeAccountId;
  set _activeAccountId(String? id) => _registry.activeAccountId = id;

  /// Coarse periodic sweep so a snoozed-folder/inbox view open on screen
  /// re-invalidates itself the moment a snooze deadline passes, instead of
  /// only re-filtering on the next explicit [getEmailsInFolder] call (which
  /// nothing forces while the user just sits looking at the list). Runs
  /// only while at least one session is connected — see
  /// [_startSnoozeExpiryTimerIfNeeded]/[logout].
  Timer? _snoozeExpiryTimer;

  /// Soonest upcoming snooze deadline (epoch millis) across every session,
  /// or null when nothing is snoozed with a future deadline. Lets the timer
  /// tick cheaply compare one integer instead of rescanning every session's
  /// snoozes on every tick — only a tick that actually crosses this
  /// deadline rescans and fires [notifyListeners].
  int? _watchedSnoozeDeadlineMs;

  /// How often [_snoozeExpiryTimer] ticks — 30s in production, overridable
  /// (test-only) so a unit test can observe an expiry sweep in
  /// milliseconds instead of real seconds.
  final Duration _snoozeExpiryCheckInterval;

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
      await _signOutSession(session);
    }
    _activeAccountId = null;
    _stopSnoozeExpiryTimer();
    await SessionStore.clear();
    _touch();
    notifyListeners();
  }

  @override
  Future<void> signOutAccount(String accountId) async {
    final session = _sessions[accountId];
    if (session == null) return;
    if (_sessions.length == 1) return logout();
    await _signOutSession(session);
    await SessionStore.removeEmail(session.account.email);
    if (_activeAccountId == accountId) _activeAccountId = null;
    _touch();
    notifyListeners();
  }

  /// Local-first sign-out of one account: remote revocation may fail while
  /// offline, but tokens and every on-device trace are always removed.
  Future<void> _signOutSession(AccountSession session) async {
    try {
      await _unregisterDeviceFor(session);
      await session.authService.logout();
    } catch (_) {
      // Logout is local-first: remote revocation may fail while offline.
    } finally {
      await session.authService.tokenStore.clear(session.account.id);
      session.persistTimer?.cancel();
      _cancelReconnectRetry(session);
      await _purgeLocalData(session);
      _sessions.remove(session.account.id);
    }
  }

  /// Wipes every on-device trace of [session]'s account (see
  /// [AccountDataPurger]); credentials are cleared by the caller.
  Future<void> _purgeLocalData(AccountSession session) =>
      _accountDataPurger.purge(
        accountId: session.account.id,
        accountEmail: session.account.email,
        cache: _cache,
      );

  Future<void> _unregisterDeviceFor(AccountSession session) async {
    final deviceId = session.deviceId;
    if (deviceId == null) return;
    session.deviceId = null;
    try {
      await session.mailService.unregisterDevice(deviceId);
    } catch (_) {
      // Best-effort — the server registration expires on its own.
    }
  }

  Future<void> _expireSession(String accountId) async {
    final session = _sessions.remove(accountId);
    if (session == null) return;
    await session.authService.tokenStore.clear(accountId);
    session.persistTimer?.cancel();
    _cancelReconnectRetry(session);
    await _purgeLocalData(session);
    await SessionStore.removeEmail(session.account.email);
    if (_activeAccountId == accountId) _activeAccountId = null;
    if (_sessions.isEmpty) _stopSnoozeExpiryTimer();
    _touch();
    notifyListeners();
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
  void _scheduleReconnectRetry(AccountSession session) {
    session.reconnectTimer?.cancel();
    session.reconnectTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _retryConnection(session);
    });
  }

  void _cancelReconnectRetry(AccountSession session) {
    session.reconnectTimer?.cancel();
    session.reconnectTimer = null;
  }

  /// Starts the sweep in [_snoozeExpiryTimer] the first time any session
  /// connects; a no-op while it's already running.
  void _startSnoozeExpiryTimerIfNeeded() {
    _snoozeExpiryTimer ??= Timer.periodic(
      _snoozeExpiryCheckInterval,
      (_) => _checkSnoozeExpiry(),
    );
  }

  void _stopSnoozeExpiryTimer() {
    _snoozeExpiryTimer?.cancel();
    _snoozeExpiryTimer = null;
    _watchedSnoozeDeadlineMs = null;
  }

  /// Recomputes [_watchedSnoozeDeadlineMs] from every session's current
  /// snoozes. Called after anything that can change a snooze deadline
  /// (activating a session, [setSnoozed]) and after the watched deadline
  /// itself fires, so the timer always knows the next moment worth waking
  /// up for.
  void _recomputeWatchedSnoozeDeadline() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? soonest;
    for (final session in _sessions.values) {
      for (final ms in session.snoozedUntil.values) {
        if (ms > now && (soonest == null || ms < soonest)) soonest = ms;
      }
    }
    _watchedSnoozeDeadlineMs = soonest;
  }

  /// The 30s tick: cheap in the common case (one integer comparison), and
  /// only rescans/notifies on the tick that actually crosses the soonest
  /// deadline — that mail just came back from snooze, so any open snoozed
  /// folder or inbox view must self-update without waiting for the user to
  /// pull-to-refresh or navigate away and back.
  void _checkSnoozeExpiry() {
    final watched = _watchedSnoozeDeadlineMs;
    if (watched == null) return;
    if (DateTime.now().millisecondsSinceEpoch < watched) return;
    _recomputeWatchedSnoozeDeadline();
    notifyListeners();
  }

  Future<void> _retryConnection(AccountSession session) async {
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
    session.account = account.copyWith(quota: session.account.quota);
    unawaited(_accountSettings.refreshSessionQuota(session));
    _touch();
    notifyListeners();
  }

  /// Upserts this device's push registration for every connected account and
  /// remembers each successful registration id for [logout]. A failure for
  /// one account never blocks the others, but remains visible to callers.
  @override
  Future<Set<String>> registerCurrentDevice({
    required String fcmToken,
    required String appVersion,
    required String locale,
  }) async {
    final registrations = await Future.wait(
      _sessions.entries.map((entry) async {
        try {
          final registration = await entry.value.mailService.registerDevice(
            token: fcmToken,
            platform: defaultTargetPlatform.name.toLowerCase(),
            appVersion: appVersion,
            locale: locale,
          );
          entry.value.deviceId = registration.id;
          return entry.key;
        } catch (_) {
          return null;
        }
      }),
    );
    return registrations.whereType<String>().toSet();
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
    MailServerSettings? serverSettings,
  }) async {
    if (serverSettings != null) {
      final account = await connectManual(
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
      _activeAccountId = null;
      _touch();
      notifyListeners();
      return account;
    }
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
    final session = AccountSession(
      authService: authService,
      mailService: mailService,
      account: account,
    );
    _sessions[account.id] = session;
    authService.client.onAuthenticationLost = () => _expireSession(account.id);
    try {
      _cache ??= await _openCacheOrMemory();
      final flags = LocalMailFlagsStore(account.id, _cache!);
      await flags.migrateLegacyPrefs();
      session.flagsStore = flags;
      await _hydrateLocalSessionState(session, flags);
      _recomputeWatchedSnoozeDeadline();
      final queuedDrafts = _cache!.loadDraftQueue(account.id);
      if (queuedDrafts.isNotEmpty) {
        session.emails[MailFolder.drafts] = queuedDrafts;
        _scheduleDraftSync();
      }
      _startSnoozeExpiryTimerIfNeeded();
      _hydrateFolderMapFromCache(session);
      final hydrated = await _hydrateFromCache(session);
      final hasCachedMailbox = hydrated || session.folderIds.isNotEmpty;
      if (hasCachedMailbox) {
        session.offline = true;
        await SessionStore.saveAccountId(account.email, account.id);
        notifyListeners();
        unawaited(
          Future<void>.delayed(
            Duration.zero,
            () => _refreshActivatedCachedSession(session, flags),
          ),
        );
        return session.account;
      }
      await _loadRemoteSessionState(session, flags);
      await _loadMailbox(session);
      await _seedStarred(session);
      unawaited(_seedThreadSizes(session));
      try {
        final refreshed = await mailService.getAccount();
        session.account = refreshed.copyWith(quota: session.account.quota);
      } catch (_) {
        // Token-derived account remains usable until server details load.
      }
      unawaited(_accountSettings.refreshSessionQuota(session));
      unawaited(_signatures.migrateLegacy(session));
      await SessionStore.saveAccountId(account.email, account.id);
      notifyListeners();
      return session.account;
    } catch (_) {
      _cancelReconnectRetry(session);
      _sessions.remove(account.id);
      _touch();
      rethrow;
    }
  }

  Future<void> _hydrateLocalSessionState(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    session.pinnedIds = await flags.readPinned();
    session.repliedFromKaydetMailIds = await flags.readRepliedFromKaydetMail();
    session.forwardedFromKaydetMailIds = await flags
        .readForwardedFromKaydetMail();
    session.repliedFromKaydetMailThreadIds = await flags
        .readRepliedFromKaydetMailThreads();
    session.forwardedFromKaydetMailThreadIds = await flags
        .readForwardedFromKaydetMailThreads();
    session.labels = [
      for (final label in await flags.readLabelDefs())
        MailLabel(
          id: label['id'] as String,
          name: label['name'] as String,
          color: Color(_unsignedArgb(label['color'] as int)),
        ),
    ];
    session.labelMap = await flags.readLabelMap();
    session.manualContacts = [
      for (final contact in await flags.readContacts())
        ManualContact(
          id: contact['id'] as String,
          accountId: session.account.id,
          email: contact['email'] as String,
          displayName: contact['displayName'] as String?,
        ),
    ];
    session.snoozedUntil = await flags.readSnoozed();
  }

  Future<void> _loadRemoteSessionState(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    session.pinnedIds = await _loadPinnedIds(session, flags);
    session.repliedFromKaydetMailIds = await flags.readRepliedFromKaydetMail();
    session.forwardedFromKaydetMailIds = await flags
        .readForwardedFromKaydetMail();
    session.repliedFromKaydetMailThreadIds = await flags
        .readRepliedFromKaydetMailThreads();
    session.forwardedFromKaydetMailThreadIds = await flags
        .readForwardedFromKaydetMailThreads();
    await _loadLabels(session, flags);
    await _loadManualContacts(session, flags);
    session.snoozedUntil = await _loadSnoozedUntil(session, flags);
  }

  Future<void> _refreshActivatedCachedSession(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      await _loadRemoteSessionState(session, flags);
      await _loadMailbox(session);
      await _seedStarred(session);
      unawaited(_seedThreadSizes(session));
      try {
        final refreshed = await session.mailService.getAccount();
        session.account = refreshed.copyWith(quota: session.account.quota);
      } catch (_) {}
      unawaited(_accountSettings.refreshSessionQuota(session));
      unawaited(_signatures.migrateLegacy(session));
      notifyListeners();
    } catch (_) {
      session.offline = true;
      _scheduleReconnectRetry(session);
      notifyListeners();
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

  /// Pin state is account-scoped on the backend now; falls back to the
  /// local cache (and re-seeds it on success) so pins still show while
  /// offline.
  Future<Set<String>> _loadPinnedIds(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      final ids = (await session.mailService.getPinnedMailIds()).toSet();
      await flags.writePinned(ids);
      return ids;
    } catch (_) {
      return flags.readPinned();
    }
  }

  /// Same backend-first, cache-fallback shape as [_loadPinnedIds] for
  /// snooze deadlines (stored as UTC epoch millis locally).
  Future<Map<String, int>> _loadSnoozedUntil(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      final snoozed = await session.mailService.getSnoozed();
      final asMillis = {
        for (final entry in snoozed.entries)
          entry.key: entry.value.millisecondsSinceEpoch,
      };
      await flags.writeSnoozed(asMillis);
      return asMillis;
    } catch (_) {
      return flags.readSnoozed();
    }
  }

  /// Backend-first load of label definitions and the mail-id -> label-ids
  /// assignment map, same shape as [_loadPinnedIds]/[_loadSnoozedUntil]:
  /// migrate any pre-cutover local labels once, then fetch the backend's
  /// view and re-seed the local cache from it so labels still show while
  /// offline.
  Future<void> _loadLabels(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    await _migrateLegacyLabels(session, flags);
    try {
      final defs = await session.mailService.getLabels();
      session.labels = [
        for (final d in defs)
          MailLabel(
            id: d['id'] as String,
            name: d['name'] as String,
            color: Color(_unsignedArgb(d['color'] as int)),
          ),
      ];
      session.labelMap = await session.mailService.getLabelAssignments();
      await flags.writeLabelDefs([
        for (final l in session.labels)
          {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
      ]);
      await flags.writeLabelMap(session.labelMap);
    } catch (_) {
      session.labels = [
        for (final d in await flags.readLabelDefs())
          MailLabel(
            id: d['id'] as String,
            name: d['name'] as String,
            color: Color(_unsignedArgb(d['color'] as int)),
          ),
      ];
      session.labelMap = await flags.readLabelMap();
    }
  }

  /// Backend-first load of manually-added contacts, same shape as
  /// [_loadLabels] minus any migration — this is a new feature with no
  /// pre-cutover local data to carry forward.
  Future<void> _loadManualContacts(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      final defs = await session.mailService.getContacts();
      session.manualContacts = [
        for (final d in defs)
          ManualContact(
            id: d['id'] as String,
            accountId: session.account.id,
            email: d['email'] as String,
            displayName: d['displayName'] as String?,
          ),
      ];
      await flags.writeContacts([
        for (final c in session.manualContacts)
          {'id': c.id, 'email': c.email, 'displayName': c.displayName},
      ]);
    } catch (_) {
      session.manualContacts = [
        for (final d in await flags.readContacts())
          ManualContact(
            id: d['id'] as String,
            accountId: session.account.id,
            email: d['email'] as String,
            displayName: d['displayName'] as String?,
          ),
      ];
    }
  }

  /// One-time migration for pre-cutover installs: if the backend has no
  /// labels yet, push the local set once — the account's own pre-existing
  /// labels (including any the user renamed/deleted from the defaults) if
  /// there are any, otherwise [LocalMailFlagsStore.defaultLabels] for a
  /// brand-new account — then replay the local mail-to-label assignments
  /// against the newly created backend ids. Best-effort; a failure here
  /// Cached labels remain available when migration fails.
  /// Seeds required defaults, then migrates any pre-cutover labels and their
  /// assignments. Server labels stay authoritative when names collide.
  Future<void> _migrateLegacyLabels(
    AccountSession session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      final existing = await session.mailService.getLabels();
      final idsByName = {
        for (final label in existing)
          (label['name'] as String).toLowerCase(): label['id'] as String,
      };
      final idRemap = <String, String>{};
      final localDefs = await flags.readLabelDefs();
      final defs = [...LocalMailFlagsStore.defaultLabels, ...localDefs];
      for (final d in defs) {
        final name = d['name'] as String;
        final normalizedName = name.toLowerCase();
        var serverId = idsByName[normalizedName];
        if (serverId == null) {
          final created = await session.mailService.createLabel(
            name,
            _signedArgb(d['color'] as int),
          );
          serverId = created['id'] as String;
          idsByName[normalizedName] = serverId;
        }
        idRemap[d['id'] as String] = serverId;
      }
      for (final entry in (await flags.readLabelMap()).entries) {
        final remapped = [
          for (final oldId in entry.value)
            if (idRemap[oldId] != null) idRemap[oldId]!,
        ];
        if (remapped.isNotEmpty) {
          await session.mailService.assignLabels([entry.key], remapped);
        }
      }
    } catch (_) {
      // Best-effort — a failure here must never affect login. Cached labels
      // remain available via [_loadLabels] until migration can run again.
    }
  }

  static int _signedArgb(int color) =>
      color >= 0x80000000 ? color - 0x100000000 : color;

  static int _unsignedArgb(int color) => color & 0xFFFFFFFF;

  /// Restores the last-known server-folder-id -> [MailFolder] mapping so
  /// cached mail stays actionable (open, move, sync) even before — or
  /// without ever reaching — a successful [_loadMailbox] this session.
  void _hydrateFolderMapFromCache(AccountSession session) {
    final saved = _cache?.loadFolders(session.account.id) ?? const {};
    if (saved.isEmpty) return;
    session.folderIds.clear();
    session.folderTypeById.clear();
    for (final entry in saved.entries) {
      if (entry.value == 'custom') continue;
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
  Future<bool> _hydrateFromCache(AccountSession session) async {
    try {
      session.persisted = {};
      final queued =
          _cache?.loadDraftQueue(session.account.id) ?? const <Email>[];
      final queuedIds = queued.map((e) => e.id).toSet();
      final cached = [
        ...queued,
        ...(_cache?.load(session.account.id) ?? const <Email>[]).where(
          (e) => !queuedIds.contains(e.id),
        ),
      ];
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
      final custom = _cache?.loadCustomFolders(session.account.id) ?? const {};
      session.customFolderEmails
        ..clear()
        ..addAll({
          for (final entry in custom.entries)
            entry.key: [
              for (final email in entry.value) session.stampLocalFlags(email),
            ],
        });
      unawaited(_attachmentAutoDownloader.preloadListed(this, cached));
      return cached.isNotEmpty || custom.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ponytail: diffs the whole loaded mailbox by identity on every debounced
  // change; switch to per-row dirty tracking if mailboxes grow very large.
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
                for (final m in e.value) m.id: m,
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
    await _purgeLocalData(session);
    _sessions.remove(accountId);
    await SessionStore.removeEmail(session.account.email);
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
    final savedAccountId = await SessionStore.loadAccountId(email);
    final candidateId =
        savedAccountId != null &&
            accountIds.contains(savedAccountId) &&
            !_sessions.containsKey(savedAccountId)
        ? savedAccountId
        : accountIds.firstWhere(
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
  /// The session an account-level call targets: [accountId] when given,
  /// otherwise the active account, otherwise the first connected one.
  AccountSession? _sessionForSettings(String? accountId) => accountId != null
      ? _sessions[accountId]
      : _sessions[_activeAccountId] ?? _sessions.values.firstOrNull;

  @override
  Future<List<MailSession>> getSessions({String? accountId}) async {
    final session = _sessionForSettings(accountId);
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
  Future<void> revokeSession(String sessionId, {String? accountId}) async {
    final session = _sessionForSettings(accountId);
    if (session == null) return;
    await session.mailService.deleteSession(sessionId);
  }

  Future<void> _loadMailbox(AccountSession session) async {
    _applyFolderMap(session, await session.mailService.getFolders());
    _cancelReconnectRetry(session);
    session.offline = false;
    await _replayQueuedMutations(session);
    _persistFolderMap(session);
    notifyListeners();
  }

  /// Rebuilds the logical-folder map from the server list. `folderType` is
  /// the effective role, so user overrides (e.g. `INBOX.Sent Items` as Sent)
  /// resolve here without extra handling.
  void _applyFolderMap(AccountSession session, List<ApiMailFolder> folders) {
    session.folderIds.clear();
    session.folderTypeById.clear();
    session.serverUnread.clear();
    for (final folder in folders) {
      if (!folder.isAvailable) continue;
      final logical = _logicalFolderForType(folder.type);
      if (logical != null) {
        session.folderIds[logical] = folder.id;
        session.folderTypeById[folder.id] = logical;
        final unread = folder.unreadCount;
        if (unread != null) session.serverUnread[logical] = unread;
      }
    }
    _applyCustomFolderLists(session, folders);
  }

  void _applyCustomFolderLists(
    AccountSession session,
    List<ApiMailFolder> folders,
  ) {
    session.allFolders = [
      for (final folder in folders)
        if (folder.isAvailable) folder,
    ];
    session.customFolders = folders
        .where((folder) => folder.type == 'Custom' && folder.isAvailable)
        .toList();
    session.roleOverrideFolders = folders
        .where((folder) => folder.roleOverride != null && folder.isAvailable)
        .toList();
  }

  static MailFolder? _logicalFolderForType(String type) =>
      switch (type.toLowerCase()) {
        'inbox' => MailFolder.inbox,
        'sent' => MailFolder.sent,
        'drafts' => MailFolder.drafts,
        'trash' => MailFolder.trash,
        'junk' => MailFolder.spam,
        'spam' => MailFolder.spam,
        'archive' => MailFolder.archive,
        _ => null,
      };

  /// Best-effort: remembers the current folder map so
  /// [_hydrateFolderMapFromCache] can restore it on a future offline cold
  /// start.
  void _persistFolderMap(AccountSession session) {
    final cache = _cache;
    if (cache == null) return;
    try {
      cache.saveFolders(session.account.id, {
        for (final entry in session.folderIds.entries)
          entry.value: entry.key.name,
        for (final folder in session.customFolders) folder.id: 'custom',
      });
    } catch (_) {
      // Cache is an optimization; never surface its failures.
    }
  }

  @override
  int unreadCount(MailFolder folder) => folder == MailFolder.all
      ? getEmailsInFolder(MailFolder.all).where((email) => !email.isRead).length
      : _scopedSessions.fold(
          0,
          (sum, session) =>
              sum +
              (session.serverUnread[folder] ??
                  (session.emails[folder]
                          ?.where((email) => !email.isRead)
                          .length ??
                      0)),
        );

  /// Best-effort re-read of server counts after a mutation.
  Future<void> _refreshCountsFor(AccountSession session) async {
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
  Future<void> _seedStarred(AccountSession session) async {
    try {
      final flagged = <Email>[];
      for (var page = 1; ; page++) {
        final result = await session.mailService.search(
          query: '',
          flagged: true,
          page: page,
          pageSize: 100,
          resolveFolder: session.resolveFolder,
        );
        flagged.addAll(result);
        if (result.length < 100) break;
      }
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
    AccountSession session,
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
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          idSet.contains(email.id) ? update(email) : email,
      ];
    }
  }

  /// Re-derives every loaded mail's flags (backend-backed pin/labels,
  /// IMAP-backed star and local replied/forwarded) from [session]'s sets.
  /// Used instead of [_replaceMany] when a change can affect mail beyond
  /// the ids the caller touched directly — e.g. marking one message replied
  /// also marks every other loaded message in its thread.
  void _restampFlags(AccountSession session) {
    _touch();
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          session.stampLocalFlags(email),
      ];
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          session.stampLocalFlags(email),
      ];
    }
  }

  /// Moves every cached mail in [ids] into [targetFolder]'s bucket within
  /// [session], stamping the new folder on each and dropping it from
  /// wherever it used to live. Mails not currently cached are ignored.
  void _moveMany(
    AccountSession session,
    Iterable<String> ids,
    MailFolder targetFolder,
  ) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    final moved = <Email>[
      for (final list in session.customFolderEmails.values)
        for (final email in list)
          if (idSet.contains(email.id)) email.copyWith(folder: targetFolder),
    ];
    _dropFromCustomFolderMails(session, idSet);
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
  List<String> _idsInTrashOrSpam(AccountSession session, Iterable<String> ids) {
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

  static bool _isOfflineFailure(Object error) =>
      error is ApiException &&
      (error.category == ApiErrorCategory.network ||
          error.category == ApiErrorCategory.timeout);

  void _markOffline(AccountSession session) {
    session.offline = true;
    _scheduleReconnectRetry(session);
  }

  /// Captures exact local bucket positions so rejected requests can be rolled
  /// back without replacing unrelated cached mail.
  Map<String, _MailLocationSnapshot> _snapshotMailLocations(
    AccountSession session,
    Iterable<String> ids,
  ) {
    final snapshots = {
      for (final id in ids)
        id: (
          folders: <MailFolder, (Email, int)>{},
          customFolders: <String, (Email, int)>{},
        ),
    };
    for (final entry in session.emails.entries) {
      for (var index = 0; index < entry.value.length; index++) {
        final email = entry.value[index];
        final snapshot = snapshots[email.id];
        if (snapshot != null) {
          snapshot.folders[entry.key] = (email, index);
        }
      }
    }
    for (final entry in session.customFolderEmails.entries) {
      for (var index = 0; index < entry.value.length; index++) {
        final email = entry.value[index];
        final snapshot = snapshots[email.id];
        if (snapshot != null) {
          snapshot.customFolders[entry.key] = (email, index);
        }
      }
    }
    return snapshots;
  }

  Map<String, _MailLocationSnapshot> _selectMailLocations(
    Map<String, _MailLocationSnapshot> snapshots,
    Iterable<String> ids,
  ) {
    final selected = <String, _MailLocationSnapshot>{};
    for (final id in ids) {
      final snapshot = snapshots[id];
      if (snapshot != null) selected[id] = snapshot;
    }
    return selected;
  }

  void _restoreMailLocations(
    AccountSession session,
    Map<String, _MailLocationSnapshot> snapshots,
  ) {
    if (snapshots.isEmpty) return;
    final ids = snapshots.keys.toSet();
    _touch();
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          if (!ids.contains(email.id)) email,
      ];
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      session.customFolderEmails[folderId] = [
        for (final email in session.customFolderEmails[folderId]!)
          if (!ids.contains(email.id)) email,
      ];
    }
    final folderLocations = <MailFolder, List<(Email, int)>>{};
    final customFolderLocations = <String, List<(Email, int)>>{};
    for (final entry in snapshots.entries) {
      for (final location in entry.value.folders.entries) {
        folderLocations
            .putIfAbsent(location.key, () => <(Email, int)>[])
            .add(location.value);
      }
      for (final location in entry.value.customFolders.entries) {
        customFolderLocations
            .putIfAbsent(location.key, () => <(Email, int)>[])
            .add(location.value);
      }
      final originalEmail =
          entry.value.folders.values.firstOrNull?.$1 ??
          entry.value.customFolders.values.firstOrNull?.$1;
      if (originalEmail != null) {
        if (originalEmail.isStarred) {
          session.starredIds.add(originalEmail.id);
        } else {
          session.starredIds.remove(originalEmail.id);
        }
      }
    }
    for (final entry in folderLocations.entries) {
      entry.value.sort((a, b) => a.$2.compareTo(b.$2));
      final list = session.emails.putIfAbsent(entry.key, () => <Email>[]);
      for (final (email, index) in entry.value) {
        list.insert(min(index, list.length), email);
      }
    }
    for (final entry in customFolderLocations.entries) {
      entry.value.sort((a, b) => a.$2.compareTo(b.$2));
      final list = session.customFolderEmails.putIfAbsent(
        entry.key,
        () => <Email>[],
      );
      for (final (email, index) in entry.value) {
        list.insert(min(index, list.length), email);
      }
    }
  }

  /// Applies a bulk action immediately in the local cache, then reconciles
  /// per-item results with the server. Transport failures keep the optimistic
  /// state and persist a mutation for replay; rejected items restore their
  /// previous cache locations. Permanent `delete` is handled separately.
  Future<List<BulkActionResult>> _bulkAndApplyOrQueue(
    AccountSession session,
    String operation,
    List<String> ids,
    void Function(List<String> succeededIds) apply, {
    String? folderId,
  }) async {
    if (ids.isEmpty) return const [];
    final snapshots = _snapshotMailLocations(session, ids);
    apply(ids);
    notifyListeners();
    List<BulkActionResult> results;
    try {
      results = await session.mailService.bulkAction(
        operation,
        ids,
        folderId: folderId,
      );
    } catch (error) {
      if (_isOfflineFailure(error)) {
        _markOffline(session);
        final store = session.flagsStore;
        if (store != null) {
          try {
            for (final id in ids) {
              await store.queueMutation(id, operation, folderId: folderId);
            }
          } catch (_) {
            _restoreMailLocations(
              session,
              _selectMailLocations(snapshots, ids),
            );
            notifyListeners();
            rethrow;
          }
        }
        return const [];
      }
      _restoreMailLocations(session, _selectMailLocations(snapshots, ids));
      notifyListeners();
      rethrow;
    }
    final successfulIds = results
        .where((result) => result.success)
        .map((result) => result.mailId)
        .toSet();
    final failedSnapshots = _selectMailLocations(
      snapshots,
      ids.where((id) => !successfulIds.contains(id)),
    );
    if (failedSnapshots.isNotEmpty) {
      _restoreMailLocations(session, failedSnapshots);
      notifyListeners();
    }
    final store = session.flagsStore;
    if (store != null) {
      final category = mutationCategoryFor(operation);
      for (final id in successfulIds) {
        await store.clearQueuedMutation(id, category);
      }
    }
    unawaited(_refreshCountsFor(session));
    return results;
  }

  void _throwForFailedBulkResults(
    Iterable<Iterable<BulkActionResult>> accountResults,
  ) {
    final failure = accountResults
        .expand((results) => results)
        .where((result) => !result.success)
        .firstOrNull;
    if (failure != null) {
      throw ApiException(
        status: 0,
        code: failure.code ?? 'mail_operation_failed',
      );
    }
  }

  /// Replays queued mail, pin/snooze/label and manual contact mutations.
  /// Transport failures remain queued for the next reconnect. Server
  /// rejections are dropped and surfaced through [offlineMutationConflicts];
  /// backend-owned state is re-read to replace rejected optimistic changes.
  /// Mail changes in the same category and contact changes for the same id
  /// collapse at queue time (see `LocalMailFlagsStore.queueMutation`).
  Future<void> _replayQueuedMutations(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    final all = await store.readQueuedMutations();
    if (all.isEmpty) return;
    final contacts = [
      for (final m in all)
        if (_contactOperations.contains(m.operation)) m,
    ];
    if (contacts.isNotEmpty) {
      await _replayManualContacts(session, store, contacts);
    }
    final queued = [
      for (final m in all)
        if (!_appStateOperations.contains(m.operation) &&
            !_contactOperations.contains(m.operation))
          m,
    ];
    final appState = [
      for (final m in all)
        if (_appStateOperations.contains(m.operation)) m,
    ];
    if (queued.isEmpty) {
      if (appState.isNotEmpty) await _replayAppState(session, store, appState);
      return;
    }
    final byOp = <(String, String?), List<QueuedMutation>>{};
    for (final mutation in queued) {
      byOp
          .putIfAbsent((mutation.operation, mutation.folderId), () => [])
          .add(mutation);
    }
    var changed = false;
    for (final entry in byOp.entries) {
      final (operation, folderId) = entry.key;
      final ids = [for (final m in entry.value) m.mailId];
      final category = mutationCategoryFor(operation, folderId);
      List<BulkActionResult> results;
      try {
        results = await session.mailService.bulkAction(
          operation,
          ids,
          folderId: folderId,
        );
      } catch (_) {
        continue; // Still offline; the next reconnect retries.
      }
      final restored = <String>[];
      for (final r in results) {
        if (r.success) {
          await store.clearQueuedMutation(r.mailId, category);
          changed = true;
          if (operation == 'restore') restored.add(r.mailId);
        } else if (r.code == 'mail_operation_conflict' ||
            r.code == 'mailbox_changed' ||
            r.code == 'mail_not_found') {
          await store.clearQueuedMutation(r.mailId, category);
          session.mutationConflicts.add(r.mailId);
          changed = true;
        }
        // Any other failure (e.g. reauthentication needed) stays queued.
      }
      // The offline placeholder filed a queued restore into Inbox (see
      // `moveToFolder`) — now that the server confirmed it, correct it to
      // wherever it actually came from, same as the online restore path.
      if (restored.isNotEmpty) await _fileRestored(session, restored);
    }
    if (changed) notifyListeners();
    if (appState.isNotEmpty) await _replayAppState(session, store, appState);
  }

  static const _appStateOperations = {
    'pin',
    'unpin',
    'snooze',
    'unsnooze',
    'label_add',
    'label_remove',
  };

  /// Replays queued pin/snooze/label changes. A still-unreachable backend
  /// leaves them queued; a server rejection (e.g. pin cap reached on another
  /// device) drops the mutation and surfaces it via [offlineMutationConflicts].
  /// Once nothing of that kind is left queued, pins, snoozes and label
  /// assignments are re-read from the backend so the local cache matches the
  /// authoritative state.
  Future<void> _replayAppState(
    AccountSession session,
    LocalMailFlagsStore store,
    List<QueuedMutation> queued,
  ) async {
    var stillQueued = false;
    final groups = <(String, String?), List<String>>{};
    for (final m in queued) {
      final key = m.operation.contains('snooze')
          ? (m.operation, '${m.mailId}\u0000${m.folderId ?? ''}')
          : (m.operation, m.folderId);
      groups.putIfAbsent(key, () => []).add(m.mailId);
    }
    for (final MapEntry(key: (operation, argument), value: ids)
        in groups.entries) {
      Future<void> drop(Iterable<String> mailIds) async {
        for (final id in mailIds) {
          await store.clearQueuedMutation(
            id,
            mutationCategoryFor(
              operation,
              operation.startsWith('label') ? argument : null,
            ),
          );
          session.mutationConflicts.add(id);
        }
      }

      try {
        switch (operation) {
          case 'pin' || 'unpin':
            final results = await session.mailService.setPinned(
              ids,
              operation == 'pin',
            );
            for (final r in results) {
              if (r.success) {
                await store.clearQueuedMutation(r.mailId, 'pin_state');
              } else {
                await drop([r.mailId]);
              }
            }
          case 'snooze':
            final until = DateTime.parse(argument!.split('\u0000').last);
            await session.mailService.setSnooze(ids.single, until);
            await store.clearQueuedMutation(ids.single, 'snooze_state');
          case 'unsnooze':
            await session.mailService.clearSnooze(ids.single);
            await store.clearQueuedMutation(ids.single, 'snooze_state');
          case 'label_add' || 'label_remove':
            operation == 'label_add'
                ? await session.mailService.assignLabels(ids, [argument!])
                : await session.mailService.unassignLabels(ids, [argument!]);
            for (final id in ids) {
              await store.clearQueuedMutation(
                id,
                mutationCategoryFor(operation, argument),
              );
            }
        }
      } catch (error) {
        if (_isOfflineFailure(error)) {
          stillQueued = true;
        } else if (error is ApiException) {
          await drop(ids);
        } else {
          stillQueued = true;
        }
      }
    }
    if (stillQueued) return;
    session.pinnedIds = await _loadPinnedIds(session, store);
    session.snoozedUntil = await _loadSnoozedUntil(session, store);
    try {
      session.labelMap = await session.mailService.getLabelAssignments();
      await store.writeLabelMap(session.labelMap);
    } catch (_) {}
    _recomputeWatchedSnoozeDeadline();
    _restampFlags(session);
    _restampLabels(session, [
      for (final list in session.emails.values)
        for (final e in list) e.id,
    ]);
    notifyListeners();
  }

  static const _contactOperations = {
    'contact_create',
    'contact_update',
    'contact_delete',
  };

  static const _localContactIdPrefix = 'local-contact-';

  Future<void> _replayManualContacts(
    AccountSession session,
    LocalMailFlagsStore store,
    List<QueuedMutation> queued,
  ) async {
    var stillQueued = false;
    var createdContact = false;
    for (final m in queued) {
      final payload = m.folderId == null
          ? null
          : jsonDecode(m.folderId!) as Map<String, dynamic>;
      try {
        switch (m.operation) {
          case 'contact_create':
            final created = await session.mailService.createContact(
              payload!['email'] as String,
              payload['displayName'] as String?,
            );
            session.manualContacts = [
              for (final c in session.manualContacts)
                c.id == m.mailId
                    ? ManualContact(
                        id: created['id'] as String,
                        accountId: c.accountId,
                        email: c.email,
                        displayName: c.displayName,
                      )
                    : c,
            ];
            createdContact = true;
          case 'contact_update':
            await session.mailService.updateContact(
              m.mailId,
              payload!['email'] as String,
              payload['displayName'] as String?,
            );
          case 'contact_delete':
            await session.mailService.deleteContact(m.mailId);
        }
        await store.clearQueuedMutation(m.mailId, 'contact');
      } catch (error) {
        if (error is ApiException && !_isOfflineFailure(error)) {
          await store.clearQueuedMutation(m.mailId, 'contact');
          session.mutationConflicts.add(m.mailId);
        } else {
          stillQueued = true;
        }
      }
    }
    if (createdContact || stillQueued) await _persistManualContacts(session);
    if (stillQueued) return;
    await _loadManualContacts(session, store);
    notifyListeners();
  }

  Iterable<AccountSession> get _scopedSessions => _registry.scoped;
  AccountSession get _primarySession => _registry.primary;
  AccountSession? _sessionOwning(String id) => _registry.owning(id);
  AccountSession? _sessionForThread(String id) => _registry.forThread(id);
  AccountSession? _sessionForLabel(String id) => _registry.forLabel(id);
  Map<AccountSession, List<String>> _groupBySession(List<String> ids) =>
      _registry.groupByOwner(ids);
  AccountSession _sessionForCompose({String? from, String? fromAccountId}) =>
      _registry.forCompose(from: from, fromAccountId: fromAccountId);

  final Map<String, List<Email>> _viewCache = {};

  // Anything that mutates a session's [AccountSession.emails] map, or that
  // switches [_activeAccountId], must call [_touch] so the next read
  // rebuilds instead of serving a stale view.
  void _touch() => _viewCache.clear();

  /// [MailFolder.starred] is virtual — "Yıldızlılar" surfaces starred mail
  /// regardless of its real folder. Mailbox views are ordered newest-first by
  /// timestamp (including the unified mailbox across accounts) with pinned
  /// mail floated to the top — see [pinnedFirst].
  @override
  List<Email> getEmailsInFolder(MailFolder folder) {
    final key = 'folder:${folder.name}:${_activeAccountId ?? ''}';
    return _viewCache.putIfAbsent(key, () => _buildFolderView(folder));
  }

  List<Email> _buildFolderView(MailFolder folder) {
    final sessions = _scopedSessions;
    if (folder == MailFolder.snoozed) {
      final pairs = [
        for (final s in sessions)
          for (final e in s.emails.values.expand((list) => list))
            if (_snoozedUntil(s, e.id) case final until?)
              (email: e, until: until),
      ];
      pairs.sort((a, b) => b.email.timestamp.compareTo(a.email.timestamp));
      return List.unmodifiable([for (final p in pairs) p.email]);
    }
    final result = folder == MailFolder.starred || folder == MailFolder.all
        ? [
            for (final s in sessions)
              ...s.emails.entries
                  .where((entry) => entry.key != MailFolder.starred)
                  .expand((entry) => entry.value)
                  .where(
                    (e) =>
                        (folder != MailFolder.starred || e.isStarred) &&
                        _snoozedUntil(s, e.id) == null,
                  ),
          ]
        : [
            for (final s in sessions)
              ...(s.emails[folder] ?? const <Email>[]).where(
                (e) => _snoozedUntil(s, e.id) == null,
              ),
          ];
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(pinnedFirst(result));
  }

  /// The active snooze deadline for [mailId] in [session], or null when it
  /// isn't snoozed or the snooze already elapsed (elapsed entries are left
  /// in storage — they're simply inert — and pruned lazily on next write).
  DateTime? _snoozedUntil(AccountSession session, String mailId) {
    final ms = session.snoozedUntil[mailId];
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(DateTime.now()) ? until : null;
  }

  Iterable<Email> _allCachedEmails(AccountSession session) sync* {
    final seen = <String>{};
    for (final list in session.emails.values) {
      for (final email in list) {
        if (seen.add(email.id)) yield email;
      }
    }
    for (final list in session.customFolderEmails.values) {
      for (final email in list) {
        if (seen.add(email.id)) yield email;
      }
    }
  }

  @override
  List<Email> getAllEmails() {
    const key = 'all:global';
    return _viewCache.putIfAbsent(
      key,
      () => [for (final s in _sessions.values) ..._allCachedEmails(s)],
    );
  }

  @override
  List<Email> getScopedEmails() {
    final key = 'all:${_activeAccountId ?? ''}';
    return _viewCache.putIfAbsent(
      key,
      () => [for (final s in _scopedSessions) ..._allCachedEmails(s)],
    );
  }

  @override
  bool hasMoreEmails(MailFolder folder) {
    if (folder == MailFolder.all) {
      return _scopedSessions.any(
        (session) => _allMailSourceFolders.any(
          (source) =>
              session.folderIds.containsKey(source) &&
              (session.hasMore[source] ?? true),
        ),
      );
    }
    if (folder == MailFolder.starred || folder == MailFolder.snoozed) {
      return false;
    }
    final sessions = _scopedSessions.where(
      (session) => session.folderIds.containsKey(folder),
    );
    return sessions.any((session) => session.hasMore[folder] ?? true);
  }

  @override
  DateTime? lastSyncedAt(MailFolder folder) {
    DateTime? latest;
    final sources = folder == MailFolder.all ? _allMailSourceFolders : [folder];
    for (final session in _scopedSessions) {
      for (final source in sources) {
        final synced = session.lastSynced[source];
        if (synced != null && (latest == null || synced.isAfter(latest))) {
          latest = synced;
        }
      }
    }
    return latest;
  }

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    if (folder == MailFolder.all) {
      final results = await Future.wait([
        for (final session in _scopedSessions)
          for (final source in _allMailSourceFolders)
            if (session.folderIds.containsKey(source))
              _loadMoreFor(session, source),
      ]);
      return results.expand((items) => items).toList();
    }
    final results = await Future.wait(
      _scopedSessions.map((session) => _loadMoreFor(session, folder)),
    );
    return results.expand((items) => items).toList();
  }

  Future<List<Email>> _loadMoreFor(
    AccountSession session,
    MailFolder folder,
  ) async {
    if (session.hasMore[folder] == false) return const [];
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
    session.hasMore[folder] =
        result.page * result.pageSize < result.total && result.items.isNotEmpty;
    session.lastSynced[folder] = DateTime.now();
    _cancelReconnectRetry(session);
    session.offline = false;
    await _replayQueuedMutations(session);
    notifyListeners();
    unawaited(_attachmentAutoDownloader.preloadListed(this, fresh));
    return List.unmodifiable(fresh);
  }

  @override
  Future<void> refreshEmails(MailFolder folder) async {
    if (folder == MailFolder.all) {
      await Future.wait([
        for (final session in _scopedSessions)
          for (final source in _allMailSourceFolders)
            if (session.folderIds.containsKey(source))
              _refreshEmailsFor(session, source),
      ]);
      return;
    }
    await Future.wait(
      _scopedSessions.map((session) => _refreshEmailsFor(session, folder)),
    );
  }

  Future<void> _refreshEmailsFor(
    AccountSession session,
    MailFolder folder,
  ) async {
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
    await _replayQueuedMutations(session);
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
                  bodyHtml: old[e.id]!.bodyHtml,
                  isStarred: old[e.id]!.isStarred,
                ),
        ),
    ];
    unawaited(_attachmentAutoDownloader.preloadListed(this, refreshed));
    // Refresh only re-fetches page 1. Mail paged in earlier via
    // loadMoreEmails is still real and must not vanish just because this
    // pass didn't re-verify it — losing it also breaks threadStatusOf's
    // cross-message reply/forward aggregation for any thread whose
    // answered/forwarded message lived past page 1.
    //
    // Page 1 is newest-first, though, so it does cover everything down to
    // its oldest item (the whole folder when the page isn't full): a cached
    // mail inside that window which the server didn't return has left the
    // folder and must go — otherwise a mail misfiled locally (or moved by
    // another client) would sit in this folder forever.
    final refreshedIds = refreshed.map((e) => e.id).toSet();
    final wholeFolder = result.items.length >= result.total;
    final oldestFetched = result.items.isEmpty
        ? null
        : result.items
              .map((e) => e.timestamp)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final stale = old.values
        .where(
          (e) =>
              !refreshedIds.contains(e.id) &&
              !wholeFolder &&
              oldestFetched != null &&
              e.timestamp.isBefore(oldestFetched),
        )
        .map(session.stampLocalFlags);
    if (folder == MailFolder.drafts) {
      _resolveDraftsFrom(refreshed);
      final queued =
          _cache?.loadDraftQueue(session.account.id) ?? const <Email>[];
      final queuedIds = queued.map((e) => e.id).toSet();
      session.emails[folder] = [
        ...queued,
        ...refreshed.where((e) => !queuedIds.contains(e.id)),
        ...stale.where((e) => !queuedIds.contains(e.id)),
      ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } else {
      session.emails[folder] = [...refreshed, ...stale]
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    session.pages[folder] = max(session.pages[folder] ?? 1, result.page);
    session.hasMore[folder] =
        (session.emails[folder]?.length ?? 0) < result.total;
    session.lastSynced[folder] = DateTime.now();
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

  /// Waits until the server has completed [folder]'s sync for each account
  /// in scope. Unknown folders throw [ArgumentError].
  @override
  Future<void> syncFolder(MailFolder folder) async {
    if (folder == MailFolder.starred || folder == MailFolder.snoozed) {
      return;
    }
    final sessions = _scopedSessions.toList();
    if (sessions.isEmpty) return;
    final jobs = <Future<void>>[];
    for (final session in sessions) {
      final sources = folder == MailFolder.all
          ? _allMailSourceFolders
          : [folder];
      for (final source in sources) {
        final folderId = session.folderIds[source];
        if (folderId != null) {
          jobs.add(_syncFolderFor(session, folderId));
        }
      }
    }
    if (jobs.isEmpty && folder != MailFolder.all) {
      throw ArgumentError('Unknown folder for this account: $folder');
    }
    await Future.wait(jobs);
  }

  Future<void> _syncFolderFor(AccountSession session, String folderId) async {
    try {
      await session.mailService.syncFolderId(folderId);
    } catch (error) {
      if (_isOfflineFailure(error)) {
        _markOffline(session);
        notifyListeners();
      }
      rethrow;
    }
  }

  @override
  Future<Email?> getEmail(String id) async {
    final owner = _sessionOwning(id);
    final candidates = owner != null ? [owner] : _sessions.values.toList();
    var sawNotFound = false;
    for (final session in candidates) {
      try {
        final email = session.stampLocalFlags(
          await session.mailService.getMail(
            id,
            resolveFolder: session.resolveFolder,
            allowRemoteImages: _remoteImageMailIds.contains(id),
          ),
        );
        if (_upsertDetail(session, email)) notifyListeners();
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
  Future<List<MailHeaderEntry>> fetchMailHeaders(String mailId) {
    final session = _sessionOwning(mailId);
    if (session == null) throw ArgumentError('Unknown mail: $mailId');
    return session.mailService.getMailHeaders(mailId);
  }

  @override
  Future<String> fetchMailSource(String mailId) {
    final session = _sessionOwning(mailId);
    if (session == null) throw ArgumentError('Unknown mail: $mailId');
    return session.mailService.getMailSource(mailId);
  }

  @override
  Future<MailSignatureVerification> verifyMailSignature(String mailId) {
    final session = _sessionOwning(mailId);
    if (session == null) throw ArgumentError('Unknown mail: $mailId');
    return session.mailService.getMailSignature(mailId);
  }

  @override
  Future<Email> loadRemoteImages(String id) async {
    final session = _sessionOwning(id);
    if (session == null) throw ArgumentError('Unknown mail: $id');
    final email = session.stampLocalFlags(
      await session.mailService.getMail(
        id,
        resolveFolder: session.resolveFolder,
        allowRemoteImages: true,
      ),
    );
    _remoteImageMailIds.add(id);
    _upsertDetail(session, email);
    notifyListeners();
    return email;
  }

  @override
  Future<Email> trustSenderForRemoteImages(
    String mailId,
    TrustedSenderKind kind,
  ) async {
    final session = _sessionOwning(mailId);
    if (session == null) throw ArgumentError('Unknown mail: $mailId');
    final current = await getEmail(mailId);
    final sender = current?.senderEmail.trim() ?? '';
    final at = sender.lastIndexOf('@');
    if (at <= 0 || at == sender.length - 1) {
      throw ArgumentError('Gönderici adresi okunamadı.');
    }
    await session.mailService.addTrustedSender(
      kind,
      kind == TrustedSenderKind.domain ? sender.substring(at + 1) : sender,
    );
    final email = session.stampLocalFlags(
      await session.mailService.getMail(
        mailId,
        resolveFolder: session.resolveFolder,
      ),
    );
    _upsertDetail(session, email);
    notifyListeners();
    return email;
  }

  @override
  Future<List<TrustedSender>> listTrustedSenders(String accountId) async {
    final items = await _sessionForAccountId(accountId).mailService
        .getTrustedSenders();
    return [for (final item in items) item.copyWith(accountId: accountId)];
  }

  @override
  Future<void> removeTrustedSender(String accountId, String id) =>
      _sessionForAccountId(accountId).mailService.removeTrustedSender(id);

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
    if (kIsWeb) return owner.mailService.downloadAttachment(mailId, id);
    final file = await ensureAttachmentFile(mailId, attachment);
    return file.readAsBytes();
  }

  @override
  Future<File> ensureAttachmentFile(String mailId, Attachment attachment) {
    final id = attachment.id;
    if (id == null) {
      throw ArgumentError('Attachment has no server id.');
    }
    final owner = _sessionOwning(mailId) ?? _primarySession;
    final key = AttachmentDownloadKey(owner.account.id, mailId, id);
    final path =
        '/api/mails/${Uri.encodeComponent(mailId)}/attachments/${Uri.encodeComponent(id)}';
    return _attachmentDownloadManager.ensureDownloaded(
      key: key,
      filename: attachment.name,
      sizeBytes: attachment.sizeBytes,
      open: ({rangeStart, abortTrigger}) async {
        final response = await owner.authService.client.getStream(
          path,
          rangeStart: rangeStart,
          abortTrigger: abortTrigger,
        );
        return HttpStreamResult(
          statusCode: response.statusCode,
          headers: response.headers,
          stream: response.stream,
        );
      },
    );
  }

  @override
  ValueListenable<AttachmentDownloadState> attachmentDownloadState(
    String mailId,
    Attachment attachment,
  ) {
    final owner = _sessionOwning(mailId) ?? _primarySession;
    return _attachmentDownloadManager.stateFor(
      AttachmentDownloadKey(owner.account.id, mailId, attachment.id ?? ''),
    );
  }

  @override
  Future<void> cancelAttachmentDownload(
    String mailId,
    Attachment attachment,
  ) async {
    final owner = _sessionOwning(mailId) ?? _primarySession;
    await _attachmentDownloadManager.cancel(
      AttachmentDownloadKey(owner.account.id, mailId, attachment.id ?? ''),
    );
  }

  @override
  Future<int> attachmentCacheSize() => _attachmentDownloadManager.cacheSize();

  @override
  Future<void> clearAttachmentCache() =>
      _attachmentDownloadManager.clearCache();

  /// Stores a full detail object in [session]'s in-memory cache. Returns true
  /// when the detail response confirms a cached unread mail became read.
  bool _upsertDetail(AccountSession session, Email email) {
    _touch();
    for (final folder in session.emails.keys.toList()) {
      final list = session.emails[folder]!;
      final index = list.indexWhere((e) => e.id == email.id);
      if (index >= 0) {
        final wasUnread = !list[index].isRead && email.isRead;
        session.emails[folder] = [...list]..[index] = email;
        return wasUnread;
      }
    }
    for (final folderId in session.customFolderEmails.keys.toList()) {
      final list = session.customFolderEmails[folderId]!;
      final index = list.indexWhere((e) => e.id == email.id);
      if (index >= 0) {
        final wasUnread = !list[index].isRead && email.isRead;
        session.customFolderEmails[folderId] = [...list]..[index] = email;
        return wasUnread;
      }
    }
    session.emails.putIfAbsent(email.folder, () => <Email>[]).insert(0, email);
    return false;
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
  Future<void> _seedThreadSizes(AccountSession session) async {
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

  /// Server conversation arrives through one `?include=body` request. Only
  /// attachments need a detail fetch for their metadata; recipients and
  /// remote-content flags already live in the conversation response.
  /// Results are deduplicated and sorted oldest → newest. A conversation-level
  /// failure propagates so the caller keeps its already-loaded mail.
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
            allowRemoteImages: _remoteImageMailIds.contains(id),
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
    session.serverThreadSizes[threadId] = thread.length;
    // One notification persists every upsert to this account's SQLite bucket
    // and lets open detail panes consume enriched bodies immediately.
    notifyListeners();
    return List.unmodifiable(thread);
  }

  @override
  Future<Email> sendEmail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
    bool requestReadReceipt = false,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final session = _sessionForCompose(
      from: from,
      fromAccountId: fromAccountId,
    );
    late final SendResult result;
    try {
      result = await session.mailService.sendMail(
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        bodyHtml: bodyHtml,
        attachments: attachments,
        replySourceMailId: inReplyToId,
        identityId: identityId,
        requestReadReceipt: requestReadReceipt,
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
        onProgress: onProgress,
        abortTrigger: abortTrigger,
      );
    } on ApiException catch (error) {
      if (!AttachmentLimitException.codes.contains(error.code)) rethrow;
      throw AttachmentLimitException.from(
        error,
        attachments,
        _composeLimits[session.account.id],
      );
    }
    if (!result.sent) throw const SendBeforeDeliveryException();
    // The endpoint confirms send/save outcome but never returns the created
    // mail — build the local copy from what we sent and echo it into the
    // Sent cache so the UI reflects it before the next refresh reconciles.
    final id = result.mailId ?? 'sent-${DateTime.now().microsecondsSinceEpoch}';
    final email = Email(
      id: id,
      senderName: session.account.displayName ?? session.account.email,
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
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
      _touch();
      session.emails
          .putIfAbsent(MailFolder.sent, () => <Email>[])
          .insert(0, email);
      notifyListeners();
    }
    return email;
  }

  @override
  Future<ComposeLimits> composeLimits(String accountId) async {
    final cached = _composeLimits[accountId];
    if (cached != null) return cached;
    final limits = await _sessionForAccountId(accountId).mailService
        .getComposeLimits();
    _composeLimits[accountId] = limits;
    return limits;
  }

  late final ScheduledSendModule _scheduled = ScheduledSendModule(
    _registry,
    notifyListeners,
  );

  @override
  Future<ScheduledSend> scheduleSend({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? inReplyToId,
    String? identityId,
    bool requestReadReceipt = false,
    required DateTime sendAt,
  }) => _scheduled.scheduleSend(
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    bodyHtml: bodyHtml,
    attachments: attachments,
    from: from,
    fromAccountId: fromAccountId,
    inReplyToId: inReplyToId,
    identityId: identityId,
    requestReadReceipt: requestReadReceipt,
    sendAt: sendAt,
  );

  @override
  Future<ScheduledSendDetail> getScheduledSend(String id) =>
      _scheduled.getScheduledSend(id);

  @override
  Future<void> updateScheduledSend({
    required String id,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String body = '',
    String? bodyHtml,
    required DateTime sendAt,
    List<String> keepAttachmentIds = const [],
    List<Attachment> attachments = const [],
  }) => _scheduled.updateScheduledSend(
    id: id,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    bodyHtml: bodyHtml,
    sendAt: sendAt,
    keepAttachmentIds: keepAttachmentIds,
    attachments: attachments,
  );

  @override
  Future<void> rescheduleFailedSend({
    required String id,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String body = '',
    String? bodyHtml,
    List<String>? attachmentIds,
    required DateTime sendAt,
  }) => _scheduled.rescheduleFailedSend(
    id: id,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    bodyHtml: bodyHtml,
    attachmentIds: attachmentIds,
    sendAt: sendAt,
  );

  @override
  Future<void> cancelScheduledSend(String id) =>
      _scheduled.cancelScheduledSend(id);

  @override
  List<ScheduledSend> getScheduledSends() => _scheduled.getScheduledSends();

  @override
  Future<void> refreshScheduledSends() => _scheduled.refreshScheduledSends();

  // --- Account-owned data, delegated to focused modules --------------------

  late final SignatureModule _signatures = SignatureModule(
    _registry,
    notifyListeners,
  );
  late final TemplateModule _templates = TemplateModule(
    _registry,
    notifyListeners,
  );
  late final AccountSettingsModule _accountSettings = AccountSettingsModule(
    _registry,
    notifyListeners,
  );

  @override
  Future<List<MailSignature>> listSignatures(
    String accountId, {
    bool refresh = false,
  }) => _signatures.listSignatures(accountId, refresh: refresh);

  @override
  Future<SignatureDefaults> getSignatureDefaults(String accountId) =>
      _signatures.getSignatureDefaults(accountId);

  @override
  Future<MailSignature> createSignature(
    String accountId,
    MailSignature signature,
  ) => _signatures.createSignature(accountId, signature);

  @override
  Future<MailSignature> updateSignature(
    String accountId,
    MailSignature signature,
  ) => _signatures.updateSignature(accountId, signature);

  @override
  Future<void> deleteSignature(String accountId, String signatureId) =>
      _signatures.deleteSignature(accountId, signatureId);

  @override
  Future<SignatureDefaults> updateSignatureDefaults(
    String accountId,
    SignatureDefaults defaults,
  ) => _signatures.updateSignatureDefaults(accountId, defaults);

  @override
  Future<List<MailIdentity>> listIdentities(
    String accountId, {
    bool refresh = false,
  }) => _signatures.listIdentities(accountId, refresh: refresh);

  @override
  Future<MailIdentity> createIdentity(
    String accountId,
    MailIdentity identity,
  ) => _signatures.createIdentity(accountId, identity);

  @override
  Future<MailIdentity> updateIdentity(
    String accountId,
    MailIdentity identity,
  ) => _signatures.updateIdentity(accountId, identity);

  @override
  Future<void> deleteIdentity(String accountId, String identityId) =>
      _signatures.deleteIdentity(accountId, identityId);

  @override
  Future<void> setSignature(String accountId, String? signature) =>
      _signatures.setSignature(accountId, signature);

  @override
  Future<List<MailTemplate>> listTemplates(
    String accountId, {
    bool refresh = false,
  }) => _templates.listTemplates(accountId, refresh: refresh);

  @override
  Future<MailTemplate> createTemplate(
    String accountId,
    MailTemplate template,
  ) => _templates.createTemplate(accountId, template);

  @override
  Future<MailTemplate> updateTemplate(
    String accountId,
    MailTemplate template,
  ) => _templates.updateTemplate(accountId, template);

  @override
  Future<void> deleteTemplate(String accountId, String templateId) =>
      _templates.deleteTemplate(accountId, templateId);

  @override
  Future<void> refreshQuota(String accountId) =>
      _accountSettings.refreshQuota(accountId);

  @override
  Future<List<FolderSyncStatus>> getSyncStatus(String accountId) =>
      _accountSettings.getSyncStatus(accountId);

  @override
  Future<AccountSyncScope> getSyncScope(String accountId) =>
      _accountSettings.getSyncScope(accountId);

  @override
  Future<AccountSyncScope> updateSyncScope(
    String accountId,
    FolderSyncScope scope, {
    List<String>? folderIds,
  }) =>
      _accountSettings.updateSyncScope(accountId, scope, folderIds: folderIds);

  @override
  Future<AccountNotificationSettings> getNotificationSettings(
    String accountId,
  ) => _accountSettings.getNotificationSettings(accountId);

  @override
  Future<AccountNotificationSettings> updateNotificationSettings(
    String accountId,
    AccountNotificationSettings settings,
  ) => _accountSettings.updateNotificationSettings(accountId, settings);

  // --- Custom folders -------------------------------------------------

  AccountSession _sessionForAccountId(String accountId) =>
      _registry.forAccount(accountId);

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) {
    final sessions = accountId == null
        ? _scopedSessions
        : [?_sessions[accountId]];
    final result = <MailCustomFolder>[
      for (final session in sessions)
        for (final f in session.customFolders)
          MailCustomFolder(
            accountId: session.account.id,
            folderId: f.id,
            name: f.name,
            fullName: f.fullName,
            isSyncEnabled: f.isSyncEnabled,
            parentFolderId: f.parentId,
            parentIdKnown: f.parentIdKnown,
            delimiter: f.delimiter,
            unreadCount: f.unreadCount,
            totalCount: f.totalCount,
          ),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return result;
  }

  @override
  List<MailFolderInfo> getAccountFolders(String accountId) => [
    for (final f in _registry.forAccount(accountId).allFolders)
      MailFolderInfo(
        accountId: accountId,
        folderId: f.id,
        name: f.name,
        fullName: f.fullName,
        kind: FolderKind.fromBackend(f.type),
        isSyncEnabled: f.isSyncEnabled,
        parentFolderId: f.parentId,
        delimiter: f.delimiter,
        unreadCount: f.unreadCount,
        totalCount: f.totalCount,
        roleOverride: f.roleOverride == null
            ? null
            : FolderKind.fromBackend(f.roleOverride!),
      ),
  ];

  @override
  Map<MailFolder, String> standardFolderIds(String accountId) =>
      Map.unmodifiable(_sessionForAccountId(accountId).folderIds);

  @override
  List<Email> cachedCustomFolderMails(String accountId, String folderId) =>
      List.unmodifiable(
        _sessionForAccountId(accountId).customFolderEmails[folderId] ??
            const [],
      );

  @override
  Future<void> refreshCustomFolders({
    String? accountId,
    bool rediscover = false,
  }) async {
    final sessions = accountId == null
        ? _scopedSessions
        : [_sessionForAccountId(accountId)];
    await Future.wait(
      sessions.map((s) => _loadCustomFolders(s, rediscover: rediscover)),
    );
    notifyListeners();
  }

  Future<void> _loadCustomFolders(
    AccountSession session, {
    bool rediscover = false,
  }) async {
    if (rediscover) await session.mailService.refreshFolders();
    var folders = await session.mailService.getFolders();
    if (!rediscover &&
        !session.folderHierarchyRequested &&
        folders.any((f) => f.isAvailable && f.delimiter == null)) {
      session.folderHierarchyRequested = true;
      await session.mailService.refreshFolders();
      folders = await session.mailService.getFolders();
    }
    _applyCustomFolderLists(session, folders);
  }

  Future<void> _reloadCustomFoldersAfterChange(AccountSession session) async {
    try {
      await _loadCustomFolders(session);
    } catch (_) {
    } finally {
      notifyListeners();
    }
  }

  void _putCustomFolder(AccountSession session, ApiMailFolder folder) {
    session.customFolders = [
      for (final f in session.customFolders)
        if (f.id != folder.id) f,
      if (folder.type == 'Custom' && folder.isAvailable) folder,
    ];
  }

  void _forgetCustomFolderMails(AccountSession session, String folderId) {
    session.customFolderEmails.remove(folderId);
    session.customFolderPages.remove(folderId);
    session.customFolderHasMore.remove(folderId);
  }

  void _dropFromCustomFolderMails(AccountSession session, Set<String> ids) {
    for (final entry in session.customFolderEmails.entries) {
      if (entry.value.any((e) => ids.contains(e.id))) {
        session.customFolderEmails[entry.key] = [
          for (final email in entry.value)
            if (!ids.contains(email.id)) email,
        ];
      }
    }
  }

  @override
  Future<List<Email>> getCustomFolderMails({
    required String accountId,
    required String folderId,
  }) {
    final session = _sessionForAccountId(accountId);
    final cached = session.customFolderEmails[folderId];
    if (cached != null) {
      unawaited(
        _fetchCustomFolderPage(
          session: session,
          folderId: folderId,
          page: 1,
        ).catchError((_) => cached),
      );
      return Future.value(List.unmodifiable(cached));
    }
    return _fetchCustomFolderPage(
      session: session,
      folderId: folderId,
      page: 1,
    );
  }

  @override
  bool hasMoreCustomFolderMails(String accountId, String folderId) =>
      _sessionForAccountId(accountId).customFolderHasMore[folderId] ?? false;

  @override
  Future<List<Email>> loadMoreCustomFolderMails({
    required String accountId,
    required String folderId,
  }) {
    final session = _sessionForAccountId(accountId);
    if (session.customFolderHasMore[folderId] == false) {
      return Future.value(session.customFolderEmails[folderId] ?? const []);
    }
    final nextPage = (session.customFolderPages[folderId] ?? 0) + 1;
    return _fetchCustomFolderPage(
      session: session,
      folderId: folderId,
      page: nextPage,
    );
  }

  Future<List<Email>> _fetchCustomFolderPage({
    required AccountSession session,
    required String folderId,
    required int page,
  }) async {
    final result = await session.mailService.getMails(
      folderId: folderId,
      resolveFolder: session.resolveFolder,
      page: page,
    );
    final fetched = result.items.map(session.stampLocalFlags).toList();
    session.customFolderPages[folderId] = page;
    session.customFolderHasMore[folderId] =
        page * result.pageSize < result.total;
    final accumulated = page == 1
        ? fetched
        : [...?session.customFolderEmails[folderId], ...fetched];
    session.customFolderEmails[folderId] = accumulated;
    try {
      if (page == 1) {
        _cache?.replaceCustomFolder(session.account.id, folderId, accumulated);
      } else {
        _cache?.apply(
          session.account.id,
          fetched,
          const [],
          customFolderId: folderId,
        );
      }
    } catch (_) {
      // Cache is an optimization; never surface its failures.
    }
    unawaited(_attachmentAutoDownloader.preloadListed(this, fetched));
    notifyListeners();
    return accumulated;
  }

  @override
  Future<void> syncCustomFolder({
    required String accountId,
    required String folderId,
  }) => _sessionForAccountId(accountId).mailService.syncFolderId(folderId);

  @override
  Future<void> createCustomFolder({
    required String accountId,
    required String name,
    String? parentFolderId,
  }) async {
    final session = _sessionForAccountId(accountId);
    final created = await session.mailService.createFolder(
      name,
      parentId: parentFolderId,
    );
    _putCustomFolder(session, created);
    await _reloadCustomFoldersAfterChange(session);
  }

  @override
  Future<void> renameCustomFolder({
    required String accountId,
    required String folderId,
    required String name,
  }) async {
    final session = _sessionForAccountId(accountId);
    final renamed = await session.mailService.renameFolder(folderId, name);
    _putCustomFolder(session, renamed);
    await _reloadCustomFoldersAfterChange(session);
  }

  @override
  Future<void> changeCustomFolderParent({
    required String accountId,
    required String folderId,
    required String? parentFolderId,
  }) async {
    final session = _sessionForAccountId(accountId);
    final moved = await session.mailService.setFolderParent(
      folderId,
      parentFolderId,
    );
    _putCustomFolder(session, moved);
    await _reloadCustomFoldersAfterChange(session);
  }

  @override
  Future<void> deleteCustomFolder({
    required String accountId,
    required String folderId,
  }) async {
    final session = _sessionForAccountId(accountId);
    await session.mailService.deleteFolder(folderId);
    session.customFolders = [
      for (final f in session.customFolders)
        if (f.id != folderId) f,
    ];
    _forgetCustomFolderMails(session, folderId);
    await _reloadCustomFoldersAfterChange(session);
  }

  @override
  List<MailFolderRoleAssignment> getFolderRoleAssignments({String? accountId}) {
    final sessions = accountId == null
        ? _scopedSessions
        : [?_sessions[accountId]];
    return [
      for (final session in sessions)
        for (final f in session.roleOverrideFolders)
          if (_logicalFolderForType(f.roleOverride!) case final role?)
            MailFolderRoleAssignment(
              accountId: session.account.id,
              folderId: f.id,
              name: f.name,
              fullName: f.fullName,
              role: role,
            ),
    ];
  }

  @override
  Future<void> setFolderRole({
    required String accountId,
    required String folderId,
    required MailFolder? role,
  }) async {
    final wire = switch (role) {
      null => null,
      MailFolder.sent => 'Sent',
      MailFolder.drafts => 'Drafts',
      MailFolder.trash => 'Trash',
      MailFolder.spam => 'Junk',
      _ => throw ArgumentError.value(role, 'role', 'not assignable'),
    };
    final session = _sessionForAccountId(accountId);
    final previous = Map.of(session.folderIds);
    await session.mailService.setFolderRole(folderId, wire);
    _applyFolderMap(session, await session.mailService.getFolders());
    _persistFolderMap(session);
    // A logical bucket now backed by a different server folder holds the
    // old folder's mail; drop it so the next open fetches the new folder.
    for (final logical in {...previous.keys, ...session.folderIds.keys}) {
      if (previous[logical] == session.folderIds[logical]) continue;
      session.emails.remove(logical);
      session.pages.remove(logical);
      session.hasMore.remove(logical);
      session.lastSynced.remove(logical);
    }
    _forgetCustomFolderMails(session, folderId);
    notifyListeners();
  }

  @override
  Future<void> moveToCustomFolder(
    List<String> ids, {
    required String accountId,
    required String folderId,
  }) async {
    if (ids.isEmpty) return;
    final session = _sessionForAccountId(accountId);
    final results = await _bulkAndApplyOrQueue(session, 'move', ids, (
      succeeded,
    ) {
      _removeMany(session, succeeded);
      _forgetCustomFolderMails(session, folderId);
    }, folderId: folderId);
    final failure = results.where((r) => !r.success).firstOrNull;
    if (failure != null) {
      throw ApiException(status: 0, code: failure.code ?? 'mail_move_failed');
    }
  }

  @override
  Set<MailFolder> availableFolders(String accountId) =>
      _sessions[accountId]?.folderIds.keys.toSet() ?? const {};

  /// Tail of the draft write queue — see [_serializeDraftWrite].
  Future<void> _draftWrites = Future.value();
  final Map<String, void Function(Email)> _draftFailureCallbacks = {};
  final _draftSyncFailureController = StreamController<Email>.broadcast();

  @override
  Stream<Email> get draftSyncFailures => _draftSyncFailureController.stream;

  @override
  void detachDraftSyncFailureHandler(String draftId) {
    _draftFailureCallbacks.remove(draftId);
  }

  bool _draftSyncScheduled = false;
  bool _draftSyncRequested = false;

  void _scheduleDraftSync() {
    if (_draftSyncScheduled) {
      _draftSyncRequested = true;
      return;
    }
    _draftSyncScheduled = true;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        try {
          await _syncQueuedDrafts();
        } finally {
          _draftSyncScheduled = false;
          if (_draftSyncRequested) {
            _draftSyncRequested = false;
            _scheduleDraftSync();
          }
        }
      }),
    );
  }

  Future<void> _syncQueuedDrafts() async {
    final cache = _cache;
    if (cache == null) return;
    for (final session in _sessions.values) {
      for (final local in cache.loadDraftQueue(session.account.id)) {
        try {
          final saved = await _serializeDraftWrite(
            () => _writeDraft(
              to: local.recipients,
              cc: local.cc,
              bcc: local.bcc,
              subject: local.subject,
              body: local.bodyText,
              bodyHtml: local.bodyHtml,
              attachments: local.attachments,
              from: local.senderEmail,
              fromAccountId: session.account.id,
              threadId: local.threadId,
              inReplyToId: local.inReplyToId,
              identityId: local.headers['draftIdentityId'],
              draftId: local.id.startsWith('local-draft-') ? null : local.id,
            ),
          );
          final latest = session.emails[MailFolder.drafts]?.firstWhere(
            (e) => e.id == local.id,
            orElse: () => local,
          );
          if (latest != null &&
              !cache.queuedDraftMatches(session.account.id, latest)) {
            _scheduleDraftSync();
            continue;
          }
          final drafts = session.emails[MailFolder.drafts];
          if (saved.id != local.id) {
            drafts?.removeWhere((e) => e.id == saved.id);
          }
          final index = drafts?.indexWhere((e) => e.id == local.id) ?? -1;
          if (index >= 0) drafts![index] = saved;
          if (saved.id != local.id) _draftIdSuccessor[local.id] = saved.id;
          cache.removeQueuedDraft(session.account.id, local.id);
          _draftFailureCallbacks.remove(local.id);
          notifyListeners();
        } catch (_) {
          final latest = session.findLoaded(local.id);
          if (latest != null &&
              !cache.queuedDraftMatches(session.account.id, latest)) {
            _scheduleDraftSync();
            continue;
          }
          final callback = _draftFailureCallbacks[local.id];
          if (callback != null) {
            callback(local);
          } else {
            _draftSyncFailureController.add(local);
          }
          Future<void>.delayed(const Duration(seconds: 15), () {
            _scheduleDraftSync();
          });
          return;
        }
      }
    }
  }

  /// Old draft id -> the id `PUT /drafts/{id}` replaced it with.
  final Map<String, String> _draftIdSuccessor = {};

  /// Drafts the server stored but couldn't name yet (`reconciliationPending`),
  /// keyed by the id the caller holds — a local placeholder after a create,
  /// or the retired id after an update. Resolved into [_draftIdSuccessor]
  /// when a Drafts refresh shows the matching server copy.
  final Map<String, ({Email written, Set<String> baseline})> _unresolvedDrafts =
      {};

  /// [baseline] is every draft id listed before the write, so only a copy
  /// that appeared afterwards can be matched to it.
  void _trackUnresolvedDraft(
    AccountSession session,
    Email written,
    Set<String> baseline,
  ) {
    _unresolvedDrafts[written.id] = (written: written, baseline: baseline);
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 3),
        () => _refreshEmailsFor(session, MailFolder.drafts),
      ).catchError((_) {}),
    );
  }

  /// Maps each unresolved draft to the server draft that appeared after it
  /// was written, with the same subject and recipients (newest first).
  void _resolveDraftsFrom(List<Email> listed) {
    if (_unresolvedDrafts.isEmpty) return;
    final claimed = _draftIdSuccessor.values.toSet();
    final candidates = listed.where((e) => !claimed.contains(e.id)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final MapEntry(key: id, value: pending)
        in _unresolvedDrafts.entries.toList()) {
      final written = pending.written;
      final notBefore = written.timestamp.subtract(const Duration(minutes: 2));
      final match = candidates
          .where(
            (e) =>
                !pending.baseline.contains(e.id) &&
                e.accountId == written.accountId &&
                _draftSubjectKey(e.subject) ==
                    _draftSubjectKey(written.subject) &&
                e.recipients.toSet().containsAll(written.recipients) &&
                written.recipients.toSet().containsAll(e.recipients) &&
                !e.timestamp.isBefore(notBefore),
          )
          .firstOrNull;
      if (match == null) continue;
      candidates.remove(match);
      _draftIdSuccessor[id] = match.id;
      _unresolvedDrafts.remove(id);
    }
  }

  /// The backend stores a blank subject as "(no subject)".
  static String _draftSubjectKey(String subject) =>
      subject.trim().isEmpty ? '(no subject)' : subject.trim();

  /// The server id to write to for [id]. A draft still awaiting
  /// reconciliation triggers one Drafts refresh; if the server copy is
  /// still unnamed after it, writing now would 404, so this fails clearly.
  Future<String> _serverDraftId(String id) async {
    var latest = _latestDraftId(id);
    final pending = _unresolvedDrafts[latest];
    if (pending == null) return latest;
    final session = _sessions[pending.written.accountId] ?? _primarySession;
    await _refreshEmailsFor(session, MailFolder.drafts);
    latest = _latestDraftId(id);
    if (_unresolvedDrafts.containsKey(latest)) {
      throw const ApiException(status: 409, code: 'draft_not_reconciled');
    }
    return latest;
  }

  /// Runs draft writes one at a time. Two overlapping saves of the same
  /// draft (a double-tapped "Taslağı Kaydet") would otherwise both `PUT`
  /// the same id: each re-APPENDs a copy and only one can retire the
  /// original, leaving duplicates behind.
  Future<T> _serializeDraftWrite<T>(Future<T> Function() write) {
    final result = _draftWrites.then((_) => write());
    _draftWrites = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// The current id of a draft that may have been re-created under a new id
  /// by an earlier update — callers holding the id they opened keep working.
  String _latestDraftId(String id) {
    var current = id;
    for (var next = _draftIdSuccessor[current]; next != null;) {
      current = next;
      next = _draftIdSuccessor[current];
    }
    return current;
  }

  @override
  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
    String? draftId,
    void Function(Email draft)? onSyncFailure,
  }) async {
    final cache = _cache;
    if (cache == null) {
      throw StateError('Draft cache unavailable');
    }
    final resolvedDraftId = draftId == null ? null : _latestDraftId(draftId);
    final session = resolvedDraftId != null
        ? (_sessionOwning(resolvedDraftId) ??
              _sessionForCompose(from: from, fromAccountId: fromAccountId))
        : _sessionForCompose(from: from, fromAccountId: fromAccountId);
    draftId = resolvedDraftId;
    final id =
        draftId ?? 'local-draft-${DateTime.now().microsecondsSinceEpoch}';
    final drafts = session.emails.putIfAbsent(
      MailFolder.drafts,
      () => <Email>[],
    );
    final oldIndex = drafts.indexWhere((e) => e.id == id);
    final previous = oldIndex < 0 ? null : drafts[oldIndex];
    final local = Email(
      id: id,
      senderName: session.account.displayName ?? session.account.email,
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty)
          ? (previous?.threadId.isNotEmpty == true
                ? previous!.threadId
                : 't-$id')
          : threadId,
      inReplyToId: inReplyToId ?? previous?.inReplyToId,
      headers: {
        // ignore: use_null_aware_elements
        if (identityId != null) 'draftIdentityId': identityId,
      },
    );
    if (oldIndex < 0) {
      drafts.insert(0, local);
    } else {
      drafts[oldIndex] = local;
    }
    try {
      cache.queueDraft(session.account.id, local);
    } catch (_) {
      if (oldIndex < 0) {
        drafts.remove(local);
      } else {
        drafts[oldIndex] = previous!;
      }
      rethrow;
    }
    if (onSyncFailure != null) _draftFailureCallbacks[id] = onSyncFailure;
    notifyListeners();
    _scheduleDraftSync();
    return local;
  }

  Future<Email> _writeDraft({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    required String? bodyHtml,
    required List<Attachment> attachments,
    required String? from,
    required String? fromAccountId,
    required String? threadId,
    required String? inReplyToId,
    required String? identityId,
    required String? draftId,
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
        bodyHtml: bodyHtml,
        attachments: attachments,
        replySourceMailId: inReplyToId,
        identityId: identityId,
      );
      final newId = result.mailId ?? draftId;
      if (newId != draftId) _draftIdSuccessor[draftId] = newId;
      final drafts = session.emails.putIfAbsent(
        MailFolder.drafts,
        () => <Email>[],
      );
      final oldIndex = drafts.indexWhere((e) => e.id == draftId);
      final previous = oldIndex >= 0 ? drafts[oldIndex] : null;
      final updated = Email(
        id: newId,
        senderName:
            session.account.displayName ??
            previous?.senderName ??
            session.account.email,
        senderEmail: from ?? session.account.email,
        recipients: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        bodyHtml: bodyHtml,
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
      if (result.mailId == null) {
        // Reconciliation pending: the server stored the new copy and already
        // retired the old one, but can't name the new id yet. Drop the stale
        // row and pick the real one up once the Drafts sync lands.
        final baseline = drafts.map((e) => e.id).toSet();
        if (oldIndex >= 0) drafts.removeAt(oldIndex);
        _touch();
        notifyListeners();
        _trackUnresolvedDraft(session, updated, baseline);
        return updated;
      }
      _touch();
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
      bodyHtml: bodyHtml,
      attachments: attachments,
      replySourceMailId: inReplyToId,
      identityId: identityId,
    );
    // Reconciliation can still be pending right after APPEND — fall back to
    // a local id so the draft is still usable; the next Drafts refresh maps
    // it to the server's real id (see [_resolveDraftsFrom]).
    final id =
        result.mailId ?? 'draft-${DateTime.now().microsecondsSinceEpoch}';
    final email = Email(
      id: id,
      senderName: session.account.displayName ?? session.account.email,
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
      inReplyToId: inReplyToId,
    );
    _touch();
    final drafts = session.emails.putIfAbsent(
      MailFolder.drafts,
      () => <Email>[],
    );
    if (result.mailId == null) {
      _trackUnresolvedDraft(session, email, drafts.map((e) => e.id).toSet());
    }
    drafts.insert(0, email);
    notifyListeners();
    return email;
  }

  @override
  Future<void> deleteDraft(String draftId) {
    final initialSession = _sessionOwning(draftId) ?? _primarySession;
    if (draftId.startsWith('local-draft-')) {
      _cache?.removeQueuedDraft(initialSession.account.id, draftId);
      _draftFailureCallbacks.remove(draftId);
      _removeMany(initialSession, [draftId]);
      notifyListeners();
      return Future.value();
    }
    final initialSnapshot = _snapshotMailLocations(initialSession, [draftId]);
    _removeMany(initialSession, [draftId]);
    notifyListeners();
    return _serializeDraftWrite(() async {
      final String id;
      try {
        id = await _serverDraftId(draftId);
      } catch (_) {
        _restoreMailLocations(initialSession, initialSnapshot);
        notifyListeners();
        rethrow;
      }
      final session = _sessionOwning(id) ?? initialSession;
      final snapshot = id == draftId
          ? initialSnapshot
          : _snapshotMailLocations(session, [id]);
      if (id != draftId) {
        _removeMany(session, [id]);
        notifyListeners();
      }
      try {
        await session.mailService.deleteDraft(id);
      } catch (_) {
        _restoreMailLocations(session, snapshot);
        notifyListeners();
        rethrow;
      }
    });
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
      idempotencyKey: newIdempotencyKey(),
    );
    if (!result.sent) return null;
    _touch();
    if (result.draftRemoved) {
      session.emails[MailFolder.drafts]?.removeWhere((e) => e.id == draftId);
    }
    final echo =
        (draft ??
                Email(
                  id: draftId,
                  senderName:
                      session.account.displayName ?? session.account.email,
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
  @override
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String mode) {
    final session = _sessionOwning(sourceMailId) ?? _primarySession;
    return session.mailService.getComposePrefill(sourceMailId, mode);
  }

  /// Server-side full-text + filtered search (`GET /api/search`) over cached
  /// server mail, fanned out across every account in scope — reaches mail
  /// not yet loaded into the local buckets. The sync in-screen search
  /// ([MailRepository.searchEmails]) stays client-side over loaded mail.
  @override
  Future<List<Email>> searchEmailsOnServer({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final sessions = accountId == null
        ? _sessions.values
        : [?_sessions[accountId]];
    final all = <Email>[];
    for (final session in sessions) {
      final folderId =
          customFolderId ?? (folder == null ? null : session.folderIds[folder]);
      if (customFolderId != null &&
          !session.customFolders.any((item) => item.id == customFolderId)) {
        continue;
      }
      if (folder != null && folderId == null) continue;
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
        labelId: labelId,
        page: page,
        pageSize: pageSize,
      );
      all.addAll(results.map(session.stampLocalFlags));
    }
    return all;
  }

  @override
  Future<RemoteSearchResult> searchRemote({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
  }) async {
    final sessions = accountId == null
        ? _sessions.values
        : [?_sessions[accountId]];
    var matched = 0;
    var imported = 0;
    var remaining = 0;
    var complete = true;
    for (final session in sessions) {
      final folderId =
          customFolderId ?? (folder == null ? null : session.folderIds[folder]);
      if (customFolderId != null &&
          !session.customFolders.any((item) => item.id == customFolderId)) {
        continue;
      }
      if (folder != null && folderId == null) continue;
      final result = await session.mailService.searchRemote(
        query: query,
        folderId: folderId,
        conversationId: conversationId,
        from: from,
        to: to,
        fromDate: fromDate,
        toDate: toDate,
        isRead: isRead,
        flagged: flagged,
        hasAttachment: hasAttachment,
        labelId: labelId,
      );
      matched += result.matched;
      imported += result.imported;
      remaining += result.remaining;
      complete = complete && result.complete;
    }
    return RemoteSearchResult(
      matched: matched,
      imported: imported,
      remaining: remaining,
      complete: complete,
    );
  }

  @override
  Future<int> queuedOfflineMutationCount(String accountId) async {
    final store = _sessions[accountId]?.flagsStore;
    if (store == null) return 0;
    return (await store.readQueuedMutations()).length;
  }

  @override
  Future<void> moveToTrash(List<String> ids) async {
    final results = await Future.wait(
      _groupBySession(ids).entries.map(
        (entry) => _bulkAndApplyOrQueue(
          entry.key,
          'trash',
          entry.value,
          (succeeded) => _moveMany(entry.key, succeeded, MailFolder.trash),
        ),
      ),
    );
    final failure = results
        .expand((perAccount) => perAccount)
        .where((result) => !result.success)
        .firstOrNull;
    if (failure != null) {
      throw ApiException(
        status: 0,
        code: failure.code ?? 'mail_operation_failed',
      );
    }
  }

  /// Expunge is irreversible: retain cached messages until server confirmation.
  @override
  Future<void> deletePermanently(List<String> ids) async {
    final failures = <String>[];
    await Future.wait(
      _groupBySession(ids).entries.map((entry) async {
        final session = entry.key;
        final results = await session.mailService.bulkAction(
          'delete',
          entry.value,
        );
        final successfulIds = results
            .where((result) => result.success)
            .map((result) => result.mailId)
            .toList();
        if (successfulIds.isNotEmpty) {
          _removeMany(session, successfulIds);
          notifyListeners();
        }
        failures.addAll([
          for (final result in results)
            if (!result.success) result.code ?? 'mail_operation_failed',
        ]);
        unawaited(_refreshCountsFor(session));
      }),
    );
    if (failures.isNotEmpty) {
      throw ApiException(status: 0, code: failures.first);
    }
  }

  /// Drops every cached mail in [ids] from whichever bucket holds it.
  void _removeMany(AccountSession session, Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _touch();
    _dropFromCustomFolderMails(session, idSet);
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          if (!idSet.contains(email.id)) email,
      ];
    }
  }

  /// Mails currently in Trash/Spam go back through bulk `restore` (the only
  /// action that reverses those two); everything else moves via the bulk
  /// `move`/`archive` actions. Both branches can run per account when [ids]
  /// mixes trashed and non-trashed mails across multiple connected accounts.
  ///
  /// `restore`'s true target folder is only known once the server responds
  /// (a restored draft goes back to Drafts, not Inbox — see
  /// [_fileRestored]), so it cannot share [_bulkAndApplyOrQueue]'s generic
  /// "apply this same local effect online or offline" contract: offline, it
  /// queues the mutation and files the mail into Inbox as a placeholder;
  /// [_replayQueuedMutations] calls [_fileRestored] once the real answer is
  /// known, exactly like the immediate-online path below does.
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
      if (restoring.isNotEmpty) {
        final snapshots = _snapshotMailLocations(session, restoring);
        _moveMany(session, restoring, MailFolder.inbox);
        notifyListeners();
        List<BulkActionResult>? results;
        try {
          results = await session.mailService.bulkAction('restore', restoring);
        } catch (error) {
          if (!_isOfflineFailure(error)) {
            _restoreMailLocations(session, snapshots);
            notifyListeners();
            rethrow;
          }
          _markOffline(session);
          final store = session.flagsStore;
          if (store != null) {
            try {
              for (final id in restoring) {
                await store.queueMutation(id, 'restore');
              }
            } catch (_) {
              _restoreMailLocations(session, snapshots);
              notifyListeners();
              rethrow;
            }
          }
        }
        if (results != null) {
          final restored = results
              .where((result) => result.success)
              .map((result) => result.mailId)
              .toList();
          final failedSnapshots = _selectMailLocations(
            snapshots,
            restoring.where((id) => !restored.contains(id)),
          );
          if (failedSnapshots.isNotEmpty) {
            _restoreMailLocations(session, failedSnapshots);
            notifyListeners();
          }
          final store = session.flagsStore;
          if (store != null) {
            for (final id in restored) {
              await store.clearQueuedMutation(id, 'location');
            }
          }
          await _fileRestored(session, restored);
          _throwForFailedBulkResults([results]);
        }
      }

      final rest = idsForSession
          .where((id) => !restoring.contains(id))
          .toList();
      if (rest.isNotEmpty) {
        final results = await _bulkAndApplyOrQueue(
          session,
          folder == MailFolder.archive ? 'archive' : 'move',
          rest,
          (succeeded) => _moveMany(session, succeeded, folder),
          folderId: folder == MailFolder.archive ? null : folderId,
        );
        _throwForFailedBulkResults([results]);
      }
    }
  }

  /// `restore` sends each mail back to the folder it was trashed/spammed
  /// from, which only the server tracks — the target a caller passes to
  /// [moveToFolder] says nothing about where it went (a restored draft goes
  /// back to Drafts, not Inbox). Asks the server where each mail landed and
  /// files it there; a mail whose folder can't be determined, or that went
  /// to a folder this client doesn't track, only leaves Trash/Spam locally
  /// and shows up again on that folder's next load.
  Future<void> _fileRestored(AccountSession session, List<String> ids) async {
    if (ids.isEmpty) return;
    final details = await Future.wait(
      ids.map((id) async {
        String? landedFolderId;
        try {
          final detail = await session.mailService.getMail(
            id,
            resolveFolder: (folderId) {
              landedFolderId = folderId;
              return session.resolveFolder(folderId);
            },
          );
          final tracked = session.folderTypeById.containsKey(landedFolderId);
          return tracked ? detail : null;
        } catch (_) {
          return null;
        }
      }),
    );
    for (final detail in details) {
      if (detail == null) continue;
      _removeMany(session, [detail.id]);
      session.emails
          .putIfAbsent(detail.folder, () => <Email>[])
          .insert(0, session.stampLocalFlags(detail));
    }
    notifyListeners();
  }

  @override
  Future<void> markAsRead(List<String> ids) async {
    final results = await Future.wait(
      _groupBySession(ids).entries.map(
        (entry) => _bulkAndApplyOrQueue(
          entry.key,
          'read',
          entry.value,
          (affected) => _replaceMany(
            entry.key,
            affected,
            (mail) => mail.copyWith(isRead: true),
          ),
        ),
      ),
    );
    _throwForFailedBulkResults(results);
  }

  @override
  Future<void> markAsUnread(List<String> ids) async {
    final results = await Future.wait(
      _groupBySession(ids).entries.map(
        (entry) => _bulkAndApplyOrQueue(
          entry.key,
          'unread',
          entry.value,
          (affected) => _replaceMany(
            entry.key,
            affected,
            (mail) => mail.copyWith(isRead: false),
          ),
        ),
      ),
    );
    _throwForFailedBulkResults(results);
  }

  @override
  List<String> get offlineMutationConflicts => [
    for (final session in _scopedSessions) ...session.mutationConflicts,
  ];

  @override
  void dismissMutationConflict(String id) {
    for (final session in _sessions.values) {
      if (session.mutationConflicts.remove(id)) {
        notifyListeners();
        return;
      }
    }
  }

  /// Updates pin state optimistically; the server remains authoritative and
  /// rejected changes are rolled back before the error is returned.
  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    final accountResults = <List<BulkActionResult>>[];
    await Future.wait(
      _groupBySession(ids).entries.map((entry) async {
        final session = entry.key;
        final affected = entry.value;
        final previous = {
          for (final id in affected) id: session.pinnedIds.contains(id),
        };
        if (pinned) {
          session.pinnedIds.addAll(affected);
        } else {
          session.pinnedIds.removeAll(affected);
        }
        _replaceMany(
          session,
          affected,
          (mail) => mail.copyWith(isPinned: pinned),
        );
        notifyListeners();
        List<BulkActionResult> results;
        try {
          results = await session.mailService.setPinned(affected, pinned);
        } catch (error) {
          if (!_isOfflineFailure(error)) {
            _restorePinnedState(session, previous);
            notifyListeners();
            rethrow;
          }
          _markOffline(session);
          try {
            for (final id in affected) {
              await session.flagsStore?.queueMutation(
                id,
                pinned ? 'pin' : 'unpin',
              );
            }
          } catch (_) {
            _restorePinnedState(session, previous);
            notifyListeners();
            rethrow;
          }
          await session.flagsStore?.writePinned(session.pinnedIds);
          return;
        }
        accountResults.add(results);
        final successful = results
            .where((result) => result.success)
            .map((result) => result.mailId)
            .toSet();
        final rejected = {
          for (final id in affected)
            if (!successful.contains(id)) id: previous[id]!,
        };
        if (rejected.isNotEmpty) {
          _restorePinnedState(session, rejected);
          notifyListeners();
        }
        for (final id in successful) {
          await session.flagsStore?.clearQueuedMutation(id, 'pin_state');
        }
        await session.flagsStore?.writePinned(session.pinnedIds);
      }),
    );
    _throwForFailedBulkResults(accountResults);
  }

  void _restorePinnedState(AccountSession session, Map<String, bool> previous) {
    for (final entry in previous.entries) {
      if (entry.value) {
        session.pinnedIds.add(entry.key);
      } else {
        session.pinnedIds.remove(entry.key);
      }
    }
    _replaceMany(
      session,
      previous.keys,
      (mail) => mail.copyWith(isPinned: previous[mail.id] ?? false),
    );
  }

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    final results = await Future.wait(
      _groupBySession(ids).entries.map((entry) {
        final session = entry.key;
        return _bulkAndApplyOrQueue(
          session,
          starred ? 'star' : 'unstar',
          entry.value,
          (affected) {
            starred
                ? session.starredIds.addAll(affected)
                : session.starredIds.removeAll(affected);
            _replaceMany(
              session,
              affected,
              (mail) => mail.copyWith(isStarred: starred),
            );
          },
        );
      }),
    );
    _throwForFailedBulkResults(results);
  }

  /// Records a reply successfully sent from KaydetMail. The "replied" flag
  /// itself is local-only (see [LocalMailFlagsStore]); the resulting read
  /// state goes through the real `read` action instead of being faked
  /// locally.
  @override
  Future<void> markAsReplied(List<String> ids) async {
    if (ids.isEmpty) return;
    await markAsRead(ids);
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final store = session.flagsStore;
      if (store == null) continue;
      session.repliedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.repliedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeRepliedFromKaydetMail(session.repliedFromKaydetMailIds),
        store.writeRepliedFromKaydetMailThreads(
          session.repliedFromKaydetMailThreadIds,
        ),
      ]);
      _restampFlags(session);
    }
    notifyListeners();
  }

  /// Snoozing changes the virtual folder membership, so apply it immediately
  /// and reconcile each item with the backend response. Offline writes stay
  /// queued; rejected online writes restore their previous deadlines.
  @override
  Future<void> setSnoozed(List<String> ids, DateTime? until) async {
    if (ids.isEmpty) return;
    final errors = <Object>[];
    await Future.wait(
      _groupBySession(ids).entries.map((entry) async {
        final session = entry.key;
        final store = session.flagsStore;
        final previous = {
          for (final id in entry.value) id: session.snoozedUntil[id],
        };
        if (until == null) {
          session.snoozedUntil.removeWhere((id, _) => entry.value.contains(id));
        } else {
          final deadline = until.toUtc().millisecondsSinceEpoch;
          for (final id in entry.value) {
            session.snoozedUntil[id] = deadline;
          }
        }
        _recomputeWatchedSnoozeDeadline();
        _touch();
        notifyListeners();

        final rejected = <String>{};
        await Future.wait(
          entry.value.map((id) async {
            try {
              if (until == null) {
                await session.mailService.clearSnooze(id);
              } else {
                await session.mailService.setSnooze(id, until);
              }
              await store?.clearQueuedMutation(id, 'snooze_state');
            } catch (error) {
              if (_isOfflineFailure(error)) {
                _markOffline(session);
                try {
                  await store?.queueMutation(
                    id,
                    until == null ? 'unsnooze' : 'snooze',
                    folderId: until?.toUtc().toIso8601String(),
                  );
                  return;
                } catch (queueError) {
                  errors.add(queueError);
                }
              } else {
                errors.add(error);
              }
              rejected.add(id);
            }
          }),
        );
        for (final id in rejected) {
          final deadline = previous[id];
          if (deadline == null) {
            session.snoozedUntil.remove(id);
          } else {
            session.snoozedUntil[id] = deadline;
          }
        }
        await store?.writeSnoozed(session.snoozedUntil);
        if (rejected.isNotEmpty) {
          _recomputeWatchedSnoozeDeadline();
          _touch();
          notifyListeners();
        }
      }),
    );
    if (errors.isNotEmpty) throw errors.first;
  }

  @override
  DateTime? snoozedUntilOf(String mailId) {
    for (final session in _scopedSessions) {
      final until = _snoozedUntil(session, mailId);
      if (until != null) return until;
    }
    return null;
  }

  /// Records a forward successfully sent from KaydetMail — same split as
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
      session.forwardedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.forwardedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeForwardedFromKaydetMail(session.forwardedFromKaydetMailIds),
        store.writeForwardedFromKaydetMailThreads(
          session.forwardedFromKaydetMailThreadIds,
        ),
      ]);
      _restampFlags(session);
    }
    notifyListeners();
  }

  static String _canonicalName(String name) =>
      name.trim().replaceAll('İ', 'i').toLowerCase();

  void _assertLabelNameIsFree(
    AccountSession session,
    String name, {
    String? selfId,
  }) {
    final canonical = _canonicalName(name);
    if (canonical.isEmpty) throw ArgumentError('Etiket adı boş olamaz.');
    if (session.labels.any(
      (l) => l.id != selfId && _canonicalName(l.name) == canonical,
    )) {
      throw ArgumentError('Bu isimde bir etiket zaten var.');
    }
  }

  /// Mirrors backend-confirmed label state into the local cache so labels
  /// still show while offline. Never the source of truth — see [_loadLabels].
  Future<void> _persistLabels(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeLabelDefs([
      for (final l in session.labels)
        {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
    ]);
    await store.writeLabelMap(session.labelMap);
  }

  Future<void> _queueLabels(
    AccountSession session,
    List<String> mailIds,
    Iterable<String> labelIds,
    String operation,
  ) async {
    _markOffline(session);
    final store = session.flagsStore;
    if (store == null) return;
    for (final mailId in mailIds) {
      for (final labelId in labelIds) {
        await store.queueMutation(mailId, operation, folderId: labelId);
      }
    }
  }

  Future<void> _clearQueuedLabels(
    AccountSession session,
    List<String> mailIds,
    Iterable<String> labelIds,
  ) async {
    final store = session.flagsStore;
    if (store == null) return;
    for (final mailId in mailIds) {
      for (final labelId in labelIds) {
        await store.clearQueuedMutation(
          mailId,
          mutationCategoryFor('label_add', labelId),
        );
      }
    }
  }

  void _restampLabels(AccountSession session, Iterable<String> ids) =>
      _replaceMany(
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
    String? accountId,
  }) async {
    final session = accountId == null
        ? _primarySession
        : _sessionForAccountId(accountId);
    _assertLabelNameIsFree(session, name);
    final trimmed = name.trim();
    Map<String, dynamic> created;
    try {
      created = await session.mailService.createLabel(
        trimmed,
        _signedArgb(color.toARGB32()),
      );
    } on ApiException catch (e) {
      if (e.code == 'label_name_taken') {
        throw ArgumentError('Bu isimde bir etiket zaten var.');
      }
      rethrow;
    }
    final label = MailLabel(
      id: created['id'] as String,
      name: created['name'] as String,
      color: Color(_unsignedArgb(created['color'] as int)),
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
    final trimmed = name.trim();
    try {
      await session.mailService.updateLabel(
        id,
        trimmed,
        _signedArgb(color.toARGB32()),
      );
    } on ApiException catch (e) {
      if (e.code == 'label_name_taken') {
        throw ArgumentError('Bu isimde bir etiket zaten var.');
      }
      rethrow;
    }
    session.labels = [...session.labels]
      ..[index] = MailLabel(id: id, name: trimmed, color: color);
    await _persistLabels(session);
    notifyListeners();
  }

  @override
  Future<void> deleteLabel(String labelId) async {
    final session = _sessionForLabel(labelId);
    if (session == null) return;
    try {
      await session.mailService.deleteLabel(labelId);
    } catch (_) {
      // Never desync: a failed server delete leaves local state untouched.
      return;
    }
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
  ) => _changeEmailLabels(emailIds, labelIds, add: true);

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _changeEmailLabels(emailIds, labelIds, add: false);

  Future<void> _changeEmailLabels(
    List<String> emailIds,
    List<String> labelIds, {
    required bool add,
  }) async {
    Object? firstError;
    for (final entry in _groupBySession(emailIds).entries) {
      final session = entry.key;
      final ownedLabelIds = {
        for (final label in session.labels)
          if (labelIds.contains(label.id)) label.id,
      };
      if (ownedLabelIds.isEmpty) continue;
      final previous = {
        for (final id in entry.value)
          id: List<String>.of(session.labelMap[id] ?? const []),
      };
      for (final id in entry.value) {
        final current = session.labelMap[id] ?? const <String>[];
        session.labelMap[id] = add
            ? [
                ...current,
                ...ownedLabelIds.where((label) => !current.contains(label)),
              ]
            : current.where((label) => !ownedLabelIds.contains(label)).toList();
      }
      _restampLabels(session, entry.value);
      notifyListeners();
      try {
        try {
          if (add) {
            await session.mailService.assignLabels(
              entry.value,
              ownedLabelIds.toList(),
            );
          } else {
            await session.mailService.unassignLabels(
              entry.value,
              ownedLabelIds.toList(),
            );
          }
          await _clearQueuedLabels(session, entry.value, ownedLabelIds);
        } catch (error) {
          if (!_isOfflineFailure(error)) rethrow;
          await _queueLabels(
            session,
            entry.value,
            ownedLabelIds,
            add ? 'label_add' : 'label_remove',
          );
        }
        await _persistLabels(session);
      } catch (error) {
        for (final previousEntry in previous.entries) {
          session.labelMap[previousEntry.key] = previousEntry.value;
        }
        _restampLabels(session, entry.value);
        notifyListeners();
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  }

  void _assertContactEmailIsValid(
    AccountSession session,
    String email, {
    String? selfId,
  }) {
    if (email.isEmpty || !email.contains('@')) {
      throw ArgumentError('Geçerli bir e-posta adresi girin.');
    }
    final canonical = email.toLowerCase();
    if (session.manualContacts.any(
      (c) => c.id != selfId && c.email.toLowerCase() == canonical,
    )) {
      throw ArgumentError('Bu e-posta zaten kayıtlı.');
    }
  }

  Future<void> _persistManualContacts(AccountSession session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeContacts([
      for (final c in session.manualContacts)
        {'id': c.id, 'email': c.email, 'displayName': c.displayName},
    ]);
  }

  /// The session that owns manual contact [id], if any.
  AccountSession? _sessionForManualContact(String id) {
    for (final s in _sessions.values) {
      if (s.manualContacts.any((c) => c.id == id)) return s;
    }
    return null;
  }

  /// Manually-added contacts from every account in scope — the unified
  /// view unions them (dedup by id; account-local ids never collide in
  /// practice), same shape as [getLabels].
  @override
  List<ManualContact> getManualContacts() {
    final seen = <String>{};
    final result = <ManualContact>[];
    for (final session in _scopedSessions) {
      for (final c in session.manualContacts) {
        if (seen.add(c.id)) result.add(c);
      }
    }
    return List.unmodifiable(result);
  }

  @override
  List<ManualContact> getManualContactsForAccount(String accountId) =>
      List.unmodifiable(
        _sessions[accountId]?.manualContacts ?? const <ManualContact>[],
      );

  @override
  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
    String? accountId,
  }) async {
    final session = accountId != null
        ? _sessionForAccountId(accountId)
        : _primarySession;
    final trimmedEmail = email.trim();
    final trimmedName = displayName?.trim();
    final name = (trimmedName == null || trimmedName.isEmpty)
        ? null
        : trimmedName;
    _assertContactEmailIsValid(session, trimmedEmail);
    Map<String, dynamic> created;
    try {
      created = await session.mailService.createContact(trimmedEmail, name);
    } on ApiException catch (e) {
      if (e.code == 'contact_already_exists') {
        throw ArgumentError('Bu e-posta zaten kayıtlı.');
      }
      if (!_isOfflineFailure(e)) rethrow;
      _markOffline(session);
      created = {
        'id': '$_localContactIdPrefix${newIdempotencyKey()}',
        'email': trimmedEmail,
        'displayName': name,
      };
      await _queueContactMutation(
        session,
        created['id'] as String,
        'contact_create',
        created,
      );
    }
    final contact = ManualContact(
      id: created['id'] as String,
      accountId: session.account.id,
      email: created['email'] as String,
      displayName: created['displayName'] as String?,
    );
    session.manualContacts = [...session.manualContacts, contact];
    await _persistManualContacts(session);
    notifyListeners();
    return contact;
  }

  @override
  Future<void> updateManualContact({
    required String id,
    required String email,
    String? displayName,
  }) async {
    final session = _sessionForManualContact(id);
    if (session == null) return;
    final index = session.manualContacts.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final trimmedEmail = email.trim();
    final trimmedName = displayName?.trim();
    final name = (trimmedName == null || trimmedName.isEmpty)
        ? null
        : trimmedName;
    _assertContactEmailIsValid(session, trimmedEmail, selfId: id);
    Map<String, dynamic> updated = {'email': trimmedEmail, 'displayName': name};
    if (id.startsWith(_localContactIdPrefix)) {
      await _queueContactMutation(session, id, 'contact_create', updated);
    } else {
      try {
        updated = await session.mailService.updateContact(
          id,
          trimmedEmail,
          name,
        );
        await session.flagsStore?.clearQueuedMutation(id, 'contact');
      } on ApiException catch (e) {
        if (e.code == 'contact_already_exists') {
          throw ArgumentError('Bu e-posta zaten kayıtlı.');
        }
        if (!_isOfflineFailure(e)) rethrow;
        _markOffline(session);
        await _queueContactMutation(session, id, 'contact_update', updated);
      }
    }
    session.manualContacts = [...session.manualContacts]
      ..[index] = ManualContact(
        id: id,
        accountId: session.account.id,
        email: updated['email'] as String,
        displayName: updated['displayName'] as String?,
      );
    await _persistManualContacts(session);
    notifyListeners();
  }

  @override
  Future<void> deleteManualContact(String id) async {
    final session = _sessionForManualContact(id);
    if (session == null) return;
    final store = session.flagsStore;
    if (id.startsWith(_localContactIdPrefix)) {
      await store?.clearQueuedMutation(id, 'contact');
    } else {
      try {
        await session.mailService.deleteContact(id);
        await store?.clearQueuedMutation(id, 'contact');
      } catch (error) {
        if (!_isOfflineFailure(error)) return;
        _markOffline(session);
        await store?.queueMutation(id, 'contact_delete');
      }
    }
    session.manualContacts = session.manualContacts
        .where((c) => c.id != id)
        .toList();
    await _persistManualContacts(session);
    notifyListeners();
  }

  Future<void> _queueContactMutation(
    AccountSession session,
    String id,
    String operation,
    Map<String, dynamic> contact,
  ) async {
    await session.flagsStore?.queueMutation(
      id,
      operation,
      folderId: jsonEncode({
        'email': contact['email'],
        'displayName': contact['displayName'],
      }),
    );
  }
}
