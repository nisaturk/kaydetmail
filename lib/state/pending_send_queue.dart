import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import 'app_settings_controller.dart';
import '../repositories/mail_repository.dart';
import '../services/api_exception.dart';
import '../utils/error_messages.dart';
import 'outbox_store.dart';

@immutable
class SendProgress {
  const SendProgress(this.sent, this.total);

  final int sent;
  final int total;
  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0, 1);
}

/// Complete send snapshot. Metadata lives in the outbox journal; attachment
/// bytes are stored separately as SQLite BLOBs.
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
    this.identityId,
    this.requestReadReceipt = false,
    this.requestDeliveryReceipt = false,
    this.draftId,
    this.idempotencyKey,
  });

  final String id;
  final String? idempotencyKey;
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
  final String? identityId;
  final bool requestReadReceipt;
  final bool requestDeliveryReceipt;

  /// The draft this send originated from, if any — deleted only once the
  /// deferred send actually goes through, same as the old synchronous flow
  /// (a cancelled send must never lose the draft it was edited from).
  final String? draftId;

  /// The outbox stores attachment bytes as SQLite BLOBs instead of JSON.
  Map<String, dynamic> toJson({bool includeAttachmentBytes = true}) => {
    'id': id,
    'idempotencyKey': idempotencyKey,
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
          'bytes': includeAttachmentBytes && a.bytes != null
              ? base64Encode(a.bytes!)
              : null,
        },
    ],
    'from': from,
    'fromAccountId': fromAccountId,
    'threadId': threadId,
    'inReplyToId': inReplyToId,
    'identityId': identityId,
    'requestReadReceipt': requestReadReceipt,
    'requestDeliveryReceipt': requestDeliveryReceipt,
    'draftId': draftId,
  };

  factory PendingSend.fromJson(
    Map<String, dynamic> json, {
    Map<int, Uint8List> attachmentBytes = const {},
  }) => PendingSend(
    id: json['id'] as String,
    idempotencyKey: json['idempotencyKey'] as String?,
    to: (json['to'] as List).cast<String>(),
    cc: (json['cc'] as List? ?? const []).cast<String>(),
    bcc: (json['bcc'] as List? ?? const []).cast<String>(),
    subject: json['subject'] as String,
    body: json['body'] as String,
    bodyHtml: json['bodyHtml'] as String?,
    attachments: [
      for (final (index, a)
          in (json['attachments'] as List? ?? const [])
              .cast<Map<String, dynamic>>()
              .indexed)
        Attachment(
          id: a['id'] as String?,
          name: a['name'] as String,
          sizeBytes: a['size'] as int,
          mimeType: a['mime'] as String?,
          bytes:
              attachmentBytes[index] ??
              (a['bytes'] == null ? null : base64Decode(a['bytes'] as String)),
        ),
    ],
    from: json['from'] as String?,
    fromAccountId: json['fromAccountId'] as String?,
    threadId: json['threadId'] as String?,
    inReplyToId: json['inReplyToId'] as String?,
    identityId: json['identityId'] as String?,
    requestReadReceipt: json['requestReadReceipt'] as bool? ?? false,
    requestDeliveryReceipt: json['requestDeliveryReceipt'] as bool? ?? false,
    draftId: json['draftId'] as String?,
  );
}

typedef SendEmail = Future<Email> Function({
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
  String? identityId,
  bool requestReadReceipt,
  bool requestDeliveryReceipt,
  String? idempotencyKey,
  void Function(int sent, int total)? onProgress,
  Future<void>? abortTrigger,
});

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

/// Keeps the complete send and its attachments until delivery is confirmed.
/// A process killed while a request is in flight leaves an uncertain item for
/// the user to inspect; it is never silently retried with a new key.
class PendingSendQueue with WidgetsBindingObserver {
  PendingSendQueue._() {
    WidgetsBinding.instance.addObserver(this);
  }

  PendingSendQueue.forTest(OutboxStore store)
    : _storeFuture = Future.value(store);

  static final PendingSendQueue instance = PendingSendQueue._();
  static Duration get undoWindow =>
      AppSettingsController.instance.undoSendDelay.duration ?? Duration.zero;

  static const String _legacyPrefsKey = 'pending_send_queue_v1';

  /// Same cadence as `ApiMailRepository._scheduleReconnectRetry` — no
  /// connectivity package in this app, so "network is back" is detected by
  /// simply trying again on a timer instead of listening for an OS event.
  static const Duration _networkRetryInterval = Duration(seconds: 15);

  Future<OutboxStore>? _storeFuture;
  OutboxStore? _loadedStore;
  final Map<String, _PendingEntry> _entries = {};
  final Set<String> _inFlight = {};
  final ValueNotifier<Map<String, SendProgress>> uploadProgress = ValueNotifier(
    const {},
  );
  final Map<String, Completer<void>> _uploadAborts = {};
  final Map<String, SendProgress> _currentProgress = {};
  Timer? _networkRetryTimer;
  @visibleForTesting
  void useStoreForTest(OutboxStore store) {
    cancelAll();
    _storeFuture = Future.value(store);
    _loadedStore = store;
  }

