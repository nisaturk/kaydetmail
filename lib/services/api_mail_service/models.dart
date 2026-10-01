part of '../api_mail_service.dart';

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
    this.parentIdKnown = false,
    this.roleOverride,
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
    parentIdKnown: item.containsKey('parentId'),
    roleOverride: item['folderRoleOverride'] as String?,
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
  final bool parentIdKnown;

  /// User-assigned role (`Sent`/`Drafts`/`Trash`/`Junk`); [type] already
  /// reflects it. Null when the role comes from server detection.
  final String? roleOverride;
}

/// Per-item outcome from `POST /api/mails/bulk/{action}`.
class BulkActionResult {
  const BulkActionResult({
    required this.mailId,
    required this.success,
    this.code,
    this.reconciliationPending = false,
    this.retryable = false,
  });

  final String mailId;
  final bool success;
  /// The remote move committed, but its destination UID is not known yet.
  final bool reconciliationPending;

  /// Transport failures affect only this item and the unattempted tail, never
  /// outcomes already acknowledged by an earlier chunk.
  final bool retryable;

  bool get canRetry => retryable || switch (code) {
    'mail_reconciliation_pending' ||
    'mail_account_needs_reauthentication' ||
    'mail_provider_unavailable' ||
    'mail_move_failed' ||
    'mail_delete_failed' ||
    'network_unavailable' ||
    'request_timeout' => true,
    _ => false,
  };

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
