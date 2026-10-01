import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/email.dart';
import '../../models/scheduled_send.dart';
import '../../models/scheduled_send_detail.dart';
import '../../services/mail_cache.dart';
import '../../utils/idempotency_key.dart';
import 'account_session.dart';
import 'session_registry.dart';

/// Backend-owned scheduled sends: the server owns the clock, this keeps the
/// per-account list cached and routes each id to the account that owns it.
class ScheduledSendModule {
  ScheduledSendModule(this._registry, this._notify, this._cache);

  final SessionRegistry _registry;
  final VoidCallback _notify;
  final MailCache? Function() _cache;

  MailCache get _attemptCache =>
      _cache() ??
      (throw StateError('Scheduled send retry storage is unavailable'));

  String _attemptKey(MailCache cache, String accountId, String fingerprint) {
    final existing = cache.readScheduledAttemptKey(accountId, fingerprint);
    if (existing != null) return existing;
    final key = newIdempotencyKey();
    cache.saveScheduledAttemptKey(accountId, fingerprint, key);
    return key;
  }

  String _fingerprint(List<Object?> fields) =>
      sha256.convert(utf8.encode(jsonEncode(fields))).toString();

  Future<ScheduledSend> scheduleSend({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    required String body,
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? inReplyToId,
    String? identityId,
    bool requestReadReceipt = false,
    required DateTime sendAt,
  }) async {
    final session = _registry.forCompose(
      from: from,
      fromAccountId: fromAccountId,
    );
    final cache = _attemptCache;
    final fingerprint = _fingerprint([
      'create',
      session.account.id,
      to,
      cc,
      bcc,
      subject,
      body,
      bodyHtml,
      inReplyToId,
      identityId,
      requestReadReceipt,
      sendAt.toUtc().toIso8601String(),
      for (final attachment in attachments)
        if (attachment.bytes != null)
          [
            attachment.name,
            attachment.mimeType,
            sha256.convert(attachment.bytes!).toString(),
          ],
    ]);
    final key = _attemptKey(cache, session.account.id, fingerprint);
    final scheduled = await session.mailService.scheduleSend(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      attachments: attachments,
      replySourceMailId: inReplyToId,
      identityId: identityId,
      requestReadReceipt: requestReadReceipt,
      sendAtUtc: sendAt,
      idempotencyKey: key,
    );
    cache.removeScheduledAttemptKey(session.account.id, fingerprint);
    final stamped = ScheduledSend(
      id: scheduled.id,
      to: List.unmodifiable(to),
      cc: List.unmodifiable(cc),
      bcc: List.unmodifiable(bcc),
      subject: subject,
      sendAt: scheduled.sendAt,
      status: scheduled.status,
      createdAt: scheduled.createdAt,
      sentMailId: scheduled.sentMailId,
      failureReason: scheduled.failureReason,
      attemptCount: scheduled.attemptCount,
      nextAttemptAtUtc: scheduled.nextAttemptAtUtc,
      accountId: session.account.id,
    );
    session.scheduledSends = [...session.scheduledSends, stamped]
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
    _notify();
    return stamped;
  }

  AccountSession _owning(String id) {
    for (final session in _registry.sessions.values) {
      if (session.scheduledSends.any((item) => item.id == id)) {
        return session;
      }
    }
    return _registry.primary;
  }

  Future<ScheduledSendDetail> getScheduledSend(String id) =>
      _owning(id).mailService.getScheduledSend(id);

  Future<void> updateScheduledSend({
    required String id,
    required int expectedRevision,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String body = '',
    String? bodyHtml,
    required DateTime sendAt,
    List<String> keepAttachmentIds = const [],
    List<Attachment> attachments = const [],
  }) async {
    final session = _owning(id);
    await session.mailService.updateScheduledSend(
      id: id,
      expectedRevision: expectedRevision,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      sendAtUtc: sendAt,
      keepAttachmentIds: keepAttachmentIds,
      attachments: attachments,
    );
    await refreshScheduledSends();
  }

  Future<void> rescheduleFailedSend({
    required String id,
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    required String subject,
    String body = '',
    String? bodyHtml,
    List<String>? attachmentIds,
    required DateTime sendAt,
  }) async {
    final session = _owning(id);
    final cache = _attemptCache;
    final fingerprint = _fingerprint([
      'reschedule',
      session.account.id,
      id,
      to,
      cc,
      bcc,
      subject,
      body,
      bodyHtml,
      attachmentIds,
      sendAt.toUtc().toIso8601String(),
    ]);
    final key = _attemptKey(cache, session.account.id, fingerprint);
    await session.mailService.rescheduleFailedSend(
      id: id,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      attachmentIds: attachmentIds,
      sendAtUtc: sendAt,
      idempotencyKey: key,
    );
    await refreshScheduledSends();
    cache.removeScheduledAttemptKey(session.account.id, fingerprint);
  }

  Future<void> cancelScheduledSend(String id) async {
    final session = _registry.sessions.values.firstWhere(
      (s) => s.scheduledSends.any((sch) => sch.id == id),
      orElse: () => _registry.primary,
    );
    await session.mailService.cancelScheduledSend(id);
    session.scheduledSends = session.scheduledSends
        .where((s) => s.id != id)
        .toList();
    _notify();
  }

  List<ScheduledSend> getScheduledSends() {
    final result = [for (final s in _registry.scoped) ...s.scheduledSends]
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
    return List.unmodifiable(result);
  }

  Future<void> refreshScheduledSends() async {
    await Future.wait(
      _registry.scoped.map((session) async {
        final items = await session.mailService.listScheduledSends();
        session.scheduledSends = [
          for (final s in items) s.copyWith(accountId: session.account.id),
        ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));
      }),
    );
    _notify();
  }
}