  Future<OutboxStore> get _store async =>
      _loadedStore ??= await (_storeFuture ??= OutboxStore.open());

  String nextId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  bool isPending(String id) => _entries.containsKey(id);

  /// Persist before showing undo or closing compose. A failed disk write
  /// leaves the original compose screen intact.
  Future<void> enqueue(
    PendingSend send, {
    SendEmail? sendEmail,
    Future<void> Function(String draftId)? deleteDraft,
    ScaffoldMessengerState? messenger,
    String? replacesId,
  }) async {
    final store = await _store;
    if (store.contains(send.id)) throw StateError('Send already queued');
    store.save(
      OutboxItem(
        send: send,
        status: OutboxStatus.pending,
        undoUntil: DateTime.now().add(undoWindow),
      ),
      replacesId: replacesId,
    );
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
  }

  Future<void> _fire(String id) async {
    final entry = _entries.remove(id);
    if (entry == null) return;
    entry.timer.cancel();
    await _dispatch(
      entry.send,
      entry.doSend,
      entry.doDeleteDraft,
      entry.messenger,
    );
  }

  Future<void> _dispatch(
    PendingSend send,
    SendEmail doSend,
    Future<void> Function(String draftId) doDeleteDraft,
    ScaffoldMessengerState? messenger,
  ) async {
    if (!_inFlight.add(send.id)) return;
    late final OutboxStore store;
    try {
      store = await _store;
      store.updateStatus(send.id, OutboxStatus.sending);
    } catch (error) {
      _inFlight.remove(send.id);
      if (messenger != null && messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Giden Kutusu kaydedilemedi: ${friendlyErrorMessage(error)}',
            ),
          ),
        );
      }
      rethrow;
    }
    final abort = Completer<void>();
    _uploadAborts[send.id] = abort;
    _currentProgress.remove(send.id);
    _publishProgress();
    var uploadCancelled = false;
    var lastSnackPercent = -10;
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
        identityId: send.identityId,
        requestReadReceipt: send.requestReadReceipt,
        requestDeliveryReceipt: send.requestDeliveryReceipt,
        idempotencyKey: send.idempotencyKey ?? send.id,
        onProgress: (sent, total) {
          _currentProgress[send.id] = SendProgress(sent, total);
          _publishProgress();
          if (send.attachments.isNotEmpty &&
              total > 0 &&
              messenger != null &&
              messenger.mounted) {
            final percent = (sent * 100 ~/ total).clamp(0, 100);
            if (percent == 100 || percent - lastSnackPercent >= 10) {
              lastSnackPercent = percent;
              messenger
                ..removeCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('Ek yükleniyor: $percent%'),
                    duration: const Duration(seconds: 3),
                  ),
                );
            }
          }
        },
        abortTrigger: abort.future,
      );
      store.remove(send.id);
      if (send.draftId != null) {
        try {
          await doDeleteDraft(send.draftId!);
        } catch (_) {
          // Delivery is confirmed; a stale draft is safer than resending.
        }
      }
    } catch (error) {
      // A definite "never reached the server" network failure is safe to
      // retry automatically with the same idempotency key — nothing was
      // sent. A timeout or interrupted delivery stays `uncertain`: the
      // request may already have reached the server, so only the user may
      // decide to retry (see the `uncertain` test coverage below).
      final networkUnavailable =
          error is ApiException && error.code == 'network_unavailable';
      uploadCancelled =
          abort.isCompleted ||
          (error is ApiException && error.code == 'upload_cancelled');
      final uncertain =
          !networkUnavailable &&
          !uploadCancelled &&
          error is! SendBeforeDeliveryException &&
          (error is! ApiException ||
              error.isTransient ||
              const [
                'delivery_unknown',
                'send_in_progress',
                'idempotency_conflict',
              ].contains(error.code));
      final status = uploadCancelled
          ? OutboxStatus.failed
          : networkUnavailable
          ? OutboxStatus.waitingForNetwork
          : uncertain
          ? OutboxStatus.uncertain
          : OutboxStatus.failed;
      store.updateStatus(
        send.id,
        status,
        error: uploadCancelled
            ? 'Gönderim iptal edildi.'
            : friendlyErrorMessage(error),
      );
      if (networkUnavailable) _scheduleNetworkRetry();
      if (messenger != null && messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              uploadCancelled
                  ? 'Gönderim iptal edildi.'
                  : networkUnavailable
                  ? 'İnternet bağlantısı yok. Bağlantı gelince otomatik gönderilecek.'
                  : uncertain
                  ? 'Mesaj gönderilmiş olabilir. Giden Kutusu ve Gönderilenler’i kontrol edin.'
                  : 'Gönderilemedi. Mesaj Giden Kutusu’nda saklandı.',
            ),
          ),
        );
      }
    } finally {
      _inFlight.remove(send.id);
      _uploadAborts.remove(send.id);
      _currentProgress.remove(send.id);
      _publishProgress();
    }
  }

  void _publishProgress() {
    uploadProgress.value = Map.unmodifiable(_currentProgress);
  }

  bool cancelUpload(String id) {
    final progress = _currentProgress[id];
    final abort = _uploadAborts[id];
    if (progress == null ||
        progress.sent >= progress.total ||
        abort == null ||
        abort.isCompleted) {
      return false;
    }
    abort.complete();
    return true;
  }

  /// Starts (or leaves running) a 15s poll that redispatches every
  /// `waitingForNetwork` item — a no-op call while it is already running.
  /// Stops itself once none remain, so it never spins forever after the
  /// last offline send finally goes through or is discarded.
  void _scheduleNetworkRetry() {
    _networkRetryTimer ??= Timer.periodic(
      _networkRetryInterval,
      (_) => unawaited(_retryWaitingForNetwork()),
    );
  }

  Future<void> _retryWaitingForNetwork() async {
    final store = await _store;
    final waiting = store
        .load()
        .where((item) => item.status == OutboxStatus.waitingForNetwork)
        .toList();
    if (waiting.isEmpty) {
      _networkRetryTimer?.cancel();
      _networkRetryTimer = null;
      return;
    }
    final doSend = AppConfig.mailRepository.sendEmail;
    final doDeleteDraft = AppConfig.mailRepository.deleteDraft;
    for (final item in waiting) {
      if (_inFlight.contains(item.send.id)) continue;
      await _dispatch(item.send, doSend, doDeleteDraft, null);
    }
  }

  bool cancel(String id) {
    final entry = _entries[id];
    if (entry == null || _loadedStore == null) return false;
    _loadedStore!.remove(id);
    entry.timer.cancel();
    _entries.remove(id);
    return true;
  }

  @visibleForTesting
  void cancelAll() {
    for (final entry in _entries.values) {
      entry.timer.cancel();
    }
    _entries.clear();
    _networkRetryTimer?.cancel();
    _networkRetryTimer = null;
  }

  Future<void> flushPending() async {
    for (final id in _entries.keys.toList()) {
      await _fire(id);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(flushPending());
    }
  }

  Future<List<OutboxItem>> items() async => (await _store).load();

  /// A confirmed pre-send failure, or a send still waiting for network, is
  /// eligible for manual retry (same payload and idempotency key). Unknown
  /// delivery requires manual inspection instead — see `OutboxScreen`.
  Future<void> retry(String id) async {
    final items = await this.items();
    final item = items.where((item) => item.send.id == id).single;
    if (item.status != OutboxStatus.failed &&
        item.status != OutboxStatus.waitingForNetwork) {
      throw StateError(
        'Only failed or waiting-for-network sends may be retried',
      );
    }
    await _dispatch(
      item.send,
      AppConfig.mailRepository.sendEmail,
      AppConfig.mailRepository.deleteDraft,
      null,
    );
  }

  Future<void> discard(String id) async {
    final store = await _store;
    if (_inFlight.contains(id)) {
      throw StateError('An active send cannot be discarded');
    }
    final item = store.load().where((item) => item.send.id == id).single;
    if (item.status == OutboxStatus.pending ||
        item.status == OutboxStatus.sending) {
      throw StateError('An active send cannot be discarded');
    }
    store.remove(id);
  }

  /// Import a previous version's pending messages before retiring its key.
  Future<void> recoverPersisted({
    SendEmail? sendEmail,
    Future<void> Function(String draftId)? deleteDraft,
  }) async {
    final store = await _store;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyPrefsKey);
    if (raw != null) {
      final existingIds = store.load().map((item) => item.send.id).toSet();
      for (final value in jsonDecode(raw) as List<dynamic>) {
        final json = value as Map<String, dynamic>;
        json['idempotencyKey'] ??= nextId();
        final send = PendingSend.fromJson(json);
        if (existingIds.add(send.id)) {
          store.save(
            OutboxItem(
              send: send,
              status: OutboxStatus.pending,
              undoUntil: DateTime.now(),
            ),
          );
        }
      }
      await prefs.remove(_legacyPrefsKey);
    }
    final doSend = sendEmail ?? AppConfig.mailRepository.sendEmail;
    final doDeleteDraft = deleteDraft ?? AppConfig.mailRepository.deleteDraft;
    for (final item in store.load()) {
      if (_entries.containsKey(item.send.id) ||
          _inFlight.contains(item.send.id)) {
        continue;
      }
      if (item.status == OutboxStatus.sending) {
        store.updateStatus(
          item.send.id,
          OutboxStatus.uncertain,
          error: 'Mesaj gönderilmiş olabilir. Gönderilenler’i kontrol edin.',
        );
      } else if (item.status == OutboxStatus.pending) {
        final remaining = item.undoUntil.difference(DateTime.now());
        if (remaining.isNegative) {
          await _dispatch(item.send, doSend, doDeleteDraft, null);
        } else {
          final timer = Timer(remaining, () => unawaited(_fire(item.send.id)));
          _entries[item.send.id] = _PendingEntry(
            timer: timer,
            send: item.send,
            doSend: doSend,
            doDeleteDraft: doDeleteDraft,
          );
        }
      }
    }
    if (store.load().any(
      (item) => item.status == OutboxStatus.waitingForNetwork,
    )) {
      _scheduleNetworkRetry();
    }
  }
}
