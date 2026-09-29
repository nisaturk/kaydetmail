part of '../api_mail_service.dart';

mixin _MailApi on _ApiMailServiceBase {
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
    bool allowRemoteImages = false,
  }) async {
    final path =
        '/api/mails/${Uri.encodeComponent(id)}${allowRemoteImages ? '?remoteContent=allow' : ''}';
    final body = await _client.get(path);
    return _mapMailDetail(body, resolveFolder);
  }

  Future<List<MailHeaderEntry>> getMailHeaders(String id) async {
    final body = await _client.get(
      '/api/mails/${Uri.encodeComponent(id)}/headers',
    );
    return [
      for (final entry in body['headers'] as List)
        if (entry is Map<String, dynamic>)
          MailHeaderEntry(
            name: entry['name'] as String? ?? '',
            value: entry['value'] as String? ?? '',
          ),
    ];
  }

  Future<String> getMailSource(String id) async {
    final bytes = await _client.getBytes(
      '/api/mails/${Uri.encodeComponent(id)}/source',
    );
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<MailSignatureVerification> getMailSignature(String id) async {
    final body = await _client.get(
      '/api/mails/${Uri.encodeComponent(id)}/signature',
    );
    return MailSignatureVerification(
      standard: body['standard'] as String,
      status: body['status'] as String,
      signers: [
        for (final entry in body['signers'] as List)
          if (entry is Map<String, dynamic>)
            MailSigner(
              name: entry['name'] as String?,
              email: entry['email'] as String?,
              signedAt: DateTime.tryParse(entry['signedAt'] as String? ?? ''),
              certificateExpiresAt: DateTime.tryParse(
                entry['certificateExpiresAt'] as String? ?? '',
              ),
            ),
      ],
    );
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

  Future<List<TrustedSender>> getTrustedSenders() async {
    final body = await _client.get('/api/trusted-senders');
    final items = body['items'] as List? ?? const [];
    return [
      for (final item in items)
        TrustedSender.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<TrustedSender> addTrustedSender(
    TrustedSenderKind kind,
    String value,
  ) async => TrustedSender.fromJson(
    await _client.postJson('/api/trusted-senders', {
      'kind': kind.apiValue,
      'value': value,
    }),
  );

  Future<void> removeTrustedSender(String id) =>
      _client.delete('/api/trusted-senders/${Uri.encodeComponent(id)}');
}
