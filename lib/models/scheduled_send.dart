import 'package:flutter/foundation.dart';

/// Status of a mail queued to send at a future time (`POST
/// /api/scheduled-sends`). The backend owns the clock: a [ScheduledSend]
/// fires even if this app is closed at [sendAt].
enum ScheduledSendStatus {
  pending,
  sent,
  cancelled,
  failed;

  static ScheduledSendStatus fromApi(String value) => switch (value) {
    'Pending' => ScheduledSendStatus.pending,
    'Sent' => ScheduledSendStatus.sent,
    'Cancelled' => ScheduledSendStatus.cancelled,
    'Failed' => ScheduledSendStatus.failed,
    _ => ScheduledSendStatus.pending,
  };
}

/// A mail scheduled to send at [sendAt] (`POST /api/scheduled-sends`).
///
/// Deliberately independent of [Email] — it isn't a mail yet, has no
/// folder/thread, and only [status] `sent` ever produces one (via
/// [sentMailId]).
@immutable
class ScheduledSend {
  const ScheduledSend({
    required this.id,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.sendAt,
    required this.status,
    required this.createdAt,
    this.sentMailId,
    this.failureReason,
    this.accountId = '',
  });

  final String id;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final DateTime sendAt;
  final ScheduledSendStatus status;
  final DateTime createdAt;
  final String? sentMailId;
  final String? failureReason;

  /// Id of the [MailAccount] this was scheduled from — stamped on ingest,
  /// same convention as [Email.accountId].
  final String accountId;

  ScheduledSend copyWith({String? accountId}) => ScheduledSend(
    id: id,
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject,
    sendAt: sendAt,
    status: status,
    createdAt: createdAt,
    sentMailId: sentMailId,
    failureReason: failureReason,
    accountId: accountId ?? this.accountId,
  );

  @override
  bool operator ==(Object other) => other is ScheduledSend && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
