import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/account_notification_settings.dart';
import '../models/compose_prefill.dart';
import '../models/email.dart';
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_session.dart';
import '../models/remote_search_result.dart';
import '../models/server_mail_rule.dart';
import '../models/scheduled_send.dart';
import '../utils/html_to_text.dart';
import 'api_auth_service.dart';
import 'api_client.dart';
import 'api_exception.dart';

class ApiMailService {
  ApiMailService(
    this._client, {
    this.syncPollInterval = const Duration(seconds: 1),
    this.syncTimeout = const Duration(minutes: 2),
  });

  final ApiClient _client;
  final Duration syncPollInterval;
  final Duration syncTimeout;

  Future<MailAccount> getAccount() async {
    final body = await _client.get('/api/account');
    return _mapAccount(body);
  }

  MailAccount _mapAccount(Map<String, dynamic> body) => MailAccount(
    id: body['id'] as String,
    email: body['emailAddress'] as String,
    displayName: body['displayName'] as String?,
    provider: AccountProvider.fromBackend(body['provider'] as String),
    status: MailAccountStatus.fromBackend(body['status'] as String?),
    signature: body['signature'] as String?,
  );

  /// Sets or clears (blank/null) the signature appended to outgoing mail
  /// from this account — synced, so every device signed into it sees it.
  Future<void> updateSignature(String? signature) =>
      _client.putJson('/api/account/signature', {'signature': signature});

  /// Re-authenticates the signed-in account after its stored credentials
  /// stopped working (`mail_account_needs_reauthentication`). `imap`/`smtp`
  /// are optional — omitted servers keep their current settings, only the
  /// credentials are replaced. Answers with the same `AccountResponse` shape
  /// as [getAccount]. Reconnect is Bearer-authenticated; a brand-new device
  /// without a token uses `POST /api/accounts/login` instead — never this.
  Future<MailAccount> reconnect({
    required String password,
    ManualMailServer? imap,
    ManualMailServer? smtp,
  }) async {
    final body = await _client.postJson('/api/account/reconnect', {
      'authentication': {'type': 'Password', 'password': password},
      if (imap != null) 'imap': imap.toJson(),
      if (smtp != null) 'smtp': smtp.toJson(),
    });
    return _mapAccount(body);
  }

  /// Permanently deletes the connected account and all its cached mail.
  Future<void> deleteAccount() => _client.delete('/api/account');

  Future<List<MailSession>> getSessions() async {
    final items = await _client.getList('/api/account/sessions');
    return items
        .map(
          (item) => MailSession(
            id: item['id'] as String,
            deviceIdentifier: (item['deviceIdentifier'] as String?) ?? '—',
            createdAt: _date(item['createdAt']),
            lastUsedAt: _date(item['lastUsedAt'] ?? item['createdAt']),
            expiresAt: _date(item['expiresAt']),
          ),
        )
        .toList();
  }

  static DateTime _date(Object? v) =>
      _optionalDate(v) ?? DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> deleteSession(String sessionId) =>
      _client.delete('/api/account/sessions/${Uri.encodeComponent(sessionId)}');

  Future<List<FolderSyncStatus>> getSyncStatus() async {
    final items = await _client.getList('/api/account/sync-status');
    return items
        .map(
          (item) => FolderSyncStatus(
            folderId: item['folderId'] as String,
            folderName: item['folderName'] as String,
            folderType: item['folderType'] as String,
            backfillComplete: item['backfillComplete'] as bool,
            lastSuccessfulSyncAt: _optionalDate(item['lastSuccessfulSyncAt']),
            lastFailureAt: _optionalDate(item['lastFailureAt']),
            lastFailureCategory: item['lastFailureCategory'] as String?,
            consecutiveFailures: item['consecutiveFailures'] as int,
          ),
        )
        .toList();
  }

  Future<({String scope, Set<String> syncedFolderIds})> getSyncScope() async =>
      _mapSyncScope(await _client.get('/api/account/sync-scope'));

  Future<({String scope, Set<String> syncedFolderIds})> updateSyncScope(
    String scope, {
    List<String>? folderIds,
  }) async => _mapSyncScope(
    await _client.putJson('/api/account/sync-scope', {
      'scope': scope,
      'folderIds': ?folderIds,
    }),
  );

  static ({String scope, Set<String> syncedFolderIds}) _mapSyncScope(
    Map<String, dynamic> body,
  ) => (
    scope: body['scope'] as String,
    syncedFolderIds: (body['syncedFolderIds'] as List<dynamic>)
        .cast<String>()
        .toSet(),
  );

  Future<AccountNotificationSettings> getNotificationSettings() async =>
      AccountNotificationSettings.fromJson(
        await _client.get('/api/account/notification-settings'),
      );

  Future<AccountNotificationSettings> updateNotificationSettings(
    AccountNotificationSettings settings,
  ) async => AccountNotificationSettings.fromJson(
    await _client.putJson(
      '/api/account/notification-settings',
      settings.toJson(),
    ),
  );

