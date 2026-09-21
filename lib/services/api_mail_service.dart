import 'package:http/http.dart' as http;

import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_session.dart';
import '../utils/html_to_text.dart';
import 'api_client.dart';

class ApiMailService {
  ApiMailService(this._client);

  final ApiClient _client;

  Future<MailAccount> getAccount() async {
    final body = await _client.get('/api/account');
    return MailAccount(
      id: body['id'] as String,
      email: body['emailAddress'] as String,
      displayName: body['displayName'] as String?,
      provider: AccountProvider.fromBackend(body['provider'] as String),
    );
  }

  /// Permanently deletes the connected account and all its cached mail.
  Future<void> deleteAccount() => _client.delete('/api/account');

  Future<List<MailSession>> getSessions() async {
    final items = await _client.getList('/api/account/sessions');
    return items
        .map(
          (item) => MailSession(
            id: item['id'] as String,
            deviceIdentifier: item['deviceIdentifier'] as String,
            createdAt: DateTime.parse(item['createdAt'] as String),
            lastUsedAt: DateTime.parse(item['lastUsedAt'] as String),
            expiresAt: DateTime.parse(item['expiresAt'] as String),
          ),
        )
        .toList();
  }

  Future<void> deleteSession(String sessionId) =>
      _client.delete('/api/account/sessions/${Uri.encodeComponent(sessionId)}');

  Future<List<ApiMailFolder>> getFolders() async {
    final items = await _client.getList('/api/folders');
    return items
        .map(
          (item) => ApiMailFolder(
            id: item['id'] as String,
            mailAccountId: item['mailAccountId'] as String,
            name: item['name'] as String,
            type: item['folderType'] as String,
          ),
        )
        .toList();
  }

  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = _buildQuery('/api/mails', {
      'folderId': folderId,
      'page': '$page',
      'pageSize': '$pageSize',
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
    );
  }

  /// One of the nine fixed single-mail actions documented for
  /// `POST /api/mails/{id}/{action}` (read, unread, star, unstar, trash,
  /// restore, archive, spam, not-spam). No request/response body.
  Future<void> mailAction(String id, String action) =>
      _client.post('/api/mails/${Uri.encodeComponent(id)}/$action');

  /// Moves a single mail into an arbitrary target folder.
  Future<void> moveMail(String id, String folderId) => _client.postJson(
    '/api/mails/${Uri.encodeComponent(id)}/move',
    {'folderId': folderId},
  );

  /// Applies [action] (read, unread, archive, trash, or move) to every id in
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

  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = _buildQuery('/api/search', {
      'q': query,
      'page': '$page',
      'pageSize': '$pageSize',
      'folderId': ?folderId,
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return items
        .map((item) => _mapMail(item as Map<String, dynamic>, resolveFolder))
        .toList();
  }

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
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async {
    final body = await _client.multipartPut(
      '/api/drafts/${Uri.encodeComponent(id)}',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
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
    List<Attachment> attachments = const [],
    String? replySourceMailId,
  }) async {
    final body = await _client.multipart(
      '/api/drafts',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
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

  /// Sends a mail directly via `POST /api/mails/send`. [idempotencyKey]
  /// must be stable across retries of the same send attempt.
  Future<SendResult> sendMail({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String bodyText = '',
    List<Attachment> attachments = const [],
    String? replySourceMailId,
    required String idempotencyKey,
  }) async {
    final body = await _client.multipart(
      '/api/mails/send',
      fields: _composeFields(
        subject: subject,
        bodyText: bodyText,
        replySourceMailId: replySourceMailId,
      ),
      files: _composeParts(to: to, cc: cc, bcc: bcc, attachments: attachments),
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return SendResult(
      sent: body['sent'] as bool? ?? false,
      sentCopySaved: body['sentCopySaved'] as bool? ?? false,
      warning: body['warning'] as String?,
    );
  }

  Map<String, String> _composeFields({
    required String subject,
    required String bodyText,
    String? replySourceMailId,
  }) => {
    'subject': subject,
    'bodyText': bodyText,
    'replySourceMailId': ?replySourceMailId,
  };

  /// `To`/`Cc`/`Bcc` are read server-side as repeated same-name form
  /// values (`form["To"]`), not indexed keys — `MultipartRequest.fields` is
  /// single-valued per key, so each address goes in as a nameless text
  /// part instead, the same list `MultipartRequest` sends attachment files
  /// through. Attachments without picked file [Attachment.bytes]
  /// (mock/seed data, or a picker that only returned metadata) are
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

  String _buildQuery(String path, Map<String, String> params) {
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$path?$query';
  }

  Email _mapMail(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) => Email(
    id: item['id'] as String,
    senderName: item['fromDisplayName'] as String? ?? '',
    senderEmail: item['fromAddress'] as String,
    recipients: (item['toAddress'] as String?) != null
        ? [item['toAddress'] as String]
        : const [],
    subject: item['subject'] as String,
    bodyText: item['bodyText'] as String? ?? '',
    timestamp:
        DateTime.tryParse(item['receivedAt'] as String) ?? DateTime.now(),
    isRead: item['isRead'] as bool? ?? false,
    isStarred: item['flagged'] as bool? ?? false,
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
      final raw = item[key] as String?;
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime.now();
  }

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
      senderName: fromNames.isNotEmpty ? fromNames.first : '',
      senderEmail: fromList.isNotEmpty ? fromList.first : '',
      recipients: _addresses(item['to']),
      cc: _addresses(item['cc']),
      bcc: _addresses(item['bcc']),
      subject: item['subject'] as String? ?? '',
      bodyText: _resolveBodyText(item, body),
      hasRemoteContent: body?['hasRemoteContent'] as bool? ?? false,
      timestamp: _parseDate(item),
      isRead: item['isRead'] as bool? ?? false,
      isStarred: item['flagged'] as bool? ?? false,
      accountId: item['accountId'] as String? ?? '',
      folder: resolveFolder(item['folderId'] as String),
      threadId: item['conversationId'] as String? ?? '',
      inReplyToId: inReplyTo == null || inReplyTo.isEmpty ? null : inReplyTo,
      attachments: attachments,
    );
  }
}

/// A server-side conversation from `GET /api/conversations/{id}`: the
/// subject plus its message ids. Messages arrive as summaries without
/// bodies — fetch each one via [ApiMailService.getMail] for full content.
class ApiConversation {
  const ApiConversation({
    required this.id,
    required this.subject,
    required this.messageIds,
  });

  final String id;
  final String subject;
  final List<String> messageIds;
}

class ApiMailFolder {
  const ApiMailFolder({
    required this.id,
    required this.mailAccountId,
    required this.name,
    required this.type,
  });

  final String id;
  final String mailAccountId;
  final String name;
  final String type;
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

/// Result of `POST /api/mails/send`.
class SendResult {
  const SendResult({
    required this.sent,
    required this.sentCopySaved,
    this.warning,
  });

  final bool sent;
  final bool sentCopySaved;
  final String? warning;
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
