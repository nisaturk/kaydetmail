import 'package:flutter/foundation.dart';

import '../utils/html_to_text.dart';

/// A reusable signature. Plain text only: the HTML body some older
/// signatures carry on the server is flattened to text when read
/// ([MailSignature.fromJson]) and cleared on the next save ([toJson]).
@immutable
class MailSignature {
  const MailSignature({
    required this.id,
    required this.name,
    required this.bodyText,
    required this.createdAt,
    required this.updatedAt,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String name;
  final String bodyText;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory MailSignature.fromJson(Map<String, dynamic> json) {
    final text = json['bodyText'] as String? ?? '';
    final html = json['bodyHtml'] as String?;
    return MailSignature(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      bodyText: text.trim().isEmpty && html != null && html.trim().isNotEmpty
          ? htmlToPlainText(html)
          : text,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  MailSignature copyWith({String? accountId, String? name, String? bodyText}) =>
      MailSignature(
        id: id,
        accountId: accountId ?? this.accountId,
        name: name ?? this.name,
        bodyText: bodyText ?? this.bodyText,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// `bodyHtml` is sent explicitly as null so saving a legacy HTML signature
  /// replaces it on the server instead of keeping a stale HTML alternative.
  Map<String, dynamic> toJson() => {
    'name': name,
    'bodyText': bodyText,
    'bodyHtml': null,
  };
}

@immutable
class SignatureDefaults {
  const SignatureDefaults({
    this.newMailSignatureId,
    this.replySignatureId,
    this.forwardSignatureId,
  });

  factory SignatureDefaults.fromJson(Map<String, dynamic> json) =>
      SignatureDefaults(
        newMailSignatureId: json['newMailSignatureId'] as String?,
        replySignatureId: json['replySignatureId'] as String?,
        forwardSignatureId: json['forwardSignatureId'] as String?,
      );

  final String? newMailSignatureId;
  final String? replySignatureId;
  final String? forwardSignatureId;

  Map<String, dynamic> toJson() => {
    'newMailSignatureId': newMailSignatureId,
    'replySignatureId': replySignatureId,
    'forwardSignatureId': forwardSignatureId,
  };
}

@immutable
class MailIdentity {
  const MailIdentity({
    required this.id,
    required this.emailAddress,
    this.displayName = '',
    this.replyTo,
    this.signatureId,
    this.isDefault = false,
    this.accountId = '',
  });

  final String id;
  final String accountId;
  final String emailAddress;
  final String displayName;
  final String? replyTo;
  final String? signatureId;
  final bool isDefault;

  factory MailIdentity.fromJson(Map<String, dynamic> json) => MailIdentity(
    id: json['id'] as String,
    emailAddress: json['emailAddress'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    replyTo: json['replyTo'] as String?,
    signatureId: json['signatureId'] as String?,
    isDefault: json['isDefault'] as bool? ?? false,
  );

  MailIdentity copyWith({
    String? accountId,
    String? emailAddress,
    String? displayName,
    String? replyTo,
    String? signatureId,
    bool? isDefault,
  }) => MailIdentity(
    id: id,
    accountId: accountId ?? this.accountId,
    emailAddress: emailAddress ?? this.emailAddress,
    displayName: displayName ?? this.displayName,
    replyTo: replyTo ?? this.replyTo,
    signatureId: signatureId ?? this.signatureId,
    isDefault: isDefault ?? this.isDefault,
  );

  Map<String, dynamic> toJson() => {
    'emailAddress': emailAddress,
    'displayName': displayName,
    'replyTo': replyTo,
    'signatureId': signatureId,
    'isDefault': isDefault,
  };
}
