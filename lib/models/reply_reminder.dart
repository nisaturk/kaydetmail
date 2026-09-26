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

  /// Backend alan adları camelCase gelir; tek bozuk kayıt tüm listeyi
  /// düşürmesin diye [tryParse] null döner, listeleyen taraf atlar.
  factory ReplyReminder.fromJson(Map<String, dynamic> json) =>
      tryParse(json) ??
      (throw const FormatException('Geçersiz yanıt takibi kaydı.'));

  static ReplyReminder? tryParse(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final mailId = json['mailId'] as String?;
    final dueAt = _parseDate(json['dueAtUtc']);
    final createdAt = _parseDate(json['createdAt']);
    final sentAt = _parseDate(json['sentAt']);
    if (id == null || mailId == null || dueAt == null || createdAt == null || sentAt == null) {
      return null;
    }
    return ReplyReminder(
      id: id,
      mailId: mailId,
      conversationId: json['conversationId'] as String?,
      dueAtUtc: dueAt,
      createdAt: createdAt,
      status: json['status'] as String? ?? 'Pending',
      notifiedAt: json['notifiedAt'] == null ? null : _parseDate(json['notifiedAt']),
      subject: json['subject'] as String? ?? '',
      recipient: json['recipient'] as String? ?? '',
      sentAt: sentAt,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

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
