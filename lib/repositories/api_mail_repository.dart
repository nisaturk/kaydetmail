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
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../models/mail_custom_folder.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_rule.dart';
import '../models/mail_signature.dart';
import '../models/mail_session.dart';
import '../models/mail_template.dart';
import '../models/manual_contact.dart';
import '../models/remote_search_result.dart';
import '../models/scheduled_send.dart';
import '../models/scheduled_send_detail.dart';
import '../models/reply_reminder.dart';
import '../models/mail_snippet.dart';
import '../models/trusted_sender.dart';
import '../models/server_mail_rule.dart';
import '../services/api_auth_service.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/api_mail_service.dart';
import '../services/device_identifier_provider.dart';
import '../services/local_mail_flags_store.dart';
import '../services/mail_cache.dart';
import '../services/mail_rules_store.dart';
import '../services/signature_store.dart';
import '../models/attachment_download_state.dart';
import '../services/attachment_download_manager.dart';
import '../services/token_store.dart';
import 'mail_repository.dart';

/// Everything one connected mailbox needs to operate independently: its own
/// authenticated HTTP session, its own folder/mail cache, and its own
/// backend-backed pin/snooze/label/contact state plus local reply/forward flags.
/// Multiple accounts hold multiple [_Session]s side by side — connecting a
/// second account never touches the first one's tokens, mail, or flags.
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

  /// See [ApiMailRepository.offlineMutationConflicts].
  final Set<String> mutationConflicts = {};

  final Map<MailFolder, String> folderIds = {};
  final Map<String, MailFolder> folderTypeById = {};
  final Map<MailFolder, List<Email>> emails = {};
  final Map<MailFolder, int> pages = {};
  final Map<MailFolder, int> serverUnread = {};
  final Map<MailFolder, bool> hasMore = {};

  /// Set on every successful `_loadMoreFor`/`_refreshEmailsFor` fetch for
  /// the folder — the "son senkronizasyon" hint on empty/error states.
  final Map<MailFolder, DateTime> lastSynced = {};
  final Map<String, int> serverThreadSizes = {};

  Set<String> pinnedIds = {};
  final Set<String> starredIds = {};
  Set<String> repliedFromKaydetMailIds = {};
  Set<String> forwardedFromKaydetMailIds = {};
  Set<String> repliedFromKaydetMailThreadIds = {};
  Set<String> forwardedFromKaydetMailThreadIds = {};

  /// ThreadId-keyed: Sent-folder conversations that have received an
  /// inbound reply — the mirror direction of [repliedFromKaydetMailThreadIds]. See
  /// [ApiMailRepository._markSentThreadsAnswered].
  Set<String> threadsReceivedReplyIds = {};

  List<MailLabel> labels = [];
  Map<String, List<String>> labelMap = {};
  List<ManualContact> manualContacts = [];
  List<MailTemplate>? templates;

  /// Cached snooze deadlines (mail id -> epoch millis), fetched from the
  /// backend or read from [LocalMailFlagsStore] while offline. A mail past
  /// its timestamp is treated as not-snoozed everywhere below.
  Map<String, int> snoozedUntil = {};

  /// Scheduled sends known for this account, soonest first. Populated by
  /// [ApiMailRepository.refreshScheduledSends].
  List<ScheduledSend> scheduledSends = [];

  List<MailSignature>? signatures;
  SignatureDefaults? signatureDefaults;
  List<MailIdentity>? identities;
  List<ReplyReminder> replyReminders = [];

  /// Non-standard IMAP folders reported for this account by the last
  /// [ApiMailRepository.refreshCustomFolders]. Populated on demand, not on
  /// every login, since most accounts never open the custom-folders screen.
  List<ApiMailFolder> customFolders = [];
  bool folderHierarchyRequested = false;
  final Map<String, List<Email>> customFolderEmails = {};
  final Map<String, int> customFolderPages = {};
  final Map<String, bool> customFolderHasMore = {};

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

  /// Finds an already-loaded mail by id, regardless of which folder bucket
  /// it currently sits in. Used to resolve a message's threadId when only
  /// its id is known (e.g. [ApiMailRepository.markAsReplied]).
  Email? findLoaded(String id) {
    for (final list in emails.values) {
      for (final email in list) {
        if (email.id == id) return email;
      }
    }
    return null;
  }

  /// Overlays the locally-persisted pin/reply/forward/label flags onto a
  /// mail freshly mapped from the API — the server has no concept of any of
  /// them, so every fetch would otherwise reset them. Also stamps the owning
  /// account: list and conversation responses carry no `accountId`, and
  /// account-local features (labels) resolve through it.
  ///
  /// Reply/forward also check the thread-level sets: the user marks these
  /// by opening a specific message, but every message sharing its thread
  /// should show the icon too, even when that specific message isn't
  /// currently loaded into memory (e.g. it lives in a folder not yet
  /// fetched this session) — see [ApiMailRepository.markAsReplied].
  Email stampLocalFlags(Email email) => email.copyWith(
    accountId: account.id,
    isStarred: email.isStarred || starredIds.contains(email.id),
    isPinned: pinnedIds.contains(email.id),
    repliedFromKaydetMail:
        email.repliedFromKaydetMail ||
        repliedFromKaydetMailIds.contains(email.id) ||
        (email.threadId.isNotEmpty &&
            repliedFromKaydetMailThreadIds.contains(email.threadId)),
    forwardedFromKaydetMail:
        forwardedFromKaydetMailIds.contains(email.id) ||
        (email.threadId.isNotEmpty &&
            forwardedFromKaydetMailThreadIds.contains(email.threadId)),
    threadReceivedReply:
        email.threadId.isNotEmpty &&
        threadsReceivedReplyIds.contains(email.threadId),
    labelIds: labelMap[email.id] ?? const [],
  );
}