  Future<List<ApiMailFolder>> getFolders() async {
    final items = await _client.getList('/api/folders');
    return items
        .map((item) => ApiMailFolder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ApiMailFolder> createFolder(String name, {String? parentId}) async =>
      ApiMailFolder.fromJson(
        await _client.postJson('/api/folders', {
          'name': name,
          'parentId': parentId,
        }),
      );

  Future<ApiMailFolder> renameFolder(String id, String name) async =>
      ApiMailFolder.fromJson(
        await _client.patchJson('/api/folders/${Uri.encodeComponent(id)}', {
          'name': name,
        }),
      );

  Future<void> deleteFolder(String id) =>
      _client.delete('/api/folders/${Uri.encodeComponent(id)}');

  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
    bool? isRead,
    bool? hasAttachments,
    String? search,
  }) async {
    final path = _buildQuery('/api/mails', {
      'folderId': folderId,
      'page': '$page',
      'pageSize': '$pageSize',
      'isRead': isRead?.toString(),
      'hasAttachments': hasAttachments?.toString(),
      'search': search,
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return MailListPage(
      items: items
          .map((item) => _mapMail(item as Map<String, dynamic>, resolveFolder))
          .toList(),
      page: body['page'] as int,
      pageSize: body['pageSize'] as int,
      total: body['total'] as int,
    );
  }

  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
  }) async {
    final body = await _client.get('/api/mails/${Uri.encodeComponent(id)}');
    return _mapMailDetail(body, resolveFolder);
  }

  /// Downloads one attachment's raw bytes
  /// (`GET /api/mails/{mailId}/attachments/{attachmentId}` — not JSON, hence
  /// the byte-streaming client call). 404 means the attachment is gone or
  /// belongs to another mail/account.
  Future<Uint8List> downloadAttachment(
    String mailId,
    String attachmentId,
  ) => _client.getBytes(
    '/api/mails/${Uri.encodeComponent(mailId)}/attachments/${Uri.encodeComponent(attachmentId)}',
  );

  /// Registers (or upserts — same token twice just updates) this device for
  /// FCM pushes (`POST /api/devices`, `201`). Safe to call on every launch.
  Future<DeviceRegistration> registerDevice({
    required String token,
    required String platform,
    required String appVersion,
    required String locale,
  }) async {
    final body = await _client.postJson('/api/devices', {
      'token': token,
      'platform': platform,
      'appVersion': appVersion,
      'locale': locale,
    });
    return DeviceRegistration(
      id: body['id'] as String,
      platform: body['platform'] as String? ?? platform,
      appVersion: body['appVersion'] as String? ?? appVersion,
      locale: body['locale'] as String? ?? locale,
      registeredAt: _optionalDate(body['registeredAt']),
      lastSeenAt: _optionalDate(body['lastSeenAt']),
    );
  }

  /// Removes this device's push registration (`DELETE /api/devices/{id}`,
  /// `204`) — called on logout and when notifications are disabled.
  Future<void> unregisterDevice(String id) =>
      _client.delete('/api/devices/${Uri.encodeComponent(id)}');

