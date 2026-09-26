import 'package:flutter/foundation.dart';

@immutable
class MailSnippet {
  const MailSnippet({
    required this.id,
    this.title,
    required this.text,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String? title;
  final String text;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MailSnippet.fromJson(Map<String, dynamic> json) => MailSnippet(
    id: json['id'] as String,
    title: json['title'] as String?,
    text: json['text'] as String? ?? '',
    sortOrder: json['sortOrder'] as int? ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  MailSnippet copyWith({
    String? accountId,
    String? title,
    String? text,
    int? sortOrder,
  }) => MailSnippet(
    id: id,
    accountId: accountId ?? this.accountId,
    title: title ?? this.title,
    text: text ?? this.text,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'text': text,
    'sortOrder': sortOrder,
  };
}