/// [MailRepository] backed by the real backend. Pins, snoozes, labels and
/// manual contacts are backend-owned with an offline device cache and queue;
/// replied/forwarded-from-app flags stay local per account.
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
    this._snoozeExpiryCheckInterval = const Duration(seconds: 30),
    AttachmentDownloadManager? attachmentDownloadManager,
  }) : _initialAuthService = authService,
       _initialMailService = mailService,
       _attachmentDownloadManager =
           attachmentDownloadManager ?? AttachmentDownloadManager.instance;

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
  MailCache? _cache;

  /// Every connected account's session, keyed by account id, in connection
  /// order (a `Map` literal is insertion-ordered) — that order is also
  /// [accounts]' order and the order accounts restore in at app launch.
  final Map<String, _Session> _sessions = {};
  final Map<String, ComposeLimits> _composeLimits = {};
  final Set<String> _remoteImageMailIds = {};

  /// `null` selects the unified mailbox (every session); non-null narrows
  /// every read/write below to that one session.
  String? _activeAccountId;

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
      await _unregisterDeviceFor(session);
      await session.authService.logout();
      session.persistTimer?.cancel();
      _cancelReconnectRetry(session);
      _cache?.clear(session.account.id);
      _sessions.remove(session.account.id);
    }
    _activeAccountId = null;
    _stopSnoozeExpiryTimer();
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
      session.pinnedIds = await _loadPinnedIds(session, flags);
      session.repliedFromKaydetMailIds = await flags.readRepliedFromKaydetMail();
      session.forwardedFromKaydetMailIds = await flags.readForwardedFromKaydetMail();
      session.repliedFromKaydetMailThreadIds = await flags.readRepliedFromKaydetMailThreads();
      session.forwardedFromKaydetMailThreadIds = await flags.readForwardedFromKaydetMailThreads();
      session.threadsReceivedReplyIds = await flags.readThreadsReceivedReply();
      await _loadLabels(session, flags);
      await _loadManualContacts(session, flags);
      session.snoozedUntil = await _loadSnoozedUntil(session, flags);
      session.flagsStore = flags;
      _recomputeWatchedSnoozeDeadline();
      _startSnoozeExpiryTimerIfNeeded();
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
      unawaited(_migrateLegacySignature(session));
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

  /// Pin state is account-scoped on the backend now; falls back to the
  /// local cache (and re-seeds it on success) so pins still show while
  /// offline.
  Future<Set<String>> _loadPinnedIds(
    _Session session,
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
    _Session session,
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
  Future<void> _loadLabels(_Session session, LocalMailFlagsStore flags) async {
    await _migrateLegacyLabels(session, flags);
    try {
      final defs = await session.mailService.getLabels();
      session.labels = [
        for (final d in defs)
          MailLabel(
            id: d['id'] as String,
            name: d['name'] as String,
            color: Color(d['color'] as int),
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
            color: Color(d['color'] as int),
          ),
      ];
      session.labelMap = await flags.readLabelMap();
    }
  }

  /// Backend-first load of manually-added contacts, same shape as
  /// [_loadLabels] minus any migration — this is a new feature with no
  /// pre-cutover local data to carry forward.
  Future<void> _loadManualContacts(
    _Session session,
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
  /// must never affect login, and [_loadLabels] falls back to the local
  /// cache regardless.
  Future<void> _migrateLegacyLabels(
    _Session session,
    LocalMailFlagsStore flags,
  ) async {
    try {
      final existing = await session.mailService.getLabels();
      final localDefs = await flags.readLabelDefs();
      if (existing.isNotEmpty) {
        await MailRulesStore.remapLabelIds(session.account.id, {
          for (final local in localDefs)
            for (final server in existing)
              if ((local['name'] as String).toLowerCase() ==
                  (server['name'] as String).toLowerCase())
                (local['id'] as String): server['id'] as String,
        });
        return;
      }
      final defs = localDefs.isNotEmpty
          ? localDefs
          : LocalMailFlagsStore.defaultLabels;
      final idRemap = <String, String>{};
      for (final d in defs) {
        final created = await session.mailService.createLabel(
          d['name'] as String,
          d['color'] as int,
        );
        idRemap[d['id'] as String] = created['id'] as String;
      }
      if (localDefs.isNotEmpty) {
        for (final entry in (await flags.readLabelMap()).entries) {
          final remapped = [
            for (final oldId in entry.value)
              if (idRemap[oldId] != null) idRemap[oldId]!,
          ];
          if (remapped.isNotEmpty) {
            await session.mailService.assignLabels([entry.key], remapped);
          }
        }
      }
      await MailRulesStore.remapLabelIds(session.account.id, idRemap);
    } catch (_) {
      // Best-effort — a failure here must never affect login. Cached labels
      // remain available via [_loadLabels] until migration can run again.
    }
  }

  /// One-time migration for pre-cutover installs: if the backend has no
  /// signature yet but the old per-device SharedPreferences store does,
  /// push it once so it starts syncing. Best-effort — a failure here must
  /// never affect login.
  Future<void> _migrateLegacySignature(_Session session) async {
    if (session.account.signature != null) return;
    try {
      final legacy = await SignatureStore.load(session.account.email);
      if (legacy.trim().isEmpty) return;
      await session.mailService.updateSignature(legacy);
      session.account = session.account.copyWith(signature: legacy);
      await SignatureStore.save(session.account.email, '');
      notifyListeners();
    } catch (_) {
      // Best-effort; the legacy value stays local and compose still finds
      // it via SignatureStore until the next successful login.
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
    await _attachmentDownloadManager.removeAccount(accountId);
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
    await _replayQueuedMutations(session);
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

  /// Re-derives every loaded mail's flags (backend-backed pin/labels,
  /// IMAP-backed star and local replied/forwarded) from [session]'s sets.
  /// Used instead of [_replaceMany] when a change can affect mail beyond
  /// the ids the caller touched directly — e.g. marking one message replied
  /// also marks every other loaded message in its thread.
  void _restampFlags(_Session session) {
    _touch();
    for (final folder in session.emails.keys.toList()) {
      session.emails[folder] = [
        for (final email in session.emails[folder]!)
          session.stampLocalFlags(email),
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
    _dropFromCustomFolderMails(session, idSet);
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

  static bool _isOfflineFailure(Object error) =>
      error is ApiException &&
      (error.category == ApiErrorCategory.network ||
          error.category == ApiErrorCategory.timeout);

  void _markOffline(_Session session) {
    session.offline = true;
    _scheduleReconnectRetry(session);
  }

  /// Applies a bulk action within [session], optimistically and durably
  /// queueing it for replay when the request cannot reach the backend.
  /// Used for every operation spec docs-dev §8 requires an offline queue
  /// for (`read`, `unread`, `star`, `unstar`, `archive`, `trash`, `move`;
  /// `restore` is handled separately in [moveToFolder] since its offline
  /// target folder is a placeholder corrected on replay, not the final
  /// state): a transport failure still applies [apply] to the local cache
  /// optimistically and queues [operation] in [LocalMailFlagsStore] for
  /// replay once the account reconnects (see [_replayQueuedMutations]),
  /// instead of throwing. `delete` is deliberately never queued — it is
  /// permanent and irreversible, so a silent offline queue for it would be
  /// unsafe.
  Future<List<BulkActionResult>> _bulkAndApplyOrQueue(
    _Session session,
    String operation,
    List<String> ids,
    void Function(List<String> succeededIds) apply, {
    String? folderId,
  }) async {
    if (ids.isEmpty) return const [];
    List<BulkActionResult> results;
    try {
      results = await session.mailService.bulkAction(
        operation,
        ids,
        folderId: folderId,
      );
    } catch (_) {
      session.offline = true;
      _scheduleReconnectRetry(session);
      final store = session.flagsStore;
      if (store != null) {
        for (final id in ids) {
          await store.queueMutation(id, operation, folderId: folderId);
        }
      }
      apply(ids);
      notifyListeners();
      return const [];
    }
    final succeeded = results
        .where((r) => r.success)
        .map((r) => r.mailId)
        .toList();
    final store = session.flagsStore;
    if (store != null) {
      final category = mutationCategoryFor(operation);
      for (final id in succeeded) {
        await store.clearQueuedMutation(id, category);
      }
    }
    apply(succeeded);
    notifyListeners();
    unawaited(_refreshCountsFor(session));
    return results;
  }

  /// Replays queued mail, pin/snooze/label and manual contact mutations.
  /// Transport failures remain queued for the next reconnect. Server
  /// rejections are dropped and surfaced through [offlineMutationConflicts];
  /// backend-owned state is re-read to replace rejected optimistic changes.
  /// Mail changes in the same category and contact changes for the same id
  /// collapse at queue time (see `LocalMailFlagsStore.queueMutation`).
  Future<void> _replayQueuedMutations(_Session session) async {
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
    if (appState.isNotEmpty) await _replayAppState(session, store, appState);
    if (queued.isEmpty) return;
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
    _Session session,
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
    _Session session,
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

  static bool _pinned(Email email) => email.isPinned;

  /// Sent items open past [MailRepository.unansweredReminderThreshold] with
  /// no inbound reply float to the top of the Sent view (below pinned) —
  /// same age gate as the "Yanıtlanmadı" badge in `MailListItem`, so the
  /// sort order and the badge never disagree. Gated by
  /// [MailRepository.unansweredReminderEnabled], currently off.
  static bool _isStaleUnanswered(Email email) =>
      MailRepository.unansweredReminderEnabled &&
      !email.threadReceivedReply &&
      DateTime.now().difference(email.timestamp) >
          MailRepository.unansweredReminderThreshold;

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
    if (folder == MailFolder.snoozed) {
      final pairs = [
        for (final s in sessions)
          for (final e in s.emails.values.expand((list) => list))
            if (_snoozedUntil(s, e.id) case final until?)
              (email: e, until: until),
      ];
      pairs.sort((a, b) => a.until.compareTo(b.until));
      return List.unmodifiable([for (final p in pairs) p.email]);
    }
    final result = folder == MailFolder.starred
        ? [
            for (final s in sessions)
              ...s.emails.values
                  .expand((list) => list)
                  .where((e) => e.isStarred && _snoozedUntil(s, e.id) == null),
          ]
        : [
            for (final s in sessions)
              ...(s.emails[folder] ?? const <Email>[]).where(
                (e) => _snoozedUntil(s, e.id) == null,
              ),
          ];
    result.sort((a, b) {
      final ha = _pinned(a);
      final hb = _pinned(b);
      if (ha != hb) return ha ? -1 : 1;
      if (folder == MailFolder.sent) {
        final ua = _isStaleUnanswered(a);
        final ub = _isStaleUnanswered(b);
        if (ua != ub) return ua ? -1 : 1;
      }
      return b.timestamp.compareTo(a.timestamp);
    });
    return List.unmodifiable(result);
  }

  /// The active snooze deadline for [mailId] in [session], or null when it
  /// isn't snoozed or the snooze already elapsed (elapsed entries are left
  /// in storage — they're simply inert — and pruned lazily on next write).
  DateTime? _snoozedUntil(_Session session, String mailId) {
    final ms = session.snoozedUntil[mailId];
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(DateTime.now()) ? until : null;
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
  bool hasMoreEmails(MailFolder folder) {
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
    for (final session in _scopedSessions) {
      final synced = session.lastSynced[folder];
      if (synced != null && (latest == null || synced.isAfter(latest))) {
        latest = synced;
      }
    }
    return latest;
  }

  @override
  Future<List<Email>> loadMoreEmails(MailFolder folder) async {
    final results = await Future.wait(
      _scopedSessions.map((s) => _loadMoreFor(s, folder)),
    );
    return results.expand((r) => r).toList();
  }

  Future<List<Email>> _loadMoreFor(_Session session, MailFolder folder) async {
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
    session.emails[folder] = [...refreshed, ...stale]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    session.pages[folder] = max(session.pages[folder] ?? 1, result.page);
    session.hasMore[folder] =
        (session.emails[folder]?.length ?? 0) < result.total;
    session.lastSynced[folder] = DateTime.now();
    if (folder == MailFolder.inbox) {
      final newlyArrived = [
        for (final e in result.items)
          if (old[e.id] == null) e,
      ];
      if (newlyArrived.isNotEmpty) {
        await _markSentThreadsAnswered(session, newlyArrived);
      }
    }
    notifyListeners();
  }

  /// A reply landing in Inbox for a thread the user has mail in Sent marks
  /// that Sent-folder conversation "answered" — the mirror direction of
  /// [markAsReplied] (replying to something in Inbox marks it via
  /// [_Session.repliedFromKaydetMailThreadIds]; here, receiving a reply marks the Sent
  /// thread via [_Session.threadsReceivedReplyIds]). Threads whose Sent message
  /// hasn't been loaded into memory this session simply can't be detected
  /// yet — it catches up once Sent is opened and a further reply arrives,
  /// same best-effort tradeoff as [stampLocalFlags]'s thread-level sets.
  Future<void> _markSentThreadsAnswered(
    _Session session,
    Iterable<Email> newlyArrived,
  ) async {
    final sentThreadIds = {
      for (final e in session.emails[MailFolder.sent] ?? const <Email>[])
        if (e.threadId.isNotEmpty) e.threadId,
    };
    if (sentThreadIds.isEmpty) return;
    var changed = false;
    for (final email in newlyArrived) {
      if (email.threadId.isEmpty) continue;
      if (!sentThreadIds.contains(email.threadId)) continue;
      if (session.threadsReceivedReplyIds.add(email.threadId)) changed = true;
    }
    if (!changed) return;
    final store = session.flagsStore;
    if (store != null) {
      await store.writeThreadsReceivedReply(session.threadsReceivedReplyIds);
    }
    _restampFlags(session);
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
    final sessions = _scopedSessions.toList();
    if (sessions.isEmpty) return;
    final jobs = [
      for (final session in sessions)
        if (session.folderIds[folder] case final String folderId)
          session.mailService.syncFolderId(folderId),
    ];
    if (jobs.isEmpty) {
      throw ArgumentError('Unknown folder for this account: $folder');
    }
    await Future.wait(jobs);
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
            allowRemoteImages: _remoteImageMailIds.contains(id),
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
    final items = await _sessionForAccountId(
      accountId,
    ).mailService.getTrustedSenders();
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
        if (raw['hasAttachments'] != true &&
            !_remoteImageMailIds.contains(id)) {
          return summary;
        }
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
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
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
        idempotencyKey: idempotencyKey ?? _newIdempotencyKey(),
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
      senderName: session.account.displayName ?? '',
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
    required DateTime sendAt,
  }) async {
    final session = _sessionForCompose(
      from: from,
      fromAccountId: fromAccountId,
    );
    final scheduled = await session.mailService.scheduleSend(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      attachments: attachments,
      replySourceMailId: inReplyToId,
      identityId: identityId,
      sendAtUtc: sendAt,
      idempotencyKey: _newIdempotencyKey(),
    );
    final stamped = scheduled.copyWith(accountId: session.account.id);
    session.scheduledSends = [...session.scheduledSends, stamped]
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
    notifyListeners();
    return stamped;
  }

  _Session _sessionOwningScheduled(String id) {
    for (final session in _sessions.values) {
      if (session.scheduledSends.any((item) => item.id == id)) {
        return session;
      }
    }
    return _primarySession;
  }

  @override
  Future<ScheduledSendDetail> getScheduledSend(String id) =>
      _sessionOwningScheduled(id).mailService.getScheduledSend(id);

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
  }) async {
    final session = _sessionOwningScheduled(id);
    await session.mailService.updateScheduledSend(
      id: id,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      sendAtUtc: sendAt,
      keepAttachmentIds: keepAttachmentIds,
      attachments: attachments,
    );
    await refreshScheduledSends();
  }

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
  }) async {
    final session = _sessionOwningScheduled(id);
    await session.mailService.rescheduleFailedSend(
      id: id,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      attachmentIds: attachmentIds,
      sendAtUtc: sendAt,
      idempotencyKey: _newIdempotencyKey(),
    );
    await refreshScheduledSends();
  }

  @override
  Future<void> cancelScheduledSend(String id) async {
    final session = _sessions.values.firstWhere(
      (s) => s.scheduledSends.any((sch) => sch.id == id),
      orElse: () => _primarySession,
    );
    await session.mailService.cancelScheduledSend(id);
    session.scheduledSends = session.scheduledSends
        .where((s) => s.id != id)
        .toList();
    notifyListeners();
  }

  @override
  List<ScheduledSend> getScheduledSends() {
    final result = [for (final s in _scopedSessions) ...s.scheduledSends]
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
    return List.unmodifiable(result);
  }

  @override
  Future<ReplyReminder> setReplyReminder(
    String mailId,
    DateTime dueAtUtc,
  ) async {
    final session =
        _sessionOwning(mailId) ?? _sessions.values.firstOrNull;
    if (session == null) throw StateError('No mail session');
    final created = (await session.mailService.setReplyReminder(
      mailId,
      dueAtUtc,
    )).copyWith(accountId: session.account.id);
    final items = [
      for (final item in session.replyReminders)
        if (item.mailId != mailId) item,
      created,
    ]..sort((a, b) => a.dueAtUtc.compareTo(b.dueAtUtc));
    session.replyReminders = items;
    notifyListeners();
    return created;
  }

  @override
  Future<void> cancelReplyReminder(String mailId) async {
    final session =
        _sessionOwning(mailId) ?? _sessions.values.firstOrNull;
    if (session == null) return;
    await session.mailService.cancelReplyReminder(mailId);
    session.replyReminders = [
      for (final item in session.replyReminders)
        if (item.mailId != mailId) item,
    ];
    notifyListeners();
  }

  @override
  List<ReplyReminder> getReplyReminders() {
    final result = [for (final s in _scopedSessions) ...s.replyReminders]
      ..sort((a, b) => a.dueAtUtc.compareTo(b.dueAtUtc));
    return List.unmodifiable(result);
  }

  @override
  Future<void> refreshReplyReminders() async {
    await Future.wait(
      _scopedSessions.map((session) async {
        final items = await session.mailService.listReplyReminders();
        session.replyReminders = [
          for (final item in items)
            item.copyWith(accountId: session.account.id),
        ]..sort((a, b) => a.dueAtUtc.compareTo(b.dueAtUtc));
      }),
    );
    notifyListeners();
  }

  @override
  Future<void> refreshScheduledSends() async {
    await Future.wait(
      _scopedSessions.map((session) async {
        final items = await session.mailService.listScheduledSends();
        session.scheduledSends = [
          for (final s in items) s.copyWith(accountId: session.account.id),
        ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));
      }),
    );
    notifyListeners();
  }

  @override
  Future<List<MailSignature>> listSignatures(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _sessionForAccountId(accountId);
    if (!refresh && session.signatures != null) return session.signatures!;
    final result = await session.mailService.getSignatures();
    session.signatures = [
      for (final signature in result.items)
        signature.copyWith(accountId: accountId),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    session.signatureDefaults = result.defaults;
    return session.signatures!;
  }

  @override
  Future<SignatureDefaults> getSignatureDefaults(String accountId) async {
    final session = _sessionForAccountId(accountId);
    if (session.signatureDefaults != null) return session.signatureDefaults!;
    await listSignatures(accountId, refresh: true);
    return session.signatureDefaults ?? const SignatureDefaults();
  }

  @override
  Future<MailSignature> createSignature(
    String accountId,
    MailSignature signature,
  ) async {
    final session = _sessionForAccountId(accountId);
    final created = (await session.mailService.createSignature(
      signature,
    )).copyWith(accountId: accountId);
    final items = session.signatures ?? <MailSignature>[];
    session.signatures = [...items, created]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return created;
  }

  @override
  Future<MailSignature> updateSignature(
    String accountId,
    MailSignature signature,
  ) async {
    final session = _sessionForAccountId(accountId);
    final updated = (await session.mailService.updateSignatureItem(
      signature,
    )).copyWith(accountId: accountId);
    if (session.signatures != null) {
      session.signatures = [
        for (final item in session.signatures!)
          if (item.id == updated.id) updated else item,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    notifyListeners();
    return updated;
  }

  @override
  Future<void> deleteSignature(String accountId, String signatureId) async {
    final session = _sessionForAccountId(accountId);
    await session.mailService.deleteSignature(signatureId);
    session.signatures?.removeWhere((item) => item.id == signatureId);
    notifyListeners();
  }

  @override
  Future<SignatureDefaults> updateSignatureDefaults(
    String accountId,
    SignatureDefaults defaults,
  ) async {
    final session = _sessionForAccountId(accountId);
    final updated = await session.mailService.updateSignatureDefaults(
      defaults,
    );
    session.signatureDefaults = updated;
    notifyListeners();
    return updated;
  }

  @override
  Future<List<MailIdentity>> listIdentities(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _sessionForAccountId(accountId);
    if (!refresh && session.identities != null) return session.identities!;
    final identities = await session.mailService.getIdentities();
    session.identities = [
      for (final identity in identities)
        identity.copyWith(accountId: accountId),
    ]..sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.emailAddress.toLowerCase().compareTo(
        b.emailAddress.toLowerCase(),
      );
    });
    return session.identities!;
  }

  @override
  Future<MailIdentity> createIdentity(
    String accountId,
    MailIdentity identity,
  ) async {
    final session = _sessionForAccountId(accountId);
    var created = (await session.mailService.createIdentity(
      identity,
    )).copyWith(accountId: accountId);
    if (created.isDefault) {
      await listIdentities(accountId, refresh: true);
      created =
          session.identities!.firstWhere((item) => item.id == created.id);
    } else {
      final items = session.identities ?? <MailIdentity>[];
      session.identities = [...items, created];
    }
    notifyListeners();
    return created;
  }

  @override
  Future<MailIdentity> updateIdentity(
    String accountId,
    MailIdentity identity,
  ) async {
    final session = _sessionForAccountId(accountId);
    var updated = (await session.mailService.updateIdentity(
      identity,
    )).copyWith(accountId: accountId);
    if (updated.isDefault) {
      await listIdentities(accountId, refresh: true);
      updated = session.identities!.firstWhere((item) => item.id == updated.id);
    } else if (session.identities != null) {
      session.identities = [
        for (final item in session.identities!)
          if (item.id == updated.id) updated else item,
      ];
    }
    notifyListeners();
    return updated;
  }

  @override
  Future<void> deleteIdentity(String accountId, String identityId) async {
    final session = _sessionForAccountId(accountId);
    await session.mailService.deleteIdentity(identityId);
    session.identities?.removeWhere((item) => item.id == identityId);
    notifyListeners();
  }

  @override
  Future<void> setSignature(String accountId, String? signature) async {
    final session = _sessionForAccountId(accountId);
    final trimmed = signature?.trim();
    final normalized = trimmed == null || trimmed.isEmpty ? null : trimmed;
    await session.mailService.updateSignature(normalized);
    session.account = session.account.copyWith(signature: normalized);
    notifyListeners();
  }

  // --- Custom folders -------------------------------------------------

  _Session _sessionForAccountId(String accountId) {
    final session = _sessions[accountId];
    if (session == null) {
      throw ArgumentError('Unknown account for custom folders: $accountId');
    }
    return session;
  }

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
            delimiter: f.delimiter,
            unreadCount: f.unreadCount,
            totalCount: f.totalCount,
          ),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return result;
  }

  @override
  Future<void> refreshCustomFolders({String? accountId}) async {
    final sessions = accountId == null
        ? _scopedSessions
        : [_sessionForAccountId(accountId)];
    await Future.wait(sessions.map(_loadCustomFolders));
    notifyListeners();
  }

  Future<void> _loadCustomFolders(_Session session) async {
    var folders = await session.mailService.getFolders();
    if (!session.folderHierarchyRequested &&
        folders.any((f) => f.isAvailable && f.delimiter == null)) {
      session.folderHierarchyRequested = true;
      await session.mailService.refreshFolders();
      folders = await session.mailService.getFolders();
    }
    session.customFolders = folders
        .where((f) => f.type == 'Custom' && f.isAvailable)
        .toList();
  }

  Future<void> _reloadCustomFoldersAfterChange(_Session session) async {
    try {
      await _loadCustomFolders(session);
    } catch (_) {
    } finally {
      notifyListeners();
    }
  }

  void _putCustomFolder(_Session session, ApiMailFolder folder) {
    session.customFolders = [
      for (final f in session.customFolders)
        if (f.id != folder.id) f,
      if (folder.type == 'Custom' && folder.isAvailable) folder,
    ];
  }

  void _forgetCustomFolderMails(_Session session, String folderId) {
    session.customFolderEmails.remove(folderId);
    session.customFolderPages.remove(folderId);
    session.customFolderHasMore.remove(folderId);
  }

  void _dropFromCustomFolderMails(_Session session, Set<String> ids) {
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
  }) => _fetchCustomFolderPage(
    session: _sessionForAccountId(accountId),
    folderId: folderId,
    page: 1,
  );

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
    required _Session session,
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

  /// Old draft id -> the id `PUT /drafts/{id}` replaced it with.
  final Map<String, String> _draftIdSuccessor = {};

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
  }) => _serializeDraftWrite(
    () => _writeDraft(
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
      draftId: draftId == null ? null : _latestDraftId(draftId),
    ),
  );

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
        senderName: session.account.displayName ?? previous?.senderName ?? '',
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
        if (oldIndex >= 0) drafts.removeAt(oldIndex);
        _touch();
        notifyListeners();
        unawaited(
          Future<void>.delayed(
            const Duration(seconds: 3),
            () => _refreshEmailsFor(session, MailFolder.drafts),
          ).catchError((_) {}),
        );
        return updated;
      }
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
      bodyHtml: bodyHtml,
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
  Future<void> deleteDraft(String draftId) => _serializeDraftWrite(() async {
    final id = _latestDraftId(draftId);
    final session = _sessionOwning(id) ?? _primarySession;
    await session.mailService.deleteDraft(id);
    session.emails[MailFolder.drafts]?.removeWhere((e) => e.id == id);
    notifyListeners();
  });

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
      final folderId = folder == null ? null : session.folderIds[folder];
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
      final folderId = folder == null ? null : session.folderIds[folder];
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
  Future<List<ServerMailRule>> listRules(String accountId) async {
    final session = _sessionForAccountId(accountId);
    final legacyRules = await MailRulesStore.readRules(accountId);
    if (legacyRules.isNotEmpty) {
      final existing = await session.mailService.getRules();
      final firstPriority = existing.isEmpty
          ? 0
          : existing.map((rule) => rule.priority).reduce(max) + 1;
      for (var index = 0; index < legacyRules.length; index++) {
        final legacy = legacyRules[index];
        final RuleAction action;
        if (legacy.action.type == MailRuleActionType.addLabel) {
          final labelId = legacy.action.labelId!;
          if (!session.labels.any((label) => label.id == labelId)) {
            throw StateError(
              'Eski kuralın etiketi bulunamadı. Kural cihazda korundu.',
            );
          }
          action = RuleAction('addLabel', labelId: labelId);
        } else {
          action = RuleAction(switch (legacy.action.folder!) {
            MailFolder.trash => 'trash',
            MailFolder.spam => 'spam',
            _ => 'archive',
          });
        }
        final name = 'Gönderen: ${legacy.condition.value.trim()}';
        final draft = ServerMailRule(
          id: '',
          name: name.length > 100 ? name.substring(0, 100) : name,
          enabled: true,
          priority: firstPriority + index,
          logic: 'And',
          conditions: [RuleCondition('senderContains', legacy.condition.value)],
          actions: [action],
        );
        await session.mailService.createRule(draft, legacyId: legacy.id);
        await MailRulesStore.deleteRule(accountId, legacy.id);
      }
    }
    return session.mailService.getRules();
  }

  @override
  Future<ServerMailRule> createRule(String accountId, ServerMailRule rule) =>
      _sessionForAccountId(accountId).mailService.createRule(rule);

  @override
  Future<ServerMailRule> updateRule(String accountId, ServerMailRule rule) =>
      _sessionForAccountId(accountId).mailService.updateRule(rule);

  @override
  Future<void> deleteRule(String accountId, String ruleId) =>
      _sessionForAccountId(accountId).mailService.deleteRule(ruleId);

  @override
  Future<List<MailTemplate>> listTemplates(
    String accountId, {
    bool refresh = false,
  }) async {
    final session = _sessionForAccountId(accountId);
    if (!refresh && session.templates != null) return session.templates!;
    final templates = await session.mailService.getTemplates();
    session.templates = [
      for (final template in templates)
        template.copyWith(accountId: accountId),
    ];
    return session.templates!;
  }

  @override
  Future<MailTemplate> createTemplate(
    String accountId,
    MailTemplate template,
  ) async {
    final session = _sessionForAccountId(accountId);
    final created = (await session.mailService.createTemplate(
      template,
    )).copyWith(accountId: accountId);
    final items = session.templates ?? <MailTemplate>[];
    session.templates = [...items, created]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return created;
  }

  @override
  Future<MailTemplate> updateTemplate(
    String accountId,
    MailTemplate template,
  ) async {
    final session = _sessionForAccountId(accountId);
    final updated = (await session.mailService.updateTemplate(
      template,
    )).copyWith(accountId: accountId);
    if (session.templates != null) {
      session.templates = [
        for (final item in session.templates!)
          if (item.id == updated.id) updated else item,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return updated;
  }

  @override
  Future<void> deleteTemplate(String accountId, String templateId) async {
    final session = _sessionForAccountId(accountId);
    await session.mailService.deleteTemplate(templateId);
    session.templates?.removeWhere((item) => item.id == templateId);
  }

  @override
  Future<List<MailSnippet>> listSnippets(
    String accountId, {
    bool refresh = false,
  }) => _sessionForAccountId(accountId).mailService.getSnippets();

  @override
  Future<MailSnippet> createSnippet(String accountId, MailSnippet snippet) =>
      _sessionForAccountId(accountId).mailService.createSnippet(snippet);

  @override
  Future<MailSnippet> updateSnippet(String accountId, MailSnippet snippet) =>
      _sessionForAccountId(accountId).mailService.updateSnippet(snippet);

  @override
  Future<void> deleteSnippet(String accountId, String snippetId) =>
      _sessionForAccountId(accountId).mailService.deleteSnippet(snippetId);

  @override
  Future<List<FolderSyncStatus>> getSyncStatus(String accountId) async {
    final session = _sessions[accountId];
    if (session == null) return const [];
    return session.mailService.getSyncStatus();
  }

  @override
  Future<AccountSyncScope> getSyncScope(String accountId) async {
    final service = _sessionForAccountId(accountId).mailService;
    final (scope, folders) = await (
      service.getSyncScope(),
      service.getFolders(),
    ).wait;
    return _composeSyncScope(scope, folders);
  }

  @override
  Future<AccountSyncScope> updateSyncScope(
    String accountId,
    FolderSyncScope scope, {
    List<String>? folderIds,
  }) async {
    final service = _sessionForAccountId(accountId).mailService;
    final updated = await service.updateSyncScope(
      scope.backendValue,
      folderIds: scope == FolderSyncScope.selectedFolders ? folderIds : null,
    );
    return _composeSyncScope(updated, await service.getFolders());
  }

  @override
  Future<AccountNotificationSettings> getNotificationSettings(
    String accountId,
  ) => _sessionForAccountId(accountId).mailService.getNotificationSettings();

  @override
  Future<AccountNotificationSettings> updateNotificationSettings(
    String accountId,
    AccountNotificationSettings settings,
  ) =>
      _sessionForAccountId(accountId).mailService
          .updateNotificationSettings(settings);

  static const _syncScopeFolderOrder = [
    'Inbox',
    'Sent',
    'Drafts',
    'Archive',
    'Junk',
    'Trash',
  ];

  AccountSyncScope _composeSyncScope(
    ({String scope, Set<String> syncedFolderIds}) scope,
    List<ApiMailFolder> folders,
  ) {
    int rank(ApiMailFolder f) {
      final index = _syncScopeFolderOrder.indexOf(f.type);
      return index < 0 ? _syncScopeFolderOrder.length : index;
    }

    final available = folders.where((f) => f.isAvailable).toList()
      ..sort((a, b) {
        final byType = rank(a).compareTo(rank(b));
        return byType != 0 ? byType : a.fullName.compareTo(b.fullName);
      });
    return AccountSyncScope(
      scope: FolderSyncScope.fromBackend(scope.scope),
      folders: [
        for (final f in available)
          SyncScopeFolder(
            id: f.id,
            name: f.fullName,
            type: f.type,
            synced: scope.syncedFolderIds.contains(f.id),
          ),
      ],
    );
  }

  @override
  Future<int> queuedOfflineMutationCount(String accountId) async {
    final store = _sessions[accountId]?.flagsStore;
    if (store == null) return 0;
    return (await store.readQueuedMutations()).length;
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
        (e) => _bulkAndApplyOrQueue(
          e.key,
          'trash',
          e.value,
          (succeeded) => _moveMany(e.key, succeeded, MailFolder.trash),
        ),
      ),
    );
  }

  /// Bulk `delete` (IMAP expunge) per owning account. Only ids the server
  /// confirmed leave the cache; any per-item failure is surfaced afterwards
  /// so the UI never claims a mail is gone when it isn't.
  @override
  Future<void> deletePermanently(List<String> ids) async {
    final failures = <String>[];
    for (final entry in _groupBySession(ids).entries) {
      final session = entry.key;
      final results = await session.mailService.bulkAction(
        'delete',
        entry.value,
      );
      _removeMany(session, [
        for (final r in results)
          if (r.success) r.mailId,
      ]);
      failures.addAll([
        for (final r in results)
          if (!r.success) r.code ?? 'mail_operation_failed',
      ]);
      notifyListeners();
      unawaited(_refreshCountsFor(session));
    }
    if (failures.isNotEmpty) {
      throw ApiException(status: 0, code: failures.first);
    }
  }

  /// Drops every cached mail in [ids] from whichever bucket holds it.
  void _removeMany(_Session session, Iterable<String> ids) {
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
        List<BulkActionResult>? results;
        try {
          results = await session.mailService.bulkAction('restore', restoring);
        } catch (_) {
          session.offline = true;
          _scheduleReconnectRetry(session);
          final store = session.flagsStore;
          if (store != null) {
            for (final id in restoring) {
              await store.queueMutation(id, 'restore');
            }
          }
          _moveMany(session, restoring, MailFolder.inbox);
          notifyListeners();
        }
        if (results != null) {
          final restored = [
            for (final r in results)
              if (r.success) r.mailId,
          ];
          final store = session.flagsStore;
          if (store != null) {
            for (final id in restored) {
              await store.clearQueuedMutation(id, 'location');
            }
          }
          await _fileRestored(session, restored);
        }
      }

      final rest = idsForSession
          .where((id) => !restoring.contains(id))
          .toList();
      if (rest.isNotEmpty) {
        await _bulkAndApplyOrQueue(
          session,
          folder == MailFolder.archive ? 'archive' : 'move',
          rest,
          (succeeded) => _moveMany(session, succeeded, folder),
          folderId: folder == MailFolder.archive ? null : folderId,
        );
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
  Future<void> _fileRestored(_Session session, List<String> ids) async {
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
    _removeMany(session, ids);
    for (final detail in details) {
      if (detail == null) continue;
      session.emails
          .putIfAbsent(detail.folder, () => <Email>[])
          .insert(0, session.stampLocalFlags(detail));
    }
    notifyListeners();
  }

  @override
  Future<void> markAsRead(List<String> ids) async {
    await Future.wait(
      _groupBySession(ids).entries.map(
        (e) => _bulkAndApplyOrQueue(
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
        (e) => _bulkAndApplyOrQueue(
          e.key,
          'unread',
          e.value,
          (succeeded) =>
              _replaceMany(e.key, succeeded, (m) => m.copyWith(isRead: false)),
        ),
      ),
    );
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

  /// Writes through to the backend first (it enforces the
  /// [MailRepository.maxPinnedMails]-per-account cap authoritatively); only
  /// mails the server actually confirmed are applied locally, so a partial
  /// failure (e.g. cap already full on another device) never desyncs the
  /// ones that did succeed. A network failure applies the change locally and
  /// queues it for [_replayQueuedMutations] instead, which reconciles with
  /// the server's answer once the account reconnects.
  @override
  Future<void> setPinned(List<String> ids, bool pinned) async {
    if (ids.isEmpty) return;
    await Future.wait(
      _groupBySession(ids).entries.map((entry) async {
        final session = entry.key;
        final store = session.flagsStore;
        Set<String> succeeded;
        try {
          final results = await session.mailService.setPinned(
            entry.value,
            pinned,
          );
          succeeded = results
              .where((r) => r.success)
              .map((r) => r.mailId)
              .toSet();
          for (final id in succeeded) {
            await store?.clearQueuedMutation(id, 'pin_state');
          }
        } catch (error) {
          if (!_isOfflineFailure(error)) rethrow;
          _markOffline(session);
          for (final id in entry.value) {
            await store?.queueMutation(id, pinned ? 'pin' : 'unpin');
          }
          succeeded = entry.value.toSet();
        }
        if (succeeded.isEmpty) return;
        pinned
            ? session.pinnedIds.addAll(succeeded)
            : session.pinnedIds.removeAll(succeeded);
        await session.flagsStore?.writePinned(session.pinnedIds);
        _replaceMany(
          session,
          succeeded,
          (e) => e.copyWith(isPinned: session.pinnedIds.contains(e.id)),
        );
      }),
    );
    notifyListeners();
  }

  @override
  Future<void> setStarred(List<String> ids, bool starred) async {
    await Future.wait(
      _groupBySession(ids).entries.map((e) {
        final session = e.key;
        return _bulkAndApplyOrQueue(
          session,
          starred ? 'star' : 'unstar',
          e.value,
          (succeeded) {
            starred
                ? session.starredIds.addAll(succeeded)
                : session.starredIds.removeAll(succeeded);
            _replaceMany(
              session,
              succeeded,
              (m) => m.copyWith(isStarred: starred),
            );
          },
        );
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
      session.repliedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.repliedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeRepliedFromKaydetMail(session.repliedFromKaydetMailIds),
        store.writeRepliedFromKaydetMailThreads(session.repliedFromKaydetMailThreadIds),
      ]);
      _restampFlags(session);
    }
    notifyListeners();
  }

  /// Unlike pin/star, snoozing changes which folder view a mail is even
  /// visible in (see [_buildFolderView]), so a write always touches the
  /// view cache. Writes each id through to the backend individually (there
  /// is no bulk snooze endpoint); only ids the server actually confirmed
  /// are applied locally — same silent-partial-success shape as
  /// [setPinned], including its offline queue.
  @override
  Future<void> setSnoozed(List<String> ids, DateTime? until) async {
    if (ids.isEmpty) return;
    await Future.wait(
      _groupBySession(ids).entries.map((entry) async {
        final session = entry.key;
        final succeeded = <String>[];
        final store = session.flagsStore;
        await Future.wait(
          entry.value.map((id) async {
            try {
              if (until == null) {
                await session.mailService.clearSnooze(id);
              } else {
                await session.mailService.setSnooze(id, until);
              }
              await store?.clearQueuedMutation(id, 'snooze_state');
              succeeded.add(id);
            } catch (error) {
              if (!_isOfflineFailure(error)) return;
              _markOffline(session);
              await store?.queueMutation(
                id,
                until == null ? 'unsnooze' : 'snooze',
                folderId: until?.toUtc().toIso8601String(),
              );
              succeeded.add(id);
            }
          }),
        );
        if (succeeded.isEmpty) return;
        if (until == null) {
          session.snoozedUntil.removeWhere((id, _) => succeeded.contains(id));
        } else {
          final ms = until.toUtc().millisecondsSinceEpoch;
          for (final id in succeeded) {
            session.snoozedUntil[id] = ms;
          }
        }
        await session.flagsStore?.writeSnoozed(session.snoozedUntil);
      }),
    );
    _recomputeWatchedSnoozeDeadline();
    _touch();
    notifyListeners();
  }

  @override
  DateTime? snoozedUntilOf(String mailId) {
    for (final session in _scopedSessions) {
      final until = _snoozedUntil(session, mailId);
      if (until != null) return until;
    }
    return null;
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
      session.forwardedFromKaydetMailIds.addAll(entry.value);
      for (final id in entry.value) {
        final threadId = session.findLoaded(id)?.threadId;
        if (threadId != null && threadId.isNotEmpty) {
          session.forwardedFromKaydetMailThreadIds.add(threadId);
        }
      }
      await Future.wait([
        store.writeForwardedFromKaydetMail(session.forwardedFromKaydetMailIds),
        store.writeForwardedFromKaydetMailThreads(session.forwardedFromKaydetMailThreadIds),
      ]);
      _restampFlags(session);
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

  /// Mirrors backend-confirmed label state into the local cache so labels
  /// still show while offline. Never the source of truth — see [_loadLabels].
  Future<void> _persistLabels(_Session session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeLabelDefs([
      for (final l in session.labels)
        {'id': l.id, 'name': l.name, 'color': l.color.toARGB32()},
    ]);
    await store.writeLabelMap(session.labelMap);
  }

  Future<void> _queueLabels(
    _Session session,
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
    _Session session,
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
    final trimmed = name.trim();
    Map<String, dynamic> created;
    try {
      created = await session.mailService.createLabel(
        trimmed,
        color.toARGB32(),
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
      color: Color(created['color'] as int),
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
      await session.mailService.updateLabel(id, trimmed, color.toARGB32());
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
  ) async {
    for (final entry in _groupBySession(emailIds).entries) {
      final session = entry.key;
      final ownedLabelIds = {
        for (final label in session.labels)
          if (labelIds.contains(label.id)) label.id,
      };
      if (ownedLabelIds.isEmpty) continue;
      try {
        await session.mailService.assignLabels(
          entry.value,
          ownedLabelIds.toList(),
        );
        await _clearQueuedLabels(session, entry.value, ownedLabelIds);
      } catch (error) {
        if (!_isOfflineFailure(error)) continue;
        await _queueLabels(session, entry.value, ownedLabelIds, 'label_add');
      }
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
      try {
        await session.mailService.unassignLabels(entry.value, labelIds);
        await _clearQueuedLabels(session, entry.value, labelIds);
      } catch (error) {
        if (!_isOfflineFailure(error)) continue;
        await _queueLabels(session, entry.value, labelIds, 'label_remove');
      }
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

  void _assertContactEmailIsValid(
    _Session session,
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

  Future<void> _persistManualContacts(_Session session) async {
    final store = session.flagsStore;
    if (store == null) return;
    await store.writeContacts([
      for (final c in session.manualContacts)
        {'id': c.id, 'email': c.email, 'displayName': c.displayName},
    ]);
  }

  /// The session that owns manual contact [id], if any.
  _Session? _sessionForManualContact(String id) {
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
  }) async {
    final session = _primarySession;
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
        'id': '$_localContactIdPrefix${_newIdempotencyKey()}',
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
    _Session session,
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
