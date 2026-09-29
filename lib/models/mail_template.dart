import 'package:flutter/foundation.dart';

import '../utils/html_to_text.dart';

/// A reusable text ("hazır metin"). Plain text only: the HTML body older
/// templates may carry on the server is flattened to text when read
/// ([MailTemplate.fromJson]) and cleared on the next save ([toJson]).
@immutable
class MailTemplate {
  const MailTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.createdAt,
    required this.updatedAt,
    this.bodyText,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String name;
  final String subject;
  final String? bodyText;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MailTemplate.fromJson(Map<String, dynamic> json) {
    final text = json['bodyText'] as String?;
    final html = json['bodyHtml'] as String?;
    return MailTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      subject: json['subject'] as String? ?? '',
      bodyText:
          (text == null || text.trim().isEmpty) &&
              html != null &&
              html.trim().isNotEmpty
          ? htmlToPlainText(html)
          : text,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  MailTemplate copyWith({
    String? accountId,
    String? name,
    String? subject,
    String? bodyText,
  }) => MailTemplate(
    id: id,
    accountId: accountId ?? this.accountId,
    name: name ?? this.name,
    subject: subject ?? this.subject,
    bodyText: bodyText ?? this.bodyText,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// `bodyHtml` is sent explicitly as null so saving a legacy HTML template
  /// replaces it on the server instead of keeping a stale HTML alternative.
  Map<String, dynamic> toJson() => {
    'name': name,
    'subject': subject,
    'bodyText': bodyText,
    'bodyHtml': null,
  };
}