  /// Lists server-side conversations (`GET /api/conversations`) newest-first.
  /// Same `{ items, page, pageSize, total }` envelope as the mail list.
  Future<ConversationListPage> getConversations({
    int page = 1,
    int pageSize = 50,
  }) async {
    final path = _buildQuery('/api/conversations', {
      'page': '$page',
      'pageSize': '$pageSize',
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return ConversationListPage(
      items: items
          .map((item) => _mapConversation(item as Map<String, dynamic>))
          .toList(),
      page: body['page'] as int,
      pageSize: body['pageSize'] as int,
      total: body['total'] as int,
    );
  }

  static ConversationSummary _mapConversation(Map<String, dynamic> item) {
    return ConversationSummary(
      id: item['id'] as String,
      subject: item['subject'] as String? ?? '',
      participants: [
        for (final p in (item['participants'] as List? ?? const []))
          if (p is String && p.isNotEmpty) p,
      ],
      messageCount: (item['messageCount'] as num?)?.toInt() ?? 0,
      unreadCount: (item['unreadCount'] as num?)?.toInt() ?? 0,
      hasAttachments: item['hasAttachments'] as bool? ?? false,
      startedAt: _optionalDate(item['startedAt']),
      lastMessageAt: _optionalDate(item['lastMessageAt']),
    );
  }

  /// Loads a conversation via `GET /api/conversations/{id}`.
  ///
  /// The response carries message *summaries* (`messages[]` with ids, no
  /// bodies), so callers fetch each message via [getMail] for full content.
  /// A codeless 404 means the conversation does not exist (see the error
  /// table) and surfaces as an [ApiException] for the caller to handle.
  Future<ApiConversation> getConversation(String id) async {
    final body = await _client.get(
      '/api/conversations/${Uri.encodeComponent(id)}',
    );
    return _mapConversationDetail(id, body);
  }

  /// One request for the whole thread (`?include=body`): each message already
  /// carries `bodyText`/`body`. Summaries lack recipients and the attachment
  /// list, so [ApiConversation.messages] holds the raw entries and callers
  /// only re-fetch [getMail] for those with attachments.
  Future<ApiConversation> getConversationWithBodies(String id) async {
    final body = await _client.get(
      '/api/conversations/${Uri.encodeComponent(id)}?include=body',
    );
    return _mapConversationDetail(id, body);
  }

  ApiConversation _mapConversationDetail(String id, Map<String, dynamic> body) {
    final raw = body['messages'];
    final messageIds = <String>[];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map<String, dynamic>) {
          final mid = entry['id'] as String?;
          if (mid != null && mid.isNotEmpty && !messageIds.contains(mid)) {
            messageIds.add(mid);
          }
        }
      }
    }
    return ApiConversation(
      id: body['id'] as String? ?? id,
      subject: body['subject'] as String? ?? '',
      messageIds: messageIds,
      messages: [if (raw is List) ...raw.whereType<Map<String, dynamic>>()],
    );
  }

  /// One of the fixed single-mail actions documented for
  /// `POST /api/mails/{id}/{action}` (read, unread, star, unstar, trash,
  /// restore, archive, spam, not-spam, delete). No request/response body.
  Future<void> mailAction(String id, String action) =>
      _client.post('/api/mails/${Uri.encodeComponent(id)}/$action');

  /// Moves a single mail into an arbitrary target folder.
  Future<void> moveMail(String id, String folderId) => _client.postJson(
    '/api/mails/${Uri.encodeComponent(id)}/move',
    {'folderId': folderId},
  );

  /// Copies a single mail into an arbitrary target folder (the original
  /// stays where it is).
  Future<void> copyMail(String id, String folderId) => _client.postJson(
    '/api/mails/${Uri.encodeComponent(id)}/copy',
    {'folderId': folderId},
  );

  /// Re-discovers the server-side folder tree (`202 Accepted` +
  /// `{ folders: N }`). The result applies asynchronously — re-fetch with
  /// [getFolders] afterwards. Returns the reported folder count (`0` when
  /// the 202 carries no body).
  Future<int> refreshFolders() async {
    final body = await _client.postJson('/api/folders/refresh', {});
    return (body['folders'] as num?)?.toInt() ?? 0;
  }

  /// Queues a server sync and waits for its terminal result. A lost/expired
  /// job cannot be mistaken for success; the caller may retry explicitly.
  Future<void> syncFolderId(String folderId) async {
    final accepted = await _client.postWithHeaders(
      '/api/folders/${Uri.encodeComponent(folderId)}/sync',
      const {},
    );
    final jobId = accepted['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const FormatException('Missing folder sync job id');
    }
    final deadline = DateTime.now().add(syncTimeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Folder sync did not finish', syncTimeout);
      }
      final job = await _client.get(
        '/api/folders/sync-jobs/${Uri.encodeComponent(jobId)}',
      );
      if (job['jobId'] != jobId) {
        throw const FormatException('Mismatched folder sync job id');
      }
      switch (job['status']) {
        case 'succeeded':
          return;
        case 'failed':
          final code = job['errorCode'];
          throw ApiException(
            status: 503,
            code: code is String && code.isNotEmpty ? code : 'sync_failed',
          );
        case 'queued':
        case 'running':
          await Future<void>.delayed(syncPollInterval);
        default:
          throw const FormatException('Unexpected folder sync status');
      }
    }
  }

  /// Applies [action] (read, unread, star, unstar, archive, trash, restore,
  /// spam, not-spam, delete, or move) to every id in
  /// [mailIds] in one request. Each mail is processed independently server
  /// side — read the per-item [BulkActionResult.success] rather than
  /// assuming the whole batch succeeded or failed together.
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    final body = await _client.postJson('/api/mails/bulk/$action', {
      'mailIds': mailIds,
      'folderId': folderId,
    });
    final results = body['results'] as List;
    return results
        .map(
          (r) => BulkActionResult(
            mailId: r['mailId'] as String,
            success: r['success'] as bool,
            code: r['code'] as String?,
          ),
        )
        .toList();
  }

  /// Pins or unpins mails; the backend enforces a 3-pinned-mails-per-account
  /// cap independently, so read the per-item [BulkActionResult.success]
  /// (`pinned_limit_reached` on overflow) rather than assuming the whole
  /// batch succeeded.
  Future<List<BulkActionResult>> setPinned(
    List<String> mailIds,
    bool pinned,
  ) async {
    final body = await _client.postJson('/api/mails/pinned', {
      'mailIds': mailIds,
      'pinned': pinned,
    });
    final results = body['results'] as List;
    return results
        .map(
          (r) => BulkActionResult(
            mailId: r['mailId'] as String,
            success: r['success'] as bool,
            code: r['code'] as String?,
          ),
        )
        .toList();
  }

  /// Every pinned mail id for the current mailbox.
  Future<List<String>> getPinnedMailIds() async {
    final body = await _client.get('/api/mails/pinned');
    return (body['mailIds'] as List).cast<String>();
  }

  /// Sets [mailId]'s snooze deadline (UTC). Throws if the mail isn't in
  /// this account.
  Future<void> setSnooze(String mailId, DateTime untilUtc) => _client.putJson(
    '/api/mails/${Uri.encodeComponent(mailId)}/snooze',
    {'untilUtc': untilUtc.toUtc().toIso8601String()},
  );

  /// Clears [mailId]'s snooze; idempotent — clearing an already-unsnoozed
  /// mail also succeeds.
  Future<void> clearSnooze(String mailId) =>
      _client.delete('/api/mails/${Uri.encodeComponent(mailId)}/snooze');

  /// Every currently-snoozed mail id in the current mailbox, mapped to its
  /// UTC deadline.
  Future<Map<String, DateTime>> getSnoozed() async {
    final body = await _client.get('/api/mails/snoozed');
    final snoozed = body['snoozed'] as Map<String, dynamic>;
    return snoozed.map(
      (id, until) => MapEntry(id, DateTime.parse(until as String)),
    );
  }

  /// Every label defined for the current mailbox, in display order.
  Future<List<Map<String, dynamic>>> getLabels() async {
    final body = await _client.get('/api/labels');
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Creates a label. Throws [ApiException] with code `label_name_taken`
  /// when another label in this account already has that name
  /// (case-insensitive).
  Future<Map<String, dynamic>> createLabel(String name, int color) =>
      _client.postJson('/api/labels', {'name': name, 'color': color});

  /// Renames/recolors a label. Same `label_name_taken` conflict as
  /// [createLabel].
  Future<Map<String, dynamic>> updateLabel(String id, String name, int color) =>
      _client.putJson('/api/labels/${Uri.encodeComponent(id)}', {
        'name': name,
        'color': color,
      });

  /// Deletes a label; also strips it from every mail it was assigned to.
  Future<void> deleteLabel(String id) =>
      _client.delete('/api/labels/${Uri.encodeComponent(id)}');

  Future<List<ServerMailRule>> getRules() async {
    final items = await _client.getList('/api/rules');
    return items
        .map((item) => ServerMailRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ServerMailRule> createRule(
    ServerMailRule rule, {
    String? legacyId,
  }) async => ServerMailRule.fromJson(
    await _client.postJson('/api/rules', rule.toJson(legacyId: legacyId)),
  );

  Future<ServerMailRule> updateRule(ServerMailRule rule) async =>
      ServerMailRule.fromJson(
        await _client.putJson(
          '/api/rules/${Uri.encodeComponent(rule.id)}',
          rule.toJson(),
        ),
      );

  Future<void> deleteRule(String id) =>
      _client.delete('/api/rules/${Uri.encodeComponent(id)}');

  /// Full mail id -> assigned label ids map for the current mailbox.
  Future<Map<String, List<String>>> getLabelAssignments() async {
    final body = await _client.get('/api/labels/assignments');
    final assignments = body['assignments'] as Map<String, dynamic>;
    return assignments.map(
      (mailId, labelIds) => MapEntry(mailId, (labelIds as List).cast<String>()),
    );
  }

  /// Assigns [labelIds] to [mailIds]. Pairs outside this account, or
  /// already-assigned pairs, are silently skipped.
  Future<void> assignLabels(List<String> mailIds, List<String> labelIds) =>
      _client.postJson('/api/labels/assignments', {
        'mailIds': mailIds,
        'labelIds': labelIds,
      });

  /// Removes [labelIds] from [mailIds].
  Future<void> unassignLabels(List<String> mailIds, List<String> labelIds) =>
      _client.postJson('/api/labels/assignments/remove', {
        'mailIds': mailIds,
        'labelIds': labelIds,
      });

  /// Every manually-added contact for the current mailbox (see
  /// [ManualContact]).
  Future<List<Map<String, dynamic>>> getContacts() async {
    final body = await _client.get('/api/contacts');
    return (body['items'] as List).cast<Map<String, dynamic>>();
  }

  /// Adds a contact. Throws [ApiException] with code
  /// `contact_already_exists` when this mailbox already has a contact with
  /// that email (case-insensitive).
  Future<Map<String, dynamic>> createContact(
    String email,
    String? displayName,
  ) => _client.postJson('/api/contacts', {
    'email': email,
    'displayName': displayName,
  });

  /// Edits a contact. Same `contact_already_exists` conflict as
  /// [createContact].
  Future<Map<String, dynamic>> updateContact(
    String id,
    String email,
    String? displayName,
  ) => _client.putJson('/api/contacts/${Uri.encodeComponent(id)}', {
    'email': email,
    'displayName': displayName,
  });

  /// Removes a contact.
  Future<void> deleteContact(String id) =>
      _client.delete('/api/contacts/${Uri.encodeComponent(id)}');

  /// Full-text + filtered search over cached server mail. All filters are
  /// optional and AND-ed. Note the singular `hasAttachment` — `/mails` uses
  /// the plural `hasAttachments`.
  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
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
    final path = _buildQuery('/api/search', {
      ..._searchParams(
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
      ),
      'page': '$page',
      'pageSize': '$pageSize',
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return items
        .map((item) => _mapMail(item as Map<String, dynamic>, resolveFolder))
        .toList();
  }

  Future<RemoteSearchResult> searchRemote({
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
    String? labelId,
  }) async {
    final body = await _client.get(
      _buildQuery(
        '/api/search/remote',
        _searchParams(
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
        ),
      ),
    );
    return RemoteSearchResult(
      matched: body['matched'] as int,
      imported: body['imported'] as int,
      remaining: body['remaining'] as int,
      complete: body['complete'] as bool,
    );
  }

  static Map<String, String?> _searchParams({
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
    String? labelId,
  }) => {
    'q': query,
    'folderId': folderId,
    'conversationId': conversationId,
    'from': from,
    'to': to,
    'fromDate': fromDate?.toUtc().toIso8601String(),
    'toDate': toDate?.toUtc().toIso8601String(),
    'isRead': isRead?.toString(),
    'flagged': flagged?.toString(),
    'hasAttachment': hasAttachment?.toString(),
    'labelId': labelId,
  };

  /// Reads a draft via `GET /api/drafts/{id}` — same shape as
  /// `GET /api/mails/{id}` (`MailDetailResponse`).
  Future<Email> getDraft(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
  }) async {
    final body = await _client.get('/api/drafts/${Uri.encodeComponent(id)}');
    return _mapMailDetail(body, resolveFolder);
  }

  /// Replaces a draft via `PUT /api/drafts/{id}` (IMAP drafts cannot be
  /// edited in place — the server deletes and re-APPENDs). Returns a NEW
  /// `mailId`; the old id is invalid afterwards (`422 mail_not_draft`).
  Future<DraftResult> updateDraft(
    String id, {
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async {
    final body = await _client.multipartPut(
      '/api/drafts/${Uri.encodeComponent(id)}',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
        replySourceMailId: replySourceMailId,
      ),
      files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
    );
    return DraftResult(
      created: body['created'] as bool? ?? false,
      mailId: body['mailId'] as String?,
      warning: body['warning'] as String?,
    );
  }

  /// Deletes a draft via `DELETE /api/drafts/{id}` (`204`).
  Future<void> deleteDraft(String id) =>
      _client.delete('/api/drafts/${Uri.encodeComponent(id)}');

  /// Creates a draft via `POST /api/drafts` (IMAP `APPEND`). Returns the
  /// real server-assigned mail id.
  Future<DraftResult> createDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async {
    final body = await _client.multipart(
      '/api/drafts',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
        replySourceMailId: replySourceMailId,
      ),
      files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
    );
    return DraftResult(
      created: body['created'] as bool? ?? true,
      // Null when the append succeeded but the server hasn't reconciled the
      // new message to a mail id yet (see `reconciliationPending`).
      mailId: body['mailId'] as String?,
      warning: body['warning'] as String?,
    );
  }

  /// Sends a draft as-is via `POST /api/drafts/{id}/send` (no body).
  /// [idempotencyKey] must be stable across retries of the same attempt.
  /// `draftRemoved == false` still means "sent" — the mail went out but the
  /// draft copy could not be deleted (spec §5). `delivery_unknown` is never
  /// retried here; the caller surfaces "check Sent" instead.
  Future<SendDraftResult> sendDraft(
    String id, {
    required String idempotencyKey,
  }) async {
    final body = await _client.postWithHeaders(
      '/api/drafts/${Uri.encodeComponent(id)}/send',
      {'Idempotency-Key': idempotencyKey},
    );
    return SendDraftResult(
      sent: body['sent'] as bool? ?? false,
      sentCopySaved: body['sentCopySaved'] as bool? ?? false,
      draftRemoved: body['draftRemoved'] as bool? ?? true,
      warning: body['warning'] as String?,
    );
  }

  /// Prefills the reply/reply-all/forward screen via
  /// `GET /api/mails/{id}/compose/{reply|reply-all|forward}`. The server owns
  /// the `In-Reply-To`/`References` chain — the client only forwards
  /// `replySourceMailId` when sending. Unknown [kind] is an [ArgumentError]
  /// (never a server 404 we manufactured ourselves).
  Future<ComposePrefill> getComposePrefill(
    String sourceMailId,
    String kind,
  ) async {
    if (kind != 'reply' && kind != 'reply-all' && kind != 'forward') {
      throw ArgumentError('Unknown compose kind: $kind');
    }
    final body = await _client.get(
      '/api/mails/${Uri.encodeComponent(sourceMailId)}/compose/$kind',
    );
    final rawAttachments = body['attachments'];
    return ComposePrefill(
      sourceMailId: body['sourceMailId'] as String? ?? sourceMailId,
      to: _addresses(body['to']),
      cc: _addresses(body['cc']),
      suggestedSubject: body['suggestedSubject'] as String? ?? '',
      inReplyToMessageId: body['inReplyToMessageId'] as String?,
      references: body['references'] as String?,
      originalFrom: body['originalFrom'] as String?,
      originalDate: _optionalDate(body['originalDate']),
      originalSubject: body['originalSubject'] as String?,
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map<String, dynamic>>()
                .map(
                  (a) => Attachment(
                    id: a['id'] as String?,
                    name: a['fileName'] as String? ?? 'ek',
                    sizeBytes: (a['sizeBytes'] as num?)?.toInt() ?? 0,
                    mimeType: a['contentType'] as String?,
                  ),
                )
                .toList()
          : const <Attachment>[],
    );
  }

  /// Sends a mail directly via `POST /api/mails/send`. [idempotencyKey]
  /// must be stable across retries of the same send attempt.
  Future<SendResult> sendMail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    required String idempotencyKey,
  }) async {
    final body = await _client.multipart(
      '/api/mails/send',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
        replySourceMailId: replySourceMailId,
      ),
      files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return SendResult(
      sent: body['sent'] as bool? ?? false,
      sentCopySaved: body['sentCopySaved'] as bool? ?? false,
      warning: body['warning'] as String?,
      mailId: body['mailId'] as String?,
      conversationId: body['conversationId'] as String?,
    );
  }

  /// Queues a mail to send at [sendAtUtc] instead of now, via
  /// `POST /api/scheduled-sends`. Same field set/idempotency contract as
  /// [sendMail]; the backend — not this app — fires it at the right time.
  Future<ScheduledSend> scheduleSend({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    required DateTime sendAtUtc,
    required String idempotencyKey,
  }) async {
    final body = await _client.multipart(
      '/api/scheduled-sends',
      fields: {
        ..._composeFields(
          subject: subject,
          bodyText: bodyText,
          bodyHtml: bodyHtml,
          replySourceMailId: replySourceMailId,
        ),
        'sendAtUtc': sendAtUtc.toUtc().toIso8601String(),
      },
      files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _mapScheduledSend(body);
  }

  /// Cancels a still-pending scheduled send via
  /// `DELETE /api/scheduled-sends/{id}` (`204`).
  Future<void> cancelScheduledSend(String id) =>
      _client.delete('/api/scheduled-sends/${Uri.encodeComponent(id)}');

  /// Lists every scheduled send for the account via
  /// `GET /api/scheduled-sends`.
  Future<List<ScheduledSend>> listScheduledSends() async {
    final body = await _client.get('/api/scheduled-sends');
    final items = body['items'] as List? ?? const [];
    return items
        .map((item) => _mapScheduledSend(item as Map<String, dynamic>))
        .toList();
  }

  ScheduledSend _mapScheduledSend(Map<String, dynamic> body) => ScheduledSend(
    id: body['id'] as String,
    to: _addresses(body['to']),
    cc: _addresses(body['cc']),
    bcc: _addresses(body['bcc']),
    subject: body['subject'] as String? ?? '',
    sendAt: DateTime.parse(body['sendAtUtc'] as String).toLocal(),
    status: ScheduledSendStatus.fromApi(body['status'] as String? ?? 'Pending'),
    createdAt: DateTime.parse(body['createdAtUtc'] as String).toLocal(),
    sentMailId: body['sentMailId'] as String?,
    failureReason: body['failureReason'] as String?,
  );

  Map<String, String> _composeFields({
    required String subject,
    required String bodyText,
    String? bodyHtml,
    String? replySourceMailId,
  }) => {
    'subject': subject,
    'bodyText': bodyText,
    'bodyHtml': ?bodyHtml,
    'replySourceMailId': ?replySourceMailId,
  };

  /// `To`/`Cc`/`Bcc` are read server-side as repeated same-name form
  /// values (`form["To"]`), not indexed keys — `MultipartRequest.fields` is
  /// single-valued per key, so each address goes in as a nameless text
  /// part instead, the same list `MultipartRequest` sends attachment files
  /// through. Attachments without picked file [Attachment.bytes]
  /// (fetched from the server, or a picker that only returned metadata) are
  /// silently dropped — sent as metadata with no way to upload content.
  List<http.MultipartFile> _composeParts({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required List<Attachment> attachments,
  }) => [
    for (final address in to) http.MultipartFile.fromString('To', address),
    for (final address in cc) http.MultipartFile.fromString('Cc', address),
    for (final address in bcc) http.MultipartFile.fromString('Bcc', address),
    for (final attachment in attachments)
      if (attachment.bytes != null)
        http.MultipartFile.fromBytes(
          'attachments',
          attachment.bytes!,
          filename: attachment.name,
        ),
  ];

  /// Null-valued entries are dropped so unset filters never reach the wire.
  String _buildQuery(String path, Map<String, String?> params) {
    final query = params.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value!)}',
        )
        .join('&');
    return '$path?$query';
  }

  static String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

  Email _mapMail(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) => Email(
    id: item['id'] as String,
    senderName:
        _nonEmpty(item['fromDisplayName']) ?? item['fromAddress'] as String,
    senderEmail: item['fromAddress'] as String,
    recipients: (item['toAddress'] as String?) != null
        ? [item['toAddress'] as String]
        : const [],
    subject: item['subject'] as String,
    // List items carry a ~120 char `snippet` instead of the full body; the
    // detail fetch replaces it.
    bodyText: item['bodyText'] as String? ?? item['snippet'] as String? ?? '',
    timestamp: _optionalDate(item['receivedAt']) ?? DateTime.now(),
    isRead: item['isRead'] as bool? ?? false,
    isStarred: item['flagged'] as bool? ?? false,
    isReplied: item['answered'] as bool? ?? false,
    hasAttachments: item['hasAttachments'] as bool? ?? false,
    accountId: item['accountId'] as String? ?? '',
    folder: resolveFolder(item['folderId'] as String),
    threadId: item['conversationId'] as String? ?? '',
  );

  /// Participant lists arrive either as address strings or as
  /// `{ address, displayName }` objects — accept both, tolerate anything.
  static List<String> _addresses(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty)
          entry
        else if (entry is Map<String, dynamic> &&
            (entry['address'] as String?)?.isNotEmpty == true)
          entry['address'] as String,
    ];
  }

  /// First parseable timestamp out of the documented date fields, falling
  /// back to now so a malformed/missing date never breaks the whole mail.
  static DateTime _parseDate(Map<String, dynamic> item) {
    for (final key in ['receivedAt', 'sentAt', 'internalDate']) {
      final parsed = _optionalDate(item[key]);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

  /// The backend sends every timestamp as UTC ISO-8601 (`…Z`); convert to
  /// the device zone so displayed times match the user's clock.
  static DateTime? _optionalDate(dynamic raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

  /// Prefers `bodyText`; falls back to a *safe* plain-text rendering of
  /// `body.html` for HTML-only messages (no WebView, no remote content).
  /// Never returns null — worst case an empty body, never a crash.
  static String _resolveBodyText(
    Map<String, dynamic> item,
    Map<String, dynamic>? body,
  ) {
    final raw = item['bodyText'] as String?;
    if (raw != null && raw.trim().isNotEmpty) return raw;
    final html = body?['html'] as String?;
    if (html != null && html.trim().isNotEmpty) return htmlToPlainText(html);
    return '';
  }

  /// Maps one `include=body` conversation message. No recipients/attachment
  /// list in this shape — see [getConversationWithBodies].
  Email mapConversationMessage(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) {
    final address = item['fromAddress'] as String? ?? '';
    final name = item['fromDisplayName'] as String? ?? '';
    final body = item['body'] is Map<String, dynamic>
        ? item['body'] as Map<String, dynamic>
        : null;
    return Email(
      id: item['id'] as String,
      senderName: name.isNotEmpty ? name : address,
      senderEmail: address,
      recipients: const [],
      subject: item['subject'] as String? ?? '',
      bodyText: _resolveBodyText(item, body),
      bodyHtml: _nonEmpty(body?['html']),
      hasRemoteContent: body?['hasRemoteContent'] as bool? ?? false,
      timestamp: _parseDate(item),
      isRead: item['isRead'] as bool? ?? false,
      folder: resolveFolder(item['folderId'] as String),
      threadId: item['conversationId'] as String? ?? '',
    );
  }

  Email _mapMailDetail(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) {
    final fromRaw = item['from'] is List ? item['from'] as List : const [];
    final fromList = _addresses(fromRaw);
    final fromNames = [
      for (final entry in fromRaw)
        if (entry is Map<String, dynamic>)
          entry['displayName'] as String? ?? '',
    ];
    final rawAttachments = item['attachments'];
    final attachments = rawAttachments is List
        ? rawAttachments
              .whereType<Map<String, dynamic>>()
              .map(
                (a) => Attachment(
                  id: a['id'] as String?,
                  name: a['fileName'] as String? ?? 'ek',
                  sizeBytes: (a['sizeBytes'] as num?)?.toInt() ?? 0,
                  mimeType: a['contentType'] as String?,
                ),
              )
              .toList()
        : const <Attachment>[];
    final body = item['body'] is Map<String, dynamic>
        ? item['body'] as Map<String, dynamic>
        : null;
    final inReplyTo = item['inReplyToMessageId'] as String?;
    return Email(
      id: item['id'] as String,
      senderName: fromNames.isNotEmpty && fromNames.first.isNotEmpty
          ? fromNames.first
          : (fromList.isNotEmpty ? fromList.first : ''),
      senderEmail: fromList.isNotEmpty ? fromList.first : '',
      recipients: _addresses(item['to']),
      cc: _addresses(item['cc']),
      bcc: _addresses(item['bcc']),
      subject: item['subject'] as String? ?? '',
      bodyText: _resolveBodyText(item, body),
      bodyHtml: _nonEmpty(body?['html']),
      hasRemoteContent: body?['hasRemoteContent'] as bool? ?? false,
      timestamp: _parseDate(item),
      isRead: item['isRead'] as bool? ?? false,
      isStarred: item['flagged'] as bool? ?? false,
      isReplied: item['answered'] as bool? ?? false,
      accountId: item['accountId'] as String? ?? '',
      folder: resolveFolder(item['folderId'] as String),
      threadId: item['conversationId'] as String? ?? '',
      inReplyToId: inReplyTo == null || inReplyTo.isEmpty ? null : inReplyTo,
      attachments: attachments,
      hasAttachments: item['hasAttachments'] as bool? ?? attachments.isNotEmpty,
      headers: _mapHeaders(item['headers']),
    );
  }

  /// `headers: [{ name, value }]` -> case-insensitively keyed map (last
  /// value wins on a duplicate name; good enough for the single-value
  /// headers this app reads, e.g. `List-Unsubscribe`).
  static Map<String, String> _mapHeaders(dynamic raw) {
    if (raw is! List) return const {};
    final map = <String, String>{};
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final name = entry['name'] as String?;
      final value = entry['value'] as String?;
      if (name == null || value == null) continue;
      map[name.toLowerCase()] = value;
    }
    return map;
  }
}

/// One row from `GET /api/conversations`: subject-level metadata only, no
/// message bodies. [ApiConversation.messageIds] (via [getConversation]) plus
/// one [getMail] per message resolves the full thread.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.subject,
    required this.participants,
    required this.messageCount,
    required this.unreadCount,
    required this.hasAttachments,
    this.startedAt,
    this.lastMessageAt,
  });

  final String id;
  final String subject;
  final List<String> participants;
  final int messageCount;
  final int unreadCount;
  final bool hasAttachments;
  final DateTime? startedAt;
  final DateTime? lastMessageAt;
}

