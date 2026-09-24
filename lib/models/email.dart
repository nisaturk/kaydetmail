import 'package:flutter/foundation.dart';

import 'mail_folder.dart';

/// A file attached to an email.
@immutable
class Attachment {
  const Attachment({
    this.id,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
    this.bytes,
  });

  /// Server-side attachment id (`GET /api/mails/{mailId}/attachments/{id}`).
  /// Null for attachments picked locally that haven't been uploaded yet.
  final String? id;

  final String name;
  final int sizeBytes;
  final String? mimeType;

  /// File content, when picked from disk. Null for attachments fetched from
  /// the server (display-only) — [ApiMailRepository] needs this to actually
  /// upload the file; without it the attachment is sent as metadata only.
  final Uint8List? bytes;

  String get sizeLabel {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  bool operator ==(Object other) =>
      other is Attachment && other.name == name && other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(name, sizeBytes);
}

/// One mail message.
///
/// Deliberately kept independent of any backend response shape so
/// [ApiMailRepository] can map to/from it without leaking API details into
/// the UI.
@immutable
class Email {
  const Email({
    required this.id,
    required this.senderName,
    required this.senderEmail,
    required this.recipients,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.bodyText,
    this.bodyHtml,
    this.hasRemoteContent = false,
    required this.timestamp,
    this.isRead = false,
    this.isPinned = false,
    this.isStarred = false,
    this.isReplied = false,
    this.isForwarded = false,
    this.isAnswered = false,
    this.folder = MailFolder.inbox,
    this.labelIds = const [],
    this.attachments = const [],
    this.hasAttachments = false,
    this.accountId = '',
    this.threadId = '',
    this.inReplyToId,
    this.headers = const {},
  });

  final String id;
  final String senderName;
  final String senderEmail;

  /// Recipients of the mail (the "To" field).
  final List<String> recipients;
  final List<String> cc;
  final List<String> bcc;

  final String subject;
  final String bodyText;

  /// Server-rendered, sanitized HTML body (`body.html` on detail and
  /// conversation responses) — carries the sender's formatting (bold,
  /// lists, tables, …) that [bodyText] flattens. Null on list rows and on
  /// locally composed mail; the plain [bodyText] is shown then.
  final String? bodyHtml;

  /// Whether the original HTML body references remote content (tracking
  /// pixels, remote images, …). Remote resources are never fetched
  /// automatically; this flag only preserves the server's signal for a
  /// future "load remote content" prompt.
  final bool hasRemoteContent;

  final DateTime timestamp;
  final bool isRead;
  final bool isPinned;
  final bool isStarred;
  final bool isReplied;
  final bool isForwarded;

  /// Sent-folder-only: whether this conversation has received an inbound
  /// reply back from the recipient (client-only tracking, mirror of
  /// [isReplied] — see `ApiMailRepository._markSentThreadsAnswered`).
  /// Meaningless outside Sent; always false on mail from other folders.
  final bool isAnswered;
  final MailFolder folder;

  /// Ids of the labels attached to this mail (see `MailLabel`).
  final List<String> labelIds;
  final List<Attachment> attachments;

  /// Server-reported attachment presence (`hasAttachments` on both the list
  /// and detail responses). List rows only ever get this flag — the full
  /// [attachments] metadata is a detail-fetch-only field — so the paperclip
  /// indicator must check this too, not just `attachments.isNotEmpty`,
  /// otherwise it only shows for mail the user has already opened.
  final bool hasAttachments;

  /// Opaque id of the [MailAccount] that owns this mail — the backend
  /// `mailAccountId`, never the email address. Empty means "unassigned" —
  /// repositories stamp it on ingest. Never duplicated across accounts: one
  /// mail object lives in exactly one account, so starring/reading/deleting
  /// it in the unified inbox affects only the originating account.
  final String accountId;

  /// Stable conversation identifier shared by every mail that belongs to the
  /// same thread (a reply reuses the original message's id). Empty means
  /// "unassigned" — repositories stamp one on ingest so older seed/generated
  /// mails stay valid (each becomes its own thread).
  final String threadId;

  /// Id of the message this one replies to, when known. Nothing groups by
  /// this — [threadId] is the conversation identity. Pure provenance.
  final String? inReplyToId;

  /// Raw MIME headers (`GET /api/mails/{id}` `headers`), keyed
  /// case-insensitively. Empty on list rows and locally composed mail —
  /// only a detail fetch populates it. Powers header-driven features like
  /// one-click unsubscribe (`List-Unsubscribe`); never shown to the user
  /// directly.
  final Map<String, String> headers;

  static final _previewCache = Expando<String>('Email.preview');
  static final _whitespace = RegExp(r'\s+');

  /// One-line preview derived from the body. Computed once per instance:
  /// list rows read it on every rebuild, and bodies can be large, so only
  /// the head of the body is normalized.
  String get preview => _previewCache[this] ??= _buildPreview();

  String _buildPreview() {
    final head = bodyText.length > 600 ? bodyText.substring(0, 600) : bodyText;
    final compact = head.replaceAll(_whitespace, ' ').trim();
    if (compact.length <= 120) return compact;
    return '${compact.substring(0, 120).trimRight()}…';
  }

  /// Client-side match used by search. True when [query] is empty or appears
  /// (case-insensitively) in the sender, subject or body.
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return senderName.toLowerCase().contains(q) ||
        senderEmail.toLowerCase().contains(q) ||
        subject.toLowerCase().contains(q) ||
        bodyText.toLowerCase().contains(q);
  }

  Email copyWith({
    String? senderName,
    String? senderEmail,
    List<String>? recipients,
    List<String>? cc,
    List<String>? bcc,
    String? subject,
    String? bodyText,
    String? bodyHtml,
    bool? hasRemoteContent,
    DateTime? timestamp,
    bool? isRead,
    bool? isPinned,
    bool? isStarred,
    bool? isReplied,
    bool? isForwarded,
    bool? isAnswered,
    MailFolder? folder,
    List<String>? labelIds,
    List<Attachment>? attachments,
    bool? hasAttachments,
    String? accountId,
    String? threadId,
    String? inReplyToId,
    Map<String, String>? headers,
  }) {
    return Email(
      id: id,
      senderName: senderName ?? this.senderName,
      senderEmail: senderEmail ?? this.senderEmail,
      recipients: recipients ?? this.recipients,
      cc: cc ?? this.cc,
      bcc: bcc ?? this.bcc,
      subject: subject ?? this.subject,
      bodyText: bodyText ?? this.bodyText,
      bodyHtml: bodyHtml ?? this.bodyHtml,
      hasRemoteContent: hasRemoteContent ?? this.hasRemoteContent,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      isStarred: isStarred ?? this.isStarred,
      isReplied: isReplied ?? this.isReplied,
      isForwarded: isForwarded ?? this.isForwarded,
      isAnswered: isAnswered ?? this.isAnswered,
      folder: folder ?? this.folder,
      labelIds: labelIds ?? this.labelIds,
      attachments: attachments ?? this.attachments,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      accountId: accountId ?? this.accountId,
      threadId: threadId ?? this.threadId,
      inReplyToId: inReplyToId ?? this.inReplyToId,
      headers: headers ?? this.headers,
    );
  }

  @override
  bool operator ==(Object other) => other is Email && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
