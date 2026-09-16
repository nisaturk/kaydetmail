import 'package:flutter/foundation.dart';

import 'mail_folder.dart';

/// A file attached to an email.
@immutable
class Attachment {
  const Attachment({
    required this.name,
    required this.sizeBytes,
    this.mimeType,
  });

  final String name;
  final int sizeBytes;
  final String? mimeType;

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
/// Deliberately kept independent of any backend response shape so both the
/// mock repository and the future API repository can map to/from it.
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
    required this.timestamp,
    this.isRead = false,
    this.isPinned = false,
    this.isStarred = false,
    this.isReplied = false,
    this.isForwarded = false,
    this.folder = MailFolder.inbox,
    this.labelIds = const [],
    this.attachments = const [],
    this.accountId = '',
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
  final DateTime timestamp;
  final bool isRead;
  final bool isPinned;
  final bool isStarred;
  final bool isReplied;
  final bool isForwarded;
  final MailFolder folder;

  /// Ids of the labels attached to this mail (see `MailLabel`).
  final List<String> labelIds;
  final List<Attachment> attachments;

  /// Id of the [MailAccount] that owns this mail (the lowercase account
  /// email). Empty means "unassigned" — repositories stamp it on ingest.
  /// Never duplicated across accounts: one mail object lives in exactly one
  /// account, so starring/reading/deleting it in the unified inbox affects
  /// only the originating account.
  final String accountId;

  /// One-line preview derived from the body.
  String get preview {
    final compact = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
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
    DateTime? timestamp,
    bool? isRead,
    bool? isPinned,
    bool? isStarred,
    bool? isReplied,
    bool? isForwarded,
    MailFolder? folder,
    List<String>? labelIds,
    List<Attachment>? attachments,
    String? accountId,
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
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      isPinned: isPinned ?? this.isPinned,
      isStarred: isStarred ?? this.isStarred,
      isReplied: isReplied ?? this.isReplied,
      isForwarded: isForwarded ?? this.isForwarded,
      folder: folder ?? this.folder,
      labelIds: labelIds ?? this.labelIds,
      attachments: attachments ?? this.attachments,
      accountId: accountId ?? this.accountId,
    );
  }

  @override
  bool operator ==(Object other) => other is Email && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
