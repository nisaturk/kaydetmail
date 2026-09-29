import 'dart:async';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../services/api_exception.dart';
import '../../utils/idempotency_key.dart';
import 'account_session.dart';
import 'repository_context.dart';

/// Drafts: saved locally first (encrypted queue, instant), then written to
/// the IMAP Drafts folder in the background one write at a time. Tracks the
/// id changes `PUT /drafts/{id}` causes and drafts the server stored but
/// could not name yet, so callers holding an old id keep working.
class DraftModule {
  DraftModule(this._ctx);

  final RepositoryContext _ctx;

  /// Tail of the draft write queue — see [_serializeDraftWrite].
  Future<void> _draftWrites = Future.value();
  final Map<String, void Function(Email)> _draftFailureCallbacks = {};
  final _draftSyncFailureController = StreamController<Email>.broadcast();

  Stream<Email> get draftSyncFailures => _draftSyncFailureController.stream;

  void detachDraftSyncFailureHandler(String draftId) {
    _draftFailureCallbacks.remove(draftId);
  }

  bool _draftSyncScheduled = false;
  bool _draftSyncRequested = false;

  void scheduleSync() {
    if (_draftSyncScheduled) {
      _draftSyncRequested = true;
      return;
    }
    _draftSyncScheduled = true;
    unawaited(
      Future<void>.delayed(Duration.zero, () async {
        try {
          await _syncQueuedDrafts();
        } finally {
          _draftSyncScheduled = false;
          if (_draftSyncRequested) {
            _draftSyncRequested = false;
            scheduleSync();
          }
        }
      }),
    );
  }

  Future<void> _syncQueuedDrafts() async {
    final cache = _ctx.cache;
    if (cache == null) return;
    for (final session in _ctx.registry.sessions.values) {
      for (final local in cache.loadDraftQueue(session.account.id)) {
        try {
          final saved = await _serializeDraftWrite(
            () => _writeDraft(
              to: local.recipients,
              cc: local.cc,
              bcc: local.bcc,
              subject: local.subject,
              body: local.bodyText,
              bodyHtml: local.bodyHtml,
              attachments: local.attachments,
              from: local.senderEmail,
              fromAccountId: session.account.id,
              threadId: local.threadId,
              inReplyToId: local.inReplyToId,
              identityId: local.headers['draftIdentityId'],
              draftId: local.id.startsWith('local-draft-') ? null : local.id,
            ),
          );
          final latest = session.emails[MailFolder.drafts]?.firstWhere(
            (e) => e.id == local.id,
            orElse: () => local,
          );
          if (latest != null &&
              !cache.queuedDraftMatches(session.account.id, latest)) {
            scheduleSync();
            continue;
          }
          final drafts = session.emails[MailFolder.drafts];
          if (saved.id != local.id) {
            drafts?.removeWhere((e) => e.id == saved.id);
          }
          final index = drafts?.indexWhere((e) => e.id == local.id) ?? -1;
          if (index >= 0) drafts![index] = saved;
          if (saved.id != local.id) _draftIdSuccessor[local.id] = saved.id;
          cache.removeQueuedDraft(session.account.id, local.id);
          _draftFailureCallbacks.remove(local.id);
          _ctx.notify();
        } catch (_) {
          final latest = session.findLoaded(local.id);
          if (latest != null &&
              !cache.queuedDraftMatches(session.account.id, latest)) {
            scheduleSync();
            continue;
          }
          final callback = _draftFailureCallbacks[local.id];
          if (callback != null) {
            callback(local);
          } else {
            _draftSyncFailureController.add(local);
          }
          Future<void>.delayed(const Duration(seconds: 15), () {
            scheduleSync();
          });
          return;
        }
      }
    }
  }

  /// Old draft id -> the id `PUT /drafts/{id}` replaced it with.
  final Map<String, String> _draftIdSuccessor = {};

  /// Drafts the server stored but couldn't name yet (`reconciliationPending`),
  /// keyed by the id the caller holds — a local placeholder after a create,
  /// or the retired id after an update. Resolved into [_draftIdSuccessor]
  /// when a Drafts refresh shows the matching server copy.
  final Map<String, ({Email written, Set<String> baseline})> _unresolvedDrafts =
      {};

