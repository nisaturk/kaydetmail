import 'dart:math';

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
  LocalMailFlagsStore? _flagsStore;
  Set<String> _pinnedIds = {};
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

  Never _notImplemented() =>
      throw UnimplementedError('This mail endpoint is not implemented yet.');

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
    await _authService.logout();
    _account = null;
    _loggedIn = false;
    _flagsStore = null;
    _pinnedIds = {};
    _repliedIds = {};
    _forwardedIds = {};
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
      final flags = LocalMailFlagsStore(account.id);
      _pinnedIds = await flags.readPinned();
      _repliedIds = await flags.readReplied();
      _forwardedIds = await flags.readForwarded();
      _flagsStore = flags;
      await _loadMailbox();
    } catch (_) {
      _account = null;
      _loggedIn = false;
      _flagsStore = null;
      _pinnedIds = {};
      _repliedIds = {};
      _forwardedIds = {};
      rethrow;
    }
  }

  /// Overlays the locally-persisted pin/reply/forward flags onto a mail
  /// freshly mapped from the API — the server has no concept of any of the
  /// three, so every fetch would otherwise reset them.
  Email _stampLocalFlags(Email email) => email.copyWith(
    isPinned: _pinnedIds.contains(email.id),
    isReplied: _repliedIds.contains(email.id),
    isForwarded: _forwardedIds.contains(email.id),
  );

  @override
  Future<void> removeAccount(String accountId) async {
    if (_account?.id != accountId) return;
    await _mailService.deleteAccount();
    await _authService.tokenStore.clear();
    _account = null;
    _loggedIn = false;
    _flagsStore = null;
    _pinnedIds = {};
    _repliedIds = {};
    _forwardedIds = {};
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
  }

  static bool _highlighted(Email e) => e.isPinned || e.isStarred;

  /// [MailFolder.pinned] is virtual — "Yıldızlılar" surfaces every pinned or
  /// starred mail regardless of its real folder — so it's built by scanning
  /// every cached bucket rather than a fetched one. Every folder additionally
  /// floats highlighted mails above the rest, newest-first within each
  /// group, matching [MailRepository.getEmailsInFolder]'s documented order.
  @override
  List<Email> getEmailsInFolder(MailFolder folder) {
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
    final fresh = result.items
        .where((email) => known.add(email.id))
        .map(_stampLocalFlags)
        .toList();
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

  /// Stores a full detail object in the in-memory cache without notifying:
  /// replaces the cached copy in whichever bucket holds it, or files it
  /// under its own folder when unknown. Never creates duplicates, so a
  /// detail fetch never corrupts the folder lists.
  void _upsertDetail(Email email) {
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

  /// Loads the full server conversation: conversation → message ids →
  /// one detail fetch per message. Each message is fetched independently —
  /// one unreadable message is skipped while the rest still load. The
  /// result is deduplicated and sorted oldest → newest. A conversation-level
  /// failure propagates so the caller can keep its already-loaded mail.
  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async {
    if (threadId.isEmpty) return const [];
    final conversation = await _mailService.getConversation(threadId);
    final results = await Future.wait(
      conversation.messageIds.map((id) async {
        try {
          return await _mailService.getMail(id, resolveFolder: _resolveFolder);
        } catch (_) {
          return null;
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
    final id = 'sent-${DateTime.now().microsecondsSinceEpoch}';
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
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
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
