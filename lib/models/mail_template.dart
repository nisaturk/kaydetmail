import 'package:flutter/foundation.dart';

@immutable
class MailTemplate {
  const MailTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.createdAt,
    required this.updatedAt,
    this.bodyText,
    this.bodyHtml,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String name;
  final String subject;
  final String? bodyText;
  final String? bodyHtml;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MailTemplate.fromJson(Map<String, dynamic> json) => MailTemplate(
    id: json['id'] as String,
    name: json['name'] as String,
    subject: json['subject'] as String? ?? '',
    bodyText: json['bodyText'] as String?,
    bodyHtml: json['bodyHtml'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  MailTemplate copyWith({
    String? accountId,
    String? name,
    String? subject,
    String? bodyText,
    String? bodyHtml,
  }) => MailTemplate(
    id: id,
    accountId: accountId ?? this.accountId,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    bodyText: bodyText ?? this.bodyText,
    bodyHtml: bodyHtml ?? this.bodyHtml,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'subject': subject,
    'bodyText': bodyText,
    'bodyHtml': bodyHtml,
  };
}
