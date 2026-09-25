import 'package:flutter/foundation.dart';

@immutable
class ReplyReminder {
  const ReplyReminder({
    required this.id,
    required this.mailId,
    this.conversationId,
    required this.dueAtUtc,
    required this.createdAt,
    required this.status,
    this.notifiedAt,
    required this.subject,
    required this.recipient,
    required this.sentAt,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String mailId;
  final String? conversationId;
  final DateTime dueAtUtc;
  final DateTime createdAt;
  final String status;
  final DateTime? notifiedAt;
  final String subject;
  final String recipient;
  final DateTime sentAt;

  factory ReplyReminder.fromJson(Map<String, dynamic> json) => ReplyReminder(
    id: json['id'] as String,
    mailId: json['mailId'] as String,
    conversationId: json['conversationId'] as String?,
    dueAtUtc: DateTime.parse(json['dueAtUtc'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: json['status'] as String? ?? 'Pending',
    notifiedAt: json['notifiedAt'] == null
        ? null
        : DateTime.parse(json['notifiedAt'] as String),
    subject: json['subject'] as String? ?? '',
    recipient: json['recipient'] as String? ?? '',
    sentAt: DateTime.parse(json['sentAt'] as String),
  );

  ReplyReminder copyWith({String? accountId}) => ReplyReminder(
    id: id,
    mailId: mailId,
    conversationId: conversationId,
    dueAtUtc: dueAtUtc,
    createdAt: createdAt,
    status: status,
    notifiedAt: notifiedAt,
    subject: subject,
    recipient: recipient,
    sentAt: sentAt,
    accountId: accountId ?? this.accountId,
  );
}
