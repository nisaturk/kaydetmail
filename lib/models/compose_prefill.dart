import 'email.dart';

/// Prefill data for the reply/reply-all/forward screen from
/// `GET /api/mails/{id}/compose/{kind}`.
///
/// The backend is the source of truth for recipient computation (Reply-To
/// vs. From precedence, Reply-All self-exclusion, threading headers) — the
/// UI must never recompute [to]/[cc]/[suggestedSubject] itself. See
/// docs-dev/kaydetmail-mobile-implementation-gap-spec.md §4.
class ComposePrefill {
  const ComposePrefill({
    required this.sourceMailId,
    required this.to,
    required this.cc,
    required this.suggestedSubject,
    this.inReplyToMessageId,
    this.references,
    this.originalFrom,
    this.originalDate,
    this.originalSubject,
    this.attachments = const [],
  });

  final String sourceMailId;
  final List<String> to;
  final List<String> cc;
  final String suggestedSubject;
  final String? inReplyToMessageId;
  final String? references;
  final String? originalFrom;
  final DateTime? originalDate;
  final String? originalSubject;

  /// Source mail's attachments (forward only) — metadata only, no bytes.
  /// Re-download and re-upload their content when sending; the server does
  /// not carry the bytes over by itself.
  final List<Attachment> attachments;
}
