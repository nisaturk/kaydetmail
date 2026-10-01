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

  /// Acknowledged actions return success; a no-UID move also carries pending
  /// reconciliation. Follow-up actions must wait for the backend to rebind UID.
  Future<BulkActionResult> mailAction(String id, String action) async {
    final body = await _client.post(
      '/api/mails/${Uri.encodeComponent(id)}/$action',
    );
    return BulkActionResult(
      mailId: id,
      success: true,
      reconciliationPending: body['reconciliationPending'] == true,
    );
  }

  Future<BulkActionResult> moveMail(String id, String folderId) async {
    final body = await _client.postJson(
      '/api/mails/${Uri.encodeComponent(id)}/move',
      {'folderId': folderId},
    );
    return BulkActionResult(
      mailId: id,
      success: true,
      reconciliationPending: body['reconciliationPending'] == true,
    );
  }

  /// Copies without removing the source.
  Future<BulkActionResult> copyMail(String id, String folderId) async {
    final body = await _client.postJson(
      '/api/mails/${Uri.encodeComponent(id)}/copy',
      {'folderId': folderId},
    );
    return BulkActionResult(
      mailId: id,
      success: true,
      reconciliationPending: body['reconciliationPending'] == true,
    );
  }

  /// Sends at most 100 ids per request. A later transport failure is returned
  /// per item so callers retain remote-committed outcomes from earlier chunks.
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    const maxBatchSize = 100;
    final ids = mailIds.toSet().toList();
    final results = <BulkActionResult>[];
    for (var start = 0; start < ids.length; start += maxBatchSize) {
      final end = start + maxBatchSize < ids.length
          ? start + maxBatchSize
          : ids.length;
      try {
        final body = await _client.postJson('/api/mails/bulk/$action', {
          'mailIds': ids.sublist(start, end),
          'folderId': folderId,
        });
        final responseResults = body['results'] as List;
        final byId = {
          for (final r in responseResults)
            r['mailId'] as String: BulkActionResult(
              mailId: r['mailId'] as String,
              success: r['success'] as bool,
              code: r['code'] as String?,
              reconciliationPending: r['reconciliationPending'] == true,
            ),
        };
        for (var index = start; index < end; index++) {
          results.add(
            byId[ids[index]] ??
                BulkActionResult(
                  mailId: ids[index],
                  success: false,
                  code: 'mail_operation_failed',
                  retryable: true,
                ),
          );
        }
      } catch (error) {
        final apiError = error is ApiException ? error : null;
        for (var index = start; index < ids.length; index++) {
          results.add(
            BulkActionResult(
              mailId: ids[index],
              success: false,
              code: apiError?.code ?? 'mail_operation_failed',
              retryable:
                  apiError == null ||
                  apiError.isTransient ||
                  apiError.category == ApiErrorCategory.authentication ||
                  apiError.code == 'mail_account_needs_reauthentication',
            ),
          );
        }
        break;
      }
    }
    return results;
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