  /// [baseline] is every draft id listed before the write, so only a copy
  /// that appeared afterwards can be matched to it.
  void _trackUnresolvedDraft(
    AccountSession session,
    Email written,
    Set<String> baseline,
  ) {
    _unresolvedDrafts[written.id] = (written: written, baseline: baseline);
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 3),
        () => _ctx.refreshFolderMail(session, MailFolder.drafts),
      ).catchError((_) {}),
    );
  }

  /// Maps each unresolved draft to the server draft that appeared after it
  /// was written, with the same subject and recipients (newest first).
  void resolveFrom(List<Email> listed) {
    if (_unresolvedDrafts.isEmpty) return;
    final claimed = _draftIdSuccessor.values.toSet();
    final candidates = listed.where((e) => !claimed.contains(e.id)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final MapEntry(key: id, value: pending)
        in _unresolvedDrafts.entries.toList()) {
      final written = pending.written;
      final notBefore = written.timestamp.subtract(const Duration(minutes: 2));
      final match = candidates
          .where(
            (e) =>
                !pending.baseline.contains(e.id) &&
                e.accountId == written.accountId &&
                _draftSubjectKey(e.subject) ==
                    _draftSubjectKey(written.subject) &&
                e.recipients.toSet().containsAll(written.recipients) &&
                written.recipients.toSet().containsAll(e.recipients) &&
                !e.timestamp.isBefore(notBefore),
          )
          .firstOrNull;
      if (match == null) continue;
      candidates.remove(match);
      _draftIdSuccessor[id] = match.id;
      _unresolvedDrafts.remove(id);
    }
  }

  /// The backend stores a blank subject as "(no subject)".
  static String _draftSubjectKey(String subject) =>
      subject.trim().isEmpty ? '(no subject)' : subject.trim();

  /// The server id to write to for [id]. A draft still awaiting
  /// reconciliation triggers one Drafts refresh; if the server copy is
  /// still unnamed after it, writing now would 404, so this fails clearly.
  Future<String> _serverDraftId(String id) async {
    var latest = _latestDraftId(id);
    final pending = _unresolvedDrafts[latest];
    if (pending == null) return latest;
    final session =
        _ctx.registry.sessions[pending.written.accountId] ??
        _ctx.registry.primary;
    await _ctx.refreshFolderMail(session, MailFolder.drafts);
    latest = _latestDraftId(id);
    if (_unresolvedDrafts.containsKey(latest)) {
      throw const ApiException(status: 409, code: 'draft_not_reconciled');
    }
    return latest;
  }

  /// Runs draft writes one at a time. Two overlapping saves of the same
  /// draft (a double-tapped "Taslağı Kaydet") would otherwise both `PUT`
  /// the same id: each re-APPENDs a copy and only one can retire the
  /// original, leaving duplicates behind.
  Future<T> _serializeDraftWrite<T>(Future<T> Function() write) {
    final result = _draftWrites.then((_) => write());
    _draftWrites = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// The current id of a draft that may have been re-created under a new id
  /// by an earlier update — callers holding the id they opened keep working.
  String _latestDraftId(String id) {
    var current = id;
    for (var next = _draftIdSuccessor[current]; next != null;) {
      current = next;
      next = _draftIdSuccessor[current];
    }
    return current;
  }

  Future<Email> saveDraft({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String body = '',
    String? bodyHtml,
    List<Attachment> attachments = const [],
    String? from,
    String? fromAccountId,
    String? threadId,
    String? inReplyToId,
    String? identityId,
    String? draftId,
    void Function(Email draft)? onSyncFailure,
  }) async {
    final cache = _ctx.cache;
    if (cache == null) {
      throw StateError('Draft cache unavailable');
    }
    final resolvedDraftId = draftId == null ? null : _latestDraftId(draftId);
    final session = resolvedDraftId != null
        ? (_ctx.registry.owning(resolvedDraftId) ??
              _ctx.registry.forCompose(
                from: from,
                fromAccountId: fromAccountId,
              ))
        : _ctx.registry.forCompose(from: from, fromAccountId: fromAccountId);
    draftId = resolvedDraftId;
    final id =
        draftId ?? 'local-draft-${DateTime.now().microsecondsSinceEpoch}';
    final drafts = session.emails.putIfAbsent(
      MailFolder.drafts,
      () => <Email>[],
    );
    final oldIndex = drafts.indexWhere((e) => e.id == id);
    final previous = oldIndex < 0 ? null : drafts[oldIndex];
    final local = Email(
      id: id,
      senderName: session.account.displayName ?? session.account.email,
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty)
          ? (previous?.threadId.isNotEmpty == true
                ? previous!.threadId
                : 't-$id')
          : threadId,
      inReplyToId: inReplyToId ?? previous?.inReplyToId,
      headers: {
        // ignore: use_null_aware_elements
        if (identityId != null) 'draftIdentityId': identityId,
      },
    );
    if (oldIndex < 0) {
      drafts.insert(0, local);
    } else {
      drafts[oldIndex] = local;
    }
    try {
      cache.queueDraft(session.account.id, local);
    } catch (_) {
      if (oldIndex < 0) {
        drafts.remove(local);
      } else {
        drafts[oldIndex] = previous!;
      }
      rethrow;
    }
    if (onSyncFailure != null) _draftFailureCallbacks[id] = onSyncFailure;
    _ctx.notify();
    scheduleSync();
    return local;
  }

  Future<Email> _writeDraft({
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subject,
    required String body,
    required String? bodyHtml,
    required List<Attachment> attachments,
    required String? from,
    required String? fromAccountId,
    required String? threadId,
    required String? inReplyToId,
    required String? identityId,
    required String? draftId,
  }) async {
    final session = draftId != null
        ? (_ctx.registry.owning(draftId) ??
              _ctx.registry.forCompose(
                from: from,
                fromAccountId: fromAccountId,
              ))
        : _ctx.registry.forCompose(from: from, fromAccountId: fromAccountId);
    // Editing an existing draft goes through PUT /drafts/{id}, which returns
    // a NEW mailId — the old id is invalid afterwards, so the cache drops it
    // and stores the draft under the new one instead of duplicating it.
    if (draftId != null) {
      final result = await session.mailService.updateDraft(
        draftId,
        to: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        bodyHtml: bodyHtml,
        attachments: attachments,
        replySourceMailId: inReplyToId,
        identityId: identityId,
      );
      final newId = result.mailId ?? draftId;
      if (newId != draftId) _draftIdSuccessor[draftId] = newId;
      final drafts = session.emails.putIfAbsent(
        MailFolder.drafts,
        () => <Email>[],
      );
      final oldIndex = drafts.indexWhere((e) => e.id == draftId);
      final previous = oldIndex >= 0 ? drafts[oldIndex] : null;
      final updated = Email(
        id: newId,
        senderName:
            session.account.displayName ??
            previous?.senderName ??
            session.account.email,
        senderEmail: from ?? session.account.email,
        recipients: to,
        cc: cc,
        bcc: bcc,
        subject: subject,
        bodyText: body,
        bodyHtml: bodyHtml,
        timestamp: DateTime.now(),
        isRead: true,
        folder: MailFolder.drafts,
        attachments: attachments,
        accountId: session.account.id,
        threadId: (threadId == null || threadId.isEmpty)
            ? (previous?.threadId.isNotEmpty == true
                  ? previous!.threadId
                  : 't-$newId')
            : threadId,
        inReplyToId: inReplyToId ?? previous?.inReplyToId,
      );
      if (result.mailId == null) {
        // Reconciliation pending: the server stored the new copy and already
        // retired the old one, but can't name the new id yet. Drop the stale
        // row and pick the real one up once the Drafts sync lands.
        final baseline = drafts.map((e) => e.id).toSet();
        if (oldIndex >= 0) drafts.removeAt(oldIndex);
        _ctx.touch();
        _ctx.notify();
        _trackUnresolvedDraft(session, updated, baseline);
        return updated;
      }
      _ctx.touch();
      if (oldIndex >= 0) {
        drafts[oldIndex] = updated;
      } else {
        drafts.insert(0, updated);
      }
      _ctx.notify();
      return updated;
    }
    final result = await session.mailService.createDraft(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      attachments: attachments,
      replySourceMailId: inReplyToId,
      identityId: identityId,
    );
    // Reconciliation can still be pending right after APPEND — fall back to
    // a local id so the draft is still usable; the next Drafts refresh maps
    // it to the server's real id (see [resolveFrom]).
    final id =
        result.mailId ?? 'draft-${DateTime.now().microsecondsSinceEpoch}';
    final email = Email(
      id: id,
      senderName: session.account.displayName ?? session.account.email,
      senderEmail: from ?? session.account.email,
      recipients: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      bodyText: body,
      bodyHtml: bodyHtml,
      timestamp: DateTime.now(),
      isRead: true,
      folder: MailFolder.drafts,
      attachments: attachments,
      accountId: session.account.id,
      threadId: (threadId == null || threadId.isEmpty) ? 't-$id' : threadId,
      inReplyToId: inReplyToId,
    );
    _ctx.touch();
    final drafts = session.emails.putIfAbsent(
      MailFolder.drafts,
      () => <Email>[],
    );
    if (result.mailId == null) {
      _trackUnresolvedDraft(session, email, drafts.map((e) => e.id).toSet());
    }
    drafts.insert(0, email);
    _ctx.notify();
    return email;
  }

  Future<void> deleteDraft(String draftId) {
    final initialSession =
        _ctx.registry.owning(draftId) ?? _ctx.registry.primary;
    if (draftId.startsWith('local-draft-')) {
      _ctx.cache?.removeQueuedDraft(initialSession.account.id, draftId);
      _draftFailureCallbacks.remove(draftId);
      _ctx.removeMany(initialSession, [draftId]);
      _ctx.notify();
      return Future.value();
    }
    final initialSnapshot = _ctx.snapshotMailLocations(initialSession, [
      draftId,
    ]);
    _ctx.removeMany(initialSession, [draftId]);
    _ctx.notify();
    return _serializeDraftWrite(() async {
      final String id;
      try {
        id = await _serverDraftId(draftId);
      } catch (_) {
        _ctx.restoreMailLocations(initialSession, initialSnapshot);
        _ctx.notify();
        rethrow;
      }
      final session = _ctx.registry.owning(id) ?? initialSession;
      final snapshot = id == draftId
          ? initialSnapshot
          : _ctx.snapshotMailLocations(session, [id]);
      if (id != draftId) {
        _ctx.removeMany(session, [id]);
        _ctx.notify();
      }
      try {
        await session.mailService.deleteDraft(id);
      } catch (_) {
        _ctx.restoreMailLocations(session, snapshot);
        _ctx.notify();
        rethrow;
      }
    });
  }

  /// Sends a draft via `POST /api/drafts/{id}/send`. A fresh
  /// `Idempotency-Key` per attempt makes a network-timeout retry safe. Never
  /// retries `delivery_unknown` automatically — the [ApiException] propagates
  /// so the UI can say "check Sent". `draftRemoved == false` still counts as
  /// sent: the draft just stays in the Drafts bucket.
  Future<Email?> sendDraft(String draftId) async {
    final session = _ctx.registry.owning(draftId) ?? _ctx.registry.primary;
    final draft = _findCached(draftId);
    final result = await session.mailService.sendDraft(
      draftId,
      idempotencyKey: newIdempotencyKey(),
    );
    if (!result.sent) return null;
    _ctx.touch();
    if (result.draftRemoved) {
      session.emails[MailFolder.drafts]?.removeWhere((e) => e.id == draftId);
    }
    final echo =
        (draft ??
                Email(
                  id: draftId,
                  senderName:
                      session.account.displayName ?? session.account.email,
                  senderEmail: session.account.email,
                  recipients: const [],
                  subject: '',
                  bodyText: '',
                  timestamp: DateTime.now(),
                  folder: MailFolder.sent,
                  accountId: session.account.id,
                ))
            .copyWith(folder: MailFolder.sent, timestamp: DateTime.now());
    session.emails
        .putIfAbsent(MailFolder.sent, () => <Email>[])
        .insert(0, echo);
    _ctx.notify();
    return echo;
  }

  Email? _findCached(String id) {
    for (final session in _ctx.registry.sessions.values) {
      for (final list in session.emails.values) {
        for (final email in list) {
          if (email.id == id) return email;
        }
      }
    }
    return null;
  }
}
