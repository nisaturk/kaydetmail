import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

/// Snapshot of everything a send needs, captured the moment "Gönder" is
/// tapped so the fields survive the compose screen popping and can rebuild
/// an identical compose screen if the user taps "Geri Al".
///
/// Also the durable persistence shape (see [toJson]/[fromJson]) written to
/// disk the moment it's queued, so a hard kill during [PendingSendQueue.
/// undoWindow] never silently loses the mail — see
/// [PendingSendQueue._persistAll]/[PendingSendQueue.recoverPersisted].
@immutable
class PendingSend {
  const PendingSend({
    required this.id,
    required this.to,
    this.cc = const [],
    this.bcc = const [],
    required this.subject,
    required this.body,
    this.bodyHtml,
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

  /// HTML alternative to [body] — see `_ComposeScreenState._bodyHtmlFor`.
  final String? bodyHtml;
  final List<Attachment> attachments;
  final String? from;

  /// The account this send was composed under, resolved once at enqueue
  /// time (see `_ComposeScreenState._resolvedFromAccountId`) instead of
  /// re-resolved by [from] at send time — if the account is later removed
  /// mid-flight, the send fails explicitly instead of silently landing on
  /// whichever account happens to be primary by then.
  final String? fromAccountId;
  final String? threadId;
  final String? inReplyToId;

  /// The draft this send originated from, if any — deleted only once the
  /// deferred send actually goes through, same as the old synchronous flow
  /// (a cancelled send must never lose the draft it was edited from).
  final String? draftId;

  /// Serializes this send for durable local storage. Attachment bytes are
  /// base64-encoded inline: pending sends are small and short-lived (gone
  /// within [PendingSendQueue.undoWindow] in the common case), so trading a
  /// little storage bloat for never losing an attachment a kill-recovered
  /// send still needs to upload is the right side of that trade.
  Map<String, dynamic> toJson() => {
    'id': id,
    'to': to,
    'cc': cc,
    'bcc': bcc,
    'subject': subject,
    'body': body,
    'bodyHtml': bodyHtml,
    'attachments': [
      for (final a in attachments)
        {
          'id': a.id,
          'name': a.name,
          'size': a.sizeBytes,
          'mime': a.mimeType,
          'bytes': a.bytes == null ? null : base64Encode(a.bytes!),
        },
    ],
    'from': from,
    'fromAccountId': fromAccountId,
    'threadId': threadId,
    'inReplyToId': inReplyToId,
    'draftId': draftId,
  };

  factory PendingSend.fromJson(Map<String, dynamic> json) => PendingSend(
    id: json['id'] as String,
    to: (json['to'] as List).cast<String>(),
    cc: (json['cc'] as List? ?? const []).cast<String>(),
    bcc: (json['bcc'] as List? ?? const []).cast<String>(),
    subject: json['subject'] as String,
    body: json['body'] as String,
    bodyHtml: json['bodyHtml'] as String?,
    attachments: [
      for (final a in (json['attachments'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        Attachment(
          id: a['id'] as String?,
          name: a['name'] as String,
          sizeBytes: a['size'] as int,
          mimeType: a['mime'] as String?,
          bytes: a['bytes'] == null
              ? null
              : base64Decode(a['bytes'] as String),
        ),
    ],
    from: json['from'] as String?,
    fromAccountId: json['fromAccountId'] as String?,
    threadId: json['threadId'] as String?,
    inReplyToId: json['inReplyToId'] as String?,
    draftId: json['draftId'] as String?,
  );
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
      String? bodyHtml,
      List<Attachment> attachments,
      String? from,
      String? fromAccountId,
      String? threadId,
      String? inReplyToId,
    });

/// One outbox failure surfaced to the user — a pending send that was
/// recovered (after a kill) or flushed (on backgrounding) but then failed to
/// actually reach the server. Not a full outbox UI: just enough that the
/// failure is never silently swallowed (see [PendingSendQueue.
/// readOutboxErrors]). The originating draft, if any, was never deleted (see
/// [PendingSendQueue._dispatch]), so the mail itself is never lost — only
/// this record of "something needs your attention" would be, without this.
@immutable
class OutboxFailure {
  const OutboxFailure({
    required this.subject,
    required this.to,
    required this.failedAt,
    required this.error,
  });

  final String subject;
  final List<String> to;
  final DateTime failedAt;
  final String error;

  Map<String, dynamic> toJson() => {
    'subject': subject,
    'to': to,
    'failedAtMs': failedAt.millisecondsSinceEpoch,
    'error': error,
  };

  factory OutboxFailure.fromJson(Map<String, dynamic> json) => OutboxFailure(
    subject: json['subject'] as String,
    to: (json['to'] as List? ?? const []).cast<String>(),
    failedAt: DateTime.fromMillisecondsSinceEpoch(json['failedAtMs'] as int),
    error: json['error'] as String,
  );
}

/// One still-counting-down (or just-recovered) send: the timer, the
/// snapshot, and the exact callbacks [PendingSendQueue.enqueue] resolved for
/// it — so [PendingSendQueue.flushPending] can fire early using the very
/// same [doSend]/[doDeleteDraft] the timer would have used.
class _PendingEntry {
  _PendingEntry({
    required this.timer,
    required this.send,
    required this.doSend,
    required this.doDeleteDraft,
    this.messenger,
  });

  final Timer timer;
  final PendingSend send;
  final SendEmail doSend;
  final Future<void> Function(String draftId) doDeleteDraft;
  final ScaffoldMessengerState? messenger;
}

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
///
/// Durability: every enqueued send is also written to [SharedPreferences]
/// (see [_persistAll]) the moment it's queued and removed again once it
/// fires or is cancelled — a `shared_preferences` JSON blob rather than a
/// SQLite table because a pending send is small, short-lived (normally gone
/// within [undoWindow]), and there's at most a handful of them at once, so
/// the extra read/write ceremony a table would need buys nothing here. This
/// class also mixes in [WidgetsBindingObserver] and registers itself once
/// (it's a permanent singleton, never disposed) purely to catch
/// backgrounding — see [didChangeAppLifecycleState]/[flushPending].
class PendingSendQueue with WidgetsBindingObserver {
  PendingSendQueue._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final PendingSendQueue instance = PendingSendQueue._();

  static const Duration undoWindow = Duration(seconds: 5);

  static const String _prefsKey = 'pending_send_queue_v1';
  static const String _outboxErrorsKey = 'pending_send_outbox_errors_v1';

  final Map<String, _PendingEntry> _entries = {};
  int _sequence = 0;

  /// A fresh id for a new pending send.
  String nextId() =>
      'pending-send-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  /// True while [id] is still counting down (not yet sent or cancelled).
  bool isPending(String id) => _entries.containsKey(id);

  /// Queues [send]; fires the real [MailRepository.sendEmail] after
  /// [undoWindow] unless [cancel] is called first, and durably persists
  /// [send] in the meantime (see class doc).
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
    final timer = Timer(undoWindow, () => unawaited(_fire(send.id)));
    _entries[send.id] = _PendingEntry(
      timer: timer,
      send: send,
      doSend: doSend,
      doDeleteDraft: doDeleteDraft,
      messenger: messenger,
    );
    unawaited(_persistAll());
  }

  Future<void> _fire(String id) async {
    final entry = _entries.remove(id);
    if (entry == null) return;
    unawaited(_persistAll());
    await _dispatch(entry.send, entry.doSend, entry.doDeleteDraft, entry.messenger);
  }

  /// Shared by the undo-window timer, [flushPending], and
  /// [recoverPersisted]: actually calls [doSend], retires the originating
  /// draft on success, and records an [OutboxFailure] (plus best-effort
  /// SnackBar) on failure — the draft is simply never deleted in that case,
  /// so it stays right where "Geri Al" would have restored it.
  Future<void> _dispatch(
    PendingSend send,
    SendEmail doSend,
    Future<void> Function(String draftId) doDeleteDraft,
    ScaffoldMessengerState? messenger,
  ) async {
    try {
      await doSend(
        to: send.to,
        cc: send.cc,
        bcc: send.bcc,
        subject: send.subject,
        body: send.body,
        bodyHtml: send.bodyHtml,
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
      await _recordOutboxFailure(send, e);
    }
  }

  /// Cancels a still-pending send (Geri Al). Returns false when it already
  /// fired or was already cancelled.
  bool cancel(String id) {
    final entry = _entries.remove(id);
    if (entry == null) return false;
    entry.timer.cancel();
    unawaited(_persistAll());
    return true;
  }

  /// Cancels every pending timer without sending — test teardown only.
  @visibleForTesting
  void cancelAll() {
    for (final entry in _entries.values) {
      entry.timer.cancel();
    }
    _entries.clear();
    unawaited(_persistAll());
  }

  /// Sends every still-counting-down pending send right now instead of
  /// waiting for its timer, using the exact callbacks each was queued with.
  /// Called when the app is about to leave the foreground (see
  /// [didChangeAppLifecycleState]) so backgrounding never silently drops a
  /// queued send — the whole point of the undo window is a few seconds of
  /// visible countdown, not a place for mail to quietly vanish.
  Future<void> flushPending() async {
    final ids = _entries.keys.toList();
    for (final id in ids) {
      final entry = _entries.remove(id);
      if (entry == null) continue;
      entry.timer.cancel();
      unawaited(_persistAll());
      await _dispatch(entry.send, entry.doSend, entry.doDeleteDraft, entry.messenger);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flushPending());
    }
  }

  // --- Durability across process death ---------------------------------

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    if (_entries.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    final json = jsonEncode([
      for (final e in _entries.values) e.send.toJson(),
    ]);
    await prefs.setString(_prefsKey, json);
  }

  /// Recovers pending sends a previous run persisted but never finished —
  /// the app was killed mid undo-window, or mid [flushPending] itself.
  /// Best-effort: each is sent immediately; a failure is recorded as an
  /// [OutboxFailure] instead of silently dropping the mail. Call once at
  /// startup, after the session is restored (a pending send needs an
  /// active account to resolve against — see
  /// `_AuthGateState._setAuthenticated`).
  ///
  /// [sendEmail]/[deleteDraft] default to [AppConfig.mailRepository]'s
  /// methods, same as [enqueue] — only overridden in tests.
  Future<void> recoverPersisted({
    SendEmail? sendEmail,
    Future<void> Function(String draftId)? deleteDraft,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    // Claim immediately so a crash mid-recovery can't replay the same sends
    // on the next launch too.
    await prefs.remove(_prefsKey);
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }
    final doSend = sendEmail ?? AppConfig.mailRepository.sendEmail;
    final doDeleteDraft = deleteDraft ?? AppConfig.mailRepository.deleteDraft;
    for (final item in decoded) {
      final send = PendingSend.fromJson(item as Map<String, dynamic>);
      await _dispatch(send, doSend, doDeleteDraft, null);
    }
  }

  Future<void> _recordOutboxFailure(PendingSend send, Object error) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_outboxErrorsKey) ?? const [];
    final failure = OutboxFailure(
      subject: send.subject,
      to: send.to,
      failedAt: DateTime.now(),
      error: friendlyErrorMessage(error),
    );
    await prefs.setStringList(_outboxErrorsKey, [
      ...existing,
      jsonEncode(failure.toJson()),
    ]);
  }

  /// Every outbox failure recorded since the last [clearOutboxErrors] —
  /// meant to be surfaced as a SnackBar the next time a relevant screen
  /// opens (see `_AuthGateState`). Not a full outbox UI — just enough that a
  /// failed recovery/flush send is never silently swallowed.
  static Future<List<OutboxFailure>> readOutboxErrors() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_outboxErrorsKey) ?? const [];
    return [
      for (final item in raw)
        OutboxFailure.fromJson(jsonDecode(item) as Map<String, dynamic>),
    ];
  }

  static Future<void> clearOutboxErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_outboxErrorsKey);
  }
}
