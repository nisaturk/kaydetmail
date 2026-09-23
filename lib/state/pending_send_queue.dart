import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

/// Snapshot of everything a send needs, captured the moment "Gönder" is
/// tapped so the fields survive the compose screen popping and can rebuild
/// an identical compose screen if the user taps "Geri Al".
@immutable
class PendingSend {
  const PendingSend({
    required this.id,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    this.attachments = const [],
    this.from,
    this.fromAccountId,
    this.threadId,
    this.inReplyToId,
    this.draftId,
  });

  final String id;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String body;
  final List<Attachment> attachments;
  final String? from;
  final String? fromAccountId;
  final String? threadId;
  final String? inReplyToId;

  /// The draft this send originated from, if any — deleted only once the
  /// deferred send actually goes through, same as the old synchronous flow
  /// (a cancelled send must never lose the draft it was edited from).
  final String? draftId;
}

/// Signature of [MailRepository.sendEmail], torn off instead of requiring a
/// whole fake [MailRepository] in tests.
typedef SendEmail =
    Future<Email> Function({
      required List<String> to,
      List<String> cc,
      List<String> bcc,
      required String subject,
      required String body,
      List<Attachment> attachments,
      String? from,
      String? fromAccountId,
      String? threadId,
      String? inReplyToId,
    });

/// Holds every "Gönder" tap for [undoWindow] before it actually reaches
/// [MailRepository.sendEmail], so a mis-addressed mail can be recalled with
/// "Geri Al" on the confirmation SnackBar.
///
/// A singleton: the countdown/timer must outlive the compose screen, which
/// pops immediately after queuing (an optimistic send). Compose shows the
/// countdown SnackBar itself, right before popping, through the app's
/// single shared [ScaffoldMessenger] — that messenger instance keeps living
/// after compose's own route is gone, so both the countdown and "Geri Al"
/// keep working (see `_ComposeScreenState._send`).
class PendingSendQueue {
  PendingSendQueue._();

  static final PendingSendQueue instance = PendingSendQueue._();

  static const Duration undoWindow = Duration(seconds: 8);

  final Map<String, Timer> _timers = {};
  int _sequence = 0;

  /// A fresh id for a new pending send.
  String nextId() =>
      'pending-send-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  /// True while [id] is still counting down (not yet sent or cancelled).
  bool isPending(String id) => _timers.containsKey(id);

  /// Queues [send]; fires the real [MailRepository.sendEmail] after
  /// [undoWindow] unless [cancel] is called first.
  ///
  /// [sendEmail]/[deleteDraft] default to [AppConfig.mailRepository]'s
  /// methods and only need overriding in tests. [messenger], if given and
  /// still mounted when the deferred send fails, surfaces a friendly error
  /// — best effort, since compose is long gone by then and nothing else is
  /// watching.
  void enqueue(
    PendingSend send, {
    SendEmail? sendEmail,
    Future<void> Function(String draftId)? deleteDraft,
    ScaffoldMessengerState? messenger,
  }) {
    final doSend = sendEmail ?? AppConfig.mailRepository.sendEmail;
    final doDeleteDraft = deleteDraft ?? AppConfig.mailRepository.deleteDraft;
    _timers[send.id] = Timer(undoWindow, () async {
      _timers.remove(send.id);
      try {
        await doSend(
          to: send.to,
          cc: send.cc,
          bcc: send.bcc,
          subject: send.subject,
          body: send.body,
          attachments: send.attachments,
          from: send.from,
          fromAccountId: send.fromAccountId,
          threadId: send.threadId,
          inReplyToId: send.inReplyToId,
        );
        final draftId = send.draftId;
        if (draftId != null) {
          try {
            await doDeleteDraft(draftId);
          } catch (_) {
            // Sent already; a stale draft row is harmless and reconciles
            // on the next refresh — same rationale as the old synchronous
            // send flow.
          }
        }
      } catch (e) {
        if (messenger != null && messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Gönderilemedi: ${friendlyErrorMessage(e)}'),
            ),
          );
        }
      }
    });
  }

  /// Cancels a still-pending send (Geri Al). Returns false when it already
  /// fired or was already cancelled.
  bool cancel(String id) {
    final timer = _timers.remove(id);
    if (timer == null) return false;
    timer.cancel();
    return true;
  }

  /// Cancels every pending timer without sending — test teardown only.
  @visibleForTesting
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
