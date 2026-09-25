import 'package:flutter/foundation.dart';

import 'email.dart';

@immutable
class ScheduledSendAttachmentInfo {
  const ScheduledSendAttachmentInfo({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  factory ScheduledSendAttachmentInfo.fromJson(Map<String, dynamic> json) =>
      ScheduledSendAttachmentInfo(
        id: json['id'] as String,
        name: json['fileName'] as String? ?? '',
        mimeType: json['contentType'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final String? mimeType;
  final int sizeBytes;
}

@immutable
class ScheduledSendDetail {
  const ScheduledSendDetail({
    required this.id,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    this.bodyText,
    this.bodyHtml,
    required this.sendAt,
    this.attachments = const [],
  });

  factory ScheduledSendDetail.fromJson(Map<String, dynamic> json) =>
      ScheduledSendDetail(
        id: json['id'] as String,
        to: _addresses(json['to']),
        cc: _addresses(json['cc']),
        bcc: _addresses(json['bcc']),
        subject: json['subject'] as String? ?? '',
        bodyText: json['bodyText'] as String?,
        bodyHtml: json['bodyHtml'] as String?,
        sendAt: DateTime.parse(json['sendAtUtc'] as String).toLocal(),
        attachments: [
          for (final item in (json['attachments'] as List? ?? const []))
            ScheduledSendAttachmentInfo.fromJson(
              item as Map<String, dynamic>,
            ),
        ],
      );

  final String id;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String? bodyText;
  final String? bodyHtml;
  final DateTime sendAt;
  final List<ScheduledSendAttachmentInfo> attachments;

  List<Attachment> toEditAttachments() => [
    for (final info in attachments)
      Attachment(
        id: info.id,
        name: info.name,
        sizeBytes: info.sizeBytes,
        mimeType: info.mimeType,
      ),
  ];

  static List<String> _addresses(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final entry in value)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }
}
