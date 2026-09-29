part of '../api_mail_service.dart';

mixin _ComposeApi on _ApiMailServiceBase {
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
    String? identityId,
  }) async {
    final body = await _client.multipartPut(
      '/api/drafts/${Uri.encodeComponent(id)}',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
        replySourceMailId: replySourceMailId,
        identityId: identityId,
      ),
      files: () =>
          _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
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
    String? identityId,
  }) async {
    final body = await _client.multipart(
      '/api/drafts',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
        replySourceMailId: replySourceMailId,
        identityId: identityId,
      ),
      files: () =>
          _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
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
    String? identityId,
    bool requestReadReceipt = false,
    required String idempotencyKey,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    final body = await _client.multipart(
      '/api/mails/send',
      fields: {
        ..._composeFields(
          subject: subject,
          bodyText: bodyText,
          bodyHtml: bodyHtml,
          replySourceMailId: replySourceMailId,
          identityId: identityId,
        ),
        'requestReadReceipt': '$requestReadReceipt',
      },
      files: () =>
          _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      headers: {'Idempotency-Key': idempotencyKey},
      onProgress: onProgress,
      abortTrigger: abortTrigger,
    );
    return SendResult(
      sent: body['sent'] as bool? ?? false,
      sentCopySaved: body['sentCopySaved'] as bool? ?? false,
      warning: body['warning'] as String?,
      mailId: body['mailId'] as String?,
      conversationId: body['conversationId'] as String?,
    );
  }

  Future<ComposeLimits> getComposeLimits() async =>
      ComposeLimits.fromJson(await _client.get('/api/compose/limits'));

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
    String? identityId,
    bool requestReadReceipt = false,
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
          identityId: identityId,
        ),
        'sendAtUtc': sendAtUtc.toUtc().toIso8601String(),
        'requestReadReceipt': '$requestReadReceipt',
      },
      files: () =>
          _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _mapScheduledSend(body);
  }

  /// Cancels a still-pending scheduled send via
  /// `DELETE /api/scheduled-sends/{id}` (`204`).
  Future<void> cancelScheduledSend(String id) =>
      _client.delete('/api/scheduled-sends/${Uri.encodeComponent(id)}');

  /// Fetches one scheduled send with its body and staged attachments via
  /// `GET /api/scheduled-sends/{id}`.
  Future<ScheduledSendDetail> getScheduledSend(String id) async {
    final body = await _client.get(
      '/api/scheduled-sends/${Uri.encodeComponent(id)}',
    );
    return ScheduledSendDetail.fromJson(body);
  }

  /// Replaces a pending scheduled send's content atomically via
  /// `PUT /api/scheduled-sends/{id}` (multipart). Staged attachments not
  /// listed in [keepAttachmentIds] are removed; [attachments] are staged
  /// as new files.
  Future<void> updateScheduledSend({
    required String id,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    String? bodyHtml,
    required DateTime sendAtUtc,
    List<String> keepAttachmentIds = const [],
    List<Attachment> attachments = const [],
  }) => _client.multipartPut(
    '/api/scheduled-sends/${Uri.encodeComponent(id)}',
    fields: {
      ..._composeFields(
        subject: subject,
        bodyText: bodyText,
        bodyHtml: bodyHtml,
      ),
      'sendAtUtc': sendAtUtc.toUtc().toIso8601String(),
    },
    files: () => [
      ..._composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      for (final kept in keepAttachmentIds)
        http.MultipartFile.fromString('keepAttachmentIds', kept),
    ],
  );

  /// Re-queues a failed send as a new pending one via
  /// `POST /api/scheduled-sends/{id}/reschedule` (JSON). A null
  /// [attachmentIds] preserves every staged attachment; [idempotencyKey]
  /// must be fresh — reusing the failed send's key is a 409.
  Future<void> rescheduleFailedSend({
    required String id,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    String? bodyHtml,
    List<String>? attachmentIds,
    required DateTime sendAtUtc,
    required String idempotencyKey,
  }) => _client.postJson(
    '/api/scheduled-sends/${Uri.encodeComponent(id)}/reschedule',
    {
      'sendAtUtc': sendAtUtc.toUtc().toIso8601String(),
      'to': to,
      'cc': cc,
      'bcc': bcc,
      'subject': subject,
      'bodyText': bodyText,
      'bodyHtml': bodyHtml,
      'attachmentIds': attachmentIds,
    },
    headers: {'Idempotency-Key': idempotencyKey},
  );

  /// Lists every scheduled send for the account via
  /// `GET /api/scheduled-sends`.
  Future<List<ScheduledSend>> listScheduledSends() async {
    final body = await _client.get('/api/scheduled-sends');
    final items = body['items'] as List? ?? const [];
    return items
        .map((item) => _mapScheduledSend(item as Map<String, dynamic>))
        .toList();
  }
}