class ConversationListPage {
  ConversationListPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<ConversationSummary> items;
  final int page;
  final int pageSize;
  final int total;
}

/// A server-side conversation from `GET /api/conversations/{id}`: the
/// subject plus its message ids. Messages arrive as summaries without
/// bodies — fetch each one via [ApiMailService.getMail] for full content.
class ApiConversation {
  const ApiConversation({
    required this.id,
    required this.subject,
    required this.messageIds,
    this.messages = const [],
  });

  final String id;
  final String subject;
  final List<String> messageIds;
  final List<Map<String, dynamic>> messages;
}

/// One FCM device registration from `POST /api/devices` (`201`).
class DeviceRegistration {
  const DeviceRegistration({
    required this.id,
    required this.platform,
    required this.appVersion,
    required this.locale,
    this.registeredAt,
    this.lastSeenAt,
  });

  final String id;
  final String platform;
  final String appVersion;
  final String locale;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;
}

class ApiMailFolder {
  const ApiMailFolder({
    required this.id,
    required this.mailAccountId,
    required this.name,
    String? fullName,
    required this.type,
    this.unreadCount,
    this.totalCount,
    this.isSyncEnabled = false,
    this.isAvailable = true,
    this.delimiter,
    this.parentId,
  }) : fullName = fullName ?? name;

