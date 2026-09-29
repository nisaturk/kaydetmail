import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/account_notification_settings.dart';
import '../models/compose_prefill.dart';
import '../models/compose_limits.dart';
import '../models/email.dart';
import '../models/mail_authentication.dart';
import '../models/mail_header_entry.dart';
import '../models/mail_security.dart';
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../models/mail_session.dart';
import '../models/remote_search_result.dart';
import '../models/mail_template.dart';
import '../models/scheduled_send.dart';
import '../models/scheduled_send_detail.dart';
import '../models/mail_signature.dart';
import '../models/trusted_sender.dart';
import '../utils/html_to_text.dart';
import '../utils/attachment_mime.dart';
import 'api_auth_service.dart';
import 'api_client.dart';
import 'api_exception.dart';

part 'api_mail_service/account.dart';
part 'api_mail_service/folders.dart';
part 'api_mail_service/mail.dart';
part 'api_mail_service/organize.dart';
part 'api_mail_service/search.dart';
part 'api_mail_service/compose.dart';
part 'api_mail_service/mapping.dart';
part 'api_mail_service/models.dart';

/// Shared state and response mapping for the endpoint groups below.
abstract class _ApiMailServiceBase {
  _ApiMailServiceBase(
    this._client, {
    this.syncPollInterval = const Duration(seconds: 1),
    this.syncTimeout = const Duration(minutes: 2),
  });

  final ApiClient _client;

  final Duration syncPollInterval;

  final Duration syncTimeout;

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

  MailAccount _mapAccount(Map<String, dynamic> body) => MailAccount(
    id: body['id'] as String,
    email: body['emailAddress'] as String,
    displayName: body['displayName'] as String?,
    provider: AccountProvider.fromBackend(body['provider'] as String),
    status: MailAccountStatus.fromBackend(body['status'] as String?),
    signature: body['signature'] as String?,
  );

  /// `POST`/`PUT` responses only carry `{ id, sendAtUtc, status }` —
  /// every other field falls back to a neutral default instead of throwing.
  ScheduledSend _mapScheduledSend(Map<String, dynamic> body) {
    DateTime orNow(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : DateTime.now();
    return ScheduledSend(
      id: body['id'] as String,
      to: _addresses(body['to']),
      cc: _addresses(body['cc']),
      bcc: _addresses(body['bcc']),
      subject: body['subject'] as String? ?? '',
      sendAt: orNow(body['sendAtUtc']),
      status: ScheduledSendStatus.fromApi(
        body['status'] as String? ?? 'Pending',
      ),
      createdAt: orNow(body['createdAtUtc']),
      sentMailId: body['sentMailId'] as String?,
      failureReason: body['failureReason'] as String?,
      attemptCount: (body['attemptCount'] as num?)?.toInt() ?? 0,
      nextAttemptAtUtc: body['nextAttemptAtUtc'] is String
          ? DateTime.parse(body['nextAttemptAtUtc'] as String).toLocal()
          : null,
    );
  }

  Map<String, String> _composeFields({
    required String subject,
    required String bodyText,
    String? bodyHtml,
    String? replySourceMailId,
    String? identityId,
  }) => {
    'subject': subject,
    'bodyText': bodyText,
    'bodyHtml': ?bodyHtml,
    'replySourceMailId': ?replySourceMailId,
    'identityId': ?identityId,
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
          contentType: attachmentMediaType(
            attachment.name,
            attachment.mimeType,
          ),
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
    imapAnswered: item['answered'] as bool? ?? false,
    hasAttachments: item['hasAttachments'] as bool? ?? false,
    accountId: item['accountId'] as String? ?? '',
    folder: resolveFolder(item['folderId'] as String),
    threadId: item['conversationId'] as String? ?? '',
  );

  /// Maps one `include=body` conversation message, including recipients.
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
      recipients: _addresses(item['to']),
      cc: _addresses(item['cc']),
      bcc: _addresses(item['bcc']),
      subject: item['subject'] as String? ?? '',
      bodyText: _resolveBodyText(item, body),
      bodyHtml: _nonEmpty(body?['html']),
      hasRemoteContent: body?['hasRemoteContent'] as bool? ?? false,
      remoteImageHosts: _stringList(body?['remoteImageHosts']),
      trackingPixelHosts: _stringList(body?['trackingPixelHosts']),
      remoteImagesAllowed: body?['remoteImagesAllowed'] as bool? ?? false,
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
      remoteImageHosts: _stringList(body?['remoteImageHosts']),
      trackingPixelHosts: _stringList(body?['trackingPixelHosts']),
      remoteImagesAllowed: body?['remoteImagesAllowed'] as bool? ?? false,
      timestamp: _parseDate(item),
      isRead: item['isRead'] as bool? ?? false,
      isStarred: item['flagged'] as bool? ?? false,
      imapAnswered: item['answered'] as bool? ?? false,
      accountId: item['accountId'] as String? ?? '',
      folder: resolveFolder(item['folderId'] as String),
      threadId: item['conversationId'] as String? ?? '',
      inReplyToId: inReplyTo == null || inReplyTo.isEmpty ? null : inReplyTo,
      attachments: attachments,
      hasAttachments: item['hasAttachments'] as bool? ?? attachments.isNotEmpty,
      headers: _mapHeaders(item['headers']),
      authentication: _mapAuthentication(item['authentication']),
      security: _mapSecurity(item['security']),
    );
  }
}

/// Typed client for the KaydetMail backend, one mixin per endpoint group
/// (account, folders, mail, labels/contacts/templates/signatures, search,
/// drafts/sending) under `api_mail_service/`.
class ApiMailService extends _ApiMailServiceBase
    with
        _AccountApi,
        _FolderApi,
        _MailApi,
        _OrganizeApi,
        _SearchApi,
        _ComposeApi {
  ApiMailService(super._client, {super.syncPollInterval, super.syncTimeout});
}
