part of '../api_mail_service.dart';

DateTime _date(Object? v) =>
    _optionalDate(v) ?? DateTime.fromMillisecondsSinceEpoch(0);

({String scope, Set<String> syncedFolderIds}) _mapSyncScope(
  Map<String, dynamic> body,
) => (
  scope: body['scope'] as String,
  syncedFolderIds: (body['syncedFolderIds'] as List<dynamic>)
      .cast<String>()
      .toSet(),
);

ConversationSummary _mapConversation(Map<String, dynamic> item) {
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

Map<String, String?> _searchParams({
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

String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;

/// Participant lists arrive either as address strings or as
/// `{ address, displayName }` objects — accept both, tolerate anything.
List<String> _addresses(dynamic value) {
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

List<String> _stringList(dynamic value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

/// First parseable timestamp out of the documented date fields, falling
/// back to now so a malformed/missing date never breaks the whole mail.
DateTime _parseDate(Map<String, dynamic> item) {
  for (final key in ['receivedAt', 'sentAt', 'internalDate']) {
    final parsed = _optionalDate(item[key]);
    if (parsed != null) return parsed;
  }
  return DateTime.now();
}

/// The backend sends every timestamp as UTC ISO-8601 (`…Z`); convert to
/// the device zone so displayed times match the user's clock.
DateTime? _optionalDate(dynamic raw) =>
    raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

/// Prefers `bodyText`; falls back to a *safe* plain-text rendering of
/// `body.html` for HTML-only messages (no WebView, no remote content).
/// Never returns null — worst case an empty body, never a crash.
String _resolveBodyText(Map<String, dynamic> item, Map<String, dynamic>? body) {
  final raw = item['bodyText'] as String?;
  if (raw != null && raw.trim().isNotEmpty) return raw;
  final html = body?['html'] as String?;
  if (html != null && html.trim().isNotEmpty) return htmlToPlainText(html);
  return '';
}

/// `headers: [{ name, value }]` -> case-insensitively keyed map (last
/// value wins on a duplicate name; good enough for the single-value
/// headers this app reads, e.g. `List-Unsubscribe`).
Map<String, String> _mapHeaders(dynamic raw) {
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

MailAuthentication? _mapAuthentication(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  final authentication = MailAuthentication(
    authservId: raw['authservId'] as String?,
    spf: raw['spf'] as String?,
    dkim: raw['dkim'] as String?,
    dmarc: raw['dmarc'] as String?,
  );
  return authentication.hasResults ? authentication : null;
}

MailContentSecurity? _mapSecurity(dynamic raw) {
  if (raw is! Map<String, dynamic>) return null;
  return MailContentSecurity(
    signed: raw['signed'] as String?,
    encrypted: raw['encrypted'] as String?,
  );
}