  factory ApiMailFolder.fromJson(Map<String, dynamic> item) => ApiMailFolder(
    id: item['id'] as String,
    mailAccountId: item['mailAccountId'] as String,
    name: item['name'] as String,
    fullName: item['fullName'] as String? ?? item['name'] as String,
    type: item['folderType'] as String,
    unreadCount: (item['unreadCount'] as num?)?.toInt(),
    totalCount: (item['totalCount'] as num?)?.toInt(),
    isSyncEnabled: item['isSyncEnabled'] as bool? ?? false,
    isAvailable: item['isAvailable'] as bool? ?? true,
    delimiter: item['delimiter'] as String?,
    parentId: item['parentId'] as String?,
  );

  final String id;
  final String mailAccountId;
  final String name;

  /// Full IMAP path (e.g. `Projeler/Arşiv`).
  final String fullName;
  final String type;

  /// Server-side count (deleted mails excluded); null when the backend omits it.
  final int? unreadCount;

  /// Total live mail count; null when the backend omits it.
  final int? totalCount;

  /// Whether this folder is included in the backend's periodic background
  /// sync (Inbox/Sent by default).
  final bool isSyncEnabled;

  /// `false` means the folder was deleted on the mail server — hide it.
  final bool isAvailable;

  final String? delimiter;
  final String? parentId;
}

