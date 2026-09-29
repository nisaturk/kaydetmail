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
import 'api/contact_module.dart';
import 'api/draft_module.dart';
import 'api/folder_module.dart';
import 'api/label_module.dart';
import 'api/mail_actions_module.dart';
import 'api/mail_buckets.dart';
import 'api/repository_context.dart';
import 'api/search_module.dart';
import 'api/session_registry.dart';
import 'api/signature_module.dart';
import 'api/template_module.dart';
import 'mail_repository.dart';
import '../l10n/l10n.dart';

const _allMailSourceFolders = [
  MailFolder.inbox,
  MailFolder.sent,
  MailFolder.drafts,
  MailFolder.spam,
  MailFolder.trash,
  MailFolder.archive,
];

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
class ApiMailRepository extends MailRepository implements RepositoryContext {
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
  late final MailBuckets _buckets = MailBuckets(_touch);
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
        _drafts.scheduleSync();
      }
      _startSnoozeExpiryTimerIfNeeded();
      _folders.hydrateFromCache(session);
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
          color: Color(LabelModule.unsignedArgb(label['color'] as int)),
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
            color: Color(LabelModule.unsignedArgb(d['color'] as int)),
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
            color: Color(LabelModule.unsignedArgb(d['color'] as int)),
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
            LabelModule.signedArgb(d['color'] as int),
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
    _folders.applyFolderMap(session, await session.mailService.getFolders());
    _cancelReconnectRetry(session);
    session.offline = false;
    await _actions.replayQueuedMutations(session);
    _folders.persistFolderMap(session);
    notifyListeners();
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
      _buckets.replaceMany(
        session,
        session.starredIds,
        (e) => e.copyWith(isStarred: true),
      );
    } catch (_) {}
  }

  static bool _isOfflineFailure(Object error) =>
      error is ApiException &&
      (error.category == ApiErrorCategory.network ||
          error.category == ApiErrorCategory.timeout);

  void _markOffline(AccountSession session) {
    session.offline = true;
    _scheduleReconnectRetry(session);
  }

  Iterable<AccountSession> get _scopedSessions => _registry.scoped;
  AccountSession get _primarySession => _registry.primary;
  AccountSession? _sessionOwning(String id) => _registry.owning(id);
  AccountSession? _sessionForThread(String id) => _registry.forThread(id);
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
            if (s.activeSnoozeDeadline(e.id) case final until?)
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
                        s.activeSnoozeDeadline(e.id) == null,
                  ),
          ]
        : [
            for (final s in sessions)
              ...(s.emails[folder] ?? const <Email>[]).where(
                (e) => s.activeSnoozeDeadline(e.id) == null,
              ),
          ];
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(pinnedFirst(result));
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
    await _actions.replayQueuedMutations(session);
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
    await _actions.replayQueuedMutations(session);
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
      _drafts.resolveFrom(refreshed);
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
      throw ArgumentError(l10nNow.theSenderAddressCouldntBe);
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

  late final LabelModule _labels = LabelModule(this);
  late final ContactModule _contacts = ContactModule(this);

  @override
  List<MailLabel> getLabels() => _labels.getLabels();

  @override
  List<MailLabel> getLabelsForAccount(String accountId) =>
      _labels.getLabelsForAccount(accountId);

  @override
  Future<MailLabel> createLabel({
    required String name,
    required Color color,
    String? accountId,
  }) => _labels.createLabel(name: name, color: color, accountId: accountId);

  @override
  Future<void> updateLabel({
    required String id,
    required String name,
    required Color color,
  }) => _labels.updateLabel(id: id, name: name, color: color);

  @override
  Future<void> deleteLabel(String labelId) => _labels.deleteLabel(labelId);

  @override
  Future<void> addLabelsToEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _labels.addLabelsToEmails(emailIds, labelIds);

  @override
  Future<void> removeLabelsFromEmails(
    List<String> emailIds,
    List<String> labelIds,
  ) => _labels.removeLabelsFromEmails(emailIds, labelIds);

  @override
  List<ManualContact> getManualContacts() => _contacts.getManualContacts();

  @override
  List<ManualContact> getManualContactsForAccount(String accountId) =>
      _contacts.getManualContactsForAccount(accountId);

  @override
  Future<ManualContact> addManualContact({
    required String email,
    String? displayName,
    String? accountId,
  }) => _contacts.addManualContact(
    email: email,
    displayName: displayName,
    accountId: accountId,
  );

  @override
  Future<void> updateManualContact({
    required String id,
    required String email,
    String? displayName,
  }) => _contacts.updateManualContact(
    id: id,
    email: email,
    displayName: displayName,
  );

  @override
  Future<void> deleteManualContact(String id) =>
      _contacts.deleteManualContact(id);

  // --- RepositoryContext (what the modules share) -------------------------

  @override
  SessionRegistry get registry => _registry;

  @override
  MailCache? get cache => _cache;

  @override
  void notify() => notifyListeners();

  @override
  bool isOfflineFailure(Object error) => _isOfflineFailure(error);

  @override
  void markOffline(AccountSession session) => _markOffline(session);

  @override
  void replaceMany(
    AccountSession session,
    List<String> ids,
    Email Function(Email) update,
  ) => _buckets.replaceMany(session, ids, update);

  late final FolderModule _folders = FolderModule(this);

  @override
  List<MailCustomFolder> getCustomFolders({String? accountId}) =>
      _folders.getCustomFolders(accountId: accountId);

  @override
  List<MailFolderInfo> getAccountFolders(String accountId) =>
      _folders.getAccountFolders(accountId);

  @override
  Map<MailFolder, String> standardFolderIds(String accountId) =>
      _folders.standardFolderIds(accountId);

  @override
  Future<void> refreshCustomFolders({
    String? accountId,
    bool rediscover = false,
  }) => _folders.refreshCustomFolders(
    accountId: accountId,
    rediscover: rediscover,
  );

  @override
  Future<void> createCustomFolder({
    required String accountId,
    required String name,
    String? parentFolderId,
  }) => _folders.createCustomFolder(
    accountId: accountId,
    name: name,
    parentFolderId: parentFolderId,
  );

  @override
  Future<void> renameCustomFolder({
    required String accountId,
    required String folderId,
    required String name,
  }) => _folders.renameCustomFolder(
    accountId: accountId,
    folderId: folderId,
    name: name,
  );

  @override
  Future<void> changeCustomFolderParent({
    required String accountId,
    required String folderId,
    required String? parentFolderId,
  }) => _folders.changeCustomFolderParent(
    accountId: accountId,
    folderId: folderId,
    parentFolderId: parentFolderId,
  );

  @override
  Future<void> deleteCustomFolder({
    required String accountId,
    required String folderId,
  }) => _folders.deleteCustomFolder(accountId: accountId, folderId: folderId);

  @override
  List<MailFolderRoleAssignment> getFolderRoleAssignments({
    String? accountId,
  }) => _folders.getFolderRoleAssignments(accountId: accountId);

  @override
  Future<void> setFolderRole({
    required String accountId,
    required String folderId,
    required MailFolder? role,
  }) => _folders.setFolderRole(
    accountId: accountId,
    folderId: folderId,
    role: role,
  );

  @override
  Set<MailFolder> availableFolders(String accountId) =>
      _folders.availableFolders(accountId);

  late final DraftModule _drafts = DraftModule(this);

  @override
  Stream<Email> get draftSyncFailures => _drafts.draftSyncFailures;

  @override
  void detachDraftSyncFailureHandler(String draftId) =>
      _drafts.detachDraftSyncFailureHandler(draftId);

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
  }) => _drafts.saveDraft(
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    body: body,
    bodyHtml: bodyHtml,
    attachments: attachments,
    from: from,
    fromAccountId: fromAccountId,
    threadId: threadId,
    inReplyToId: inReplyToId,
    identityId: identityId,
    draftId: draftId,
    onSyncFailure: onSyncFailure,
  );

  @override
  Future<void> deleteDraft(String draftId) => _drafts.deleteDraft(draftId);

  /// Sends a draft via `POST /api/drafts/{id}/send`.
  Future<Email?> sendDraft(String draftId) => _drafts.sendDraft(draftId);

  @override
  void touch() => _touch();

  @override
  Future<void> refreshFolderMail(AccountSession session, MailFolder folder) =>
      _refreshEmailsFor(session, folder);

  @override
  void removeMany(AccountSession session, Iterable<String> ids) =>
      _buckets.removeMany(session, ids);

  @override
  Map<String, MailLocationSnapshot> snapshotMailLocations(
    AccountSession session,
    Iterable<String> ids,
  ) => _buckets.snapshotMailLocations(session, ids);

  @override
  void restoreMailLocations(
    AccountSession session,
    Map<String, MailLocationSnapshot> snapshots,
  ) => _buckets.restoreMailLocations(session, snapshots);

  late final MailActionsModule _actions = MailActionsModule(this, _buckets);

  @override
  Future<void> moveToTrash(List<String> ids) => _actions.moveToTrash(ids);

  @override
  Future<void> deletePermanently(List<String> ids) =>
      _actions.deletePermanently(ids);

  @override
  Future<void> moveToFolder(List<String> ids, MailFolder folder) =>
      _actions.moveToFolder(ids, folder);

  @override
  Future<void> markAsRead(List<String> ids) => _actions.markAsRead(ids);

  @override
  Future<void> markAsUnread(List<String> ids) => _actions.markAsUnread(ids);

  @override
  List<String> get offlineMutationConflicts =>
      _actions.offlineMutationConflicts;

  @override
  void dismissMutationConflict(String id) =>
      _actions.dismissMutationConflict(id);

  @override
  Future<void> setPinned(List<String> ids, bool pinned) =>
      _actions.setPinned(ids, pinned);

  @override
  Future<void> setStarred(List<String> ids, bool starred) =>
      _actions.setStarred(ids, starred);

  @override
  Future<void> markAsReplied(List<String> ids) => _actions.markAsReplied(ids);

  @override
  Future<void> markAsForwarded(List<String> ids) =>
      _actions.markAsForwarded(ids);

  @override
  Future<void> setSnoozed(List<String> ids, DateTime? until) =>
      _actions.setSnoozed(ids, until);

  @override
  DateTime? snoozedUntilOf(String mailId) => _actions.snoozedUntilOf(mailId);

  @override
  void refreshCounts(AccountSession session) =>
      unawaited(_refreshCountsFor(session));

  @override
  void recomputeSnoozeDeadline() => _recomputeWatchedSnoozeDeadline();

  @override
  Future<Set<String>> loadPinnedIds(
    AccountSession session,
    LocalMailFlagsStore store,
  ) => _loadPinnedIds(session, store);

  @override
  Future<Map<String, int>> loadSnoozedUntil(
    AccountSession session,
    LocalMailFlagsStore store,
  ) => _loadSnoozedUntil(session, store);

  @override
  Future<void> loadManualContacts(
    AccountSession session,
    LocalMailFlagsStore store,
  ) => _loadManualContacts(session, store);

  @override
  Future<void> persistContacts(AccountSession session) =>
      _contacts.persist(session);

  @override
  void restampLabels(AccountSession session, Iterable<String> ids) =>
      _labels.restamp(session, ids);

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
  List<Email> cachedCustomFolderMails(String accountId, String folderId) =>
      List.unmodifiable(
        _sessionForAccountId(accountId).customFolderEmails[folderId] ??
            const [],
      );

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
  Future<void> moveToCustomFolder(
    List<String> ids, {
    required String accountId,
    required String folderId,
  }) async {
    if (ids.isEmpty) return;
    final session = _sessionForAccountId(accountId);
    final results = await _actions.bulkAndApplyOrQueue(session, 'move', ids, (
      succeeded,
    ) {
      _buckets.removeMany(session, succeeded);
      session.forgetCustomFolderMails(folderId);
    }, folderId: folderId);
    final failure = results.where((r) => !r.success).firstOrNull;
    if (failure != null) {
      throw ApiException(status: 0, code: failure.code ?? 'mail_move_failed');
    }
  }

  /// Prefill data for the reply/reply-all/forward screen (see
  /// [ApiMailService.getComposePrefill]).
  @override
  Future<ComposePrefill> getComposePrefill(String sourceMailId, String mode) {
    final session = _sessionOwning(sourceMailId) ?? _primarySession;
    return session.mailService.getComposePrefill(sourceMailId, mode);
  }

  late final SearchModule _search = SearchModule(this);

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
  }) => _search.searchOnServer(
    query: query,
    accountId: accountId,
    folder: folder,
    customFolderId: customFolderId,
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
  }) => _search.searchRemote(
    query: query,
    accountId: accountId,
    folder: folder,
    customFolderId: customFolderId,
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

  @override
  Future<int> queuedOfflineMutationCount(String accountId) async {
    final store = _sessions[accountId]?.flagsStore;
    if (store == null) return 0;
    return (await store.readQueuedMutations()).length;
  }
}
