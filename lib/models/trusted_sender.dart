import 'package:flutter/foundation.dart';

enum TrustedSenderKind {
  sender('Sender'),
  domain('Domain');

  const TrustedSenderKind(this.apiValue);

  final String apiValue;

  static TrustedSenderKind fromApi(String? value) =>
      value == 'Domain' ? TrustedSenderKind.domain : TrustedSenderKind.sender;
}

@immutable
class TrustedSender {
  const TrustedSender({
    required this.id,
    required this.kind,
    required this.value,
    required this.createdAt,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final TrustedSenderKind kind;
  final String value;
  final DateTime createdAt;

  factory TrustedSender.fromJson(Map<String, dynamic> json) => TrustedSender(
    id: json['id'] as String,
    kind: TrustedSenderKind.fromApi(json['kind'] as String?),
    value: json['value'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  TrustedSender copyWith({String? accountId}) => TrustedSender(
    id: id,
    accountId: accountId ?? this.accountId,
    kind: kind,
    value: value,
    createdAt: createdAt,
  );
}