/// Per-item outcome from `POST /api/mails/bulk/{action}`.
class BulkActionResult {
  const BulkActionResult({
    required this.mailId,
    required this.success,
    this.code,
  });

  final String mailId;
  final bool success;

  /// Failure error code (see the mail action error table), null on success.
  final String? code;
}

/// Result of `POST /api/drafts`.
class DraftResult {
  const DraftResult({
    required this.created,
    required this.mailId,
    this.warning,
  });

  final bool created;

  /// Null when the append succeeded but reconciliation to a mail id is
  /// still pending server-side.
  final String? mailId;
  final String? warning;
}

/// Result of `POST /api/drafts/{id}/send`.
class SendDraftResult {
  const SendDraftResult({
    required this.sent,
    required this.sentCopySaved,
    required this.draftRemoved,
    this.warning,
  });

  final bool sent;
  final bool sentCopySaved;

  /// False means the mail went out but the draft copy survived — still show
  /// "sent", never an error (spec §5).
  final bool draftRemoved;
  final String? warning;
}

/// Result of `POST /api/mails/send`.
class SendResult {
  const SendResult({
    required this.sent,
    required this.sentCopySaved,
    this.warning,
    this.mailId,
    this.conversationId,
  });

  final bool sent;
  final bool sentCopySaved;
  final String? warning;

  /// Sent-folder record of the mail; null when the copy wasn't saved or was
  /// not found yet (also on idempotent replays).
  final String? mailId;
  final String? conversationId;
}

class MailListPage {
  MailListPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<Email> items;
  final int page;
  final int pageSize;
  final int total;
}
