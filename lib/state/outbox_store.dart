import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';

import '../services/mail_cache.dart';
import 'pending_send_queue.dart';

/// `waitingForNetwork` is KaydetMail-specific: entered only when a dispatch
/// attempt fails with a definite "no network path to the server" error
/// (never a timeout, which stays `uncertain` — the request may have
/// already reached the server). It is retried automatically by
/// `PendingSendQueue._scheduleNetworkRetry` without any user action, unlike
/// `failed`/`uncertain` which always require one.
enum OutboxStatus { pending, sending, waitingForNetwork, failed, uncertain }

class OutboxItem {
  const OutboxItem({
    required this.send,
    required this.status,
    required this.undoUntil,
    this.error,
  });

  final PendingSend send;
  final OutboxStatus status;
  final DateTime undoUntil;
  final String? error;
}

/// Atomic local send journal. Attachment bytes are BLOBs, not base64 in preferences.
class OutboxStore {
  OutboxStore._(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        status TEXT NOT NULL,
        undo_until_ms INTEGER NOT NULL,
        message TEXT NOT NULL,
        error TEXT
      )''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS outbox_attachments (
        send_id TEXT NOT NULL,
        position INTEGER NOT NULL,
        data BLOB NOT NULL,
        PRIMARY KEY (send_id, position)
      )''');
  }

  final CommonDatabase _db;
  bool contains(String id) =>
      _db.select('SELECT 1 FROM outbox WHERE id = ? LIMIT 1', [id]).isNotEmpty;

  static Future<OutboxStore> open() async =>
      OutboxStore._((await MailCache.open()).db);

  static OutboxStore inMemory() => OutboxStore._(MailCache.inMemory().db);

  void save(OutboxItem item, {String? replacesId}) {
    _db.execute('BEGIN');
    try {
      if (replacesId != null) {
        final previous = _db.select('SELECT status FROM outbox WHERE id = ?', [
          replacesId,
        ]);
        if (previous.length != 1 ||
            previous.single['status'] != OutboxStatus.failed.name) {
          throw StateError('Only a failed send can be replaced');
        }
      }
      _db.execute(
        '''INSERT OR REPLACE INTO outbox
           (id, account_id, status, undo_until_ms, message, error)
           VALUES (?, ?, ?, ?, ?, ?)''',
        [
          item.send.id,
          item.send.fromAccountId ?? '',
          item.status.name,
          item.undoUntil.millisecondsSinceEpoch,
          jsonEncode(item.send.toJson(includeAttachmentBytes: false)),
          item.error,
        ],
      );
      _db.execute('DELETE FROM outbox_attachments WHERE send_id = ?', [
        item.send.id,
      ]);
      final insert = _db.prepare(
        'INSERT INTO outbox_attachments (send_id, position, data) VALUES (?, ?, ?)',
      );
      try {
        for (var index = 0; index < item.send.attachments.length; index++) {
          final bytes = item.send.attachments[index].bytes;
          if (bytes != null) insert.execute([item.send.id, index, bytes]);
        }
      } finally {
        insert.close();
      }
      if (replacesId != null) {
        _db.execute('DELETE FROM outbox_attachments WHERE send_id = ?', [
          replacesId,
        ]);
        _db.execute('DELETE FROM outbox WHERE id = ?', [replacesId]);
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updateStatus(String id, OutboxStatus status, {String? error}) =>
      _db.execute('UPDATE outbox SET status = ?, error = ? WHERE id = ?', [
        status.name,
        error,
        id,
      ]);

  void remove(String id) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM outbox_attachments WHERE send_id = ?', [id]);
      _db.execute('DELETE FROM outbox WHERE id = ?', [id]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<OutboxItem> load() {
    final rows = _db.select(
      'SELECT id, status, undo_until_ms, message, error FROM outbox ORDER BY undo_until_ms DESC',
    );
    return [for (final row in rows) _decode(row)];
  }

  OutboxItem _decode(Row row) {
    final id = row['id'] as String;
    final blobs = _db.select(
      'SELECT position, data FROM outbox_attachments WHERE send_id = ?',
      [id],
    );
    final bytes = <int, Uint8List>{
      for (final blob in blobs)
        blob['position'] as int: blob['data'] as Uint8List,
    };
    return OutboxItem(
      send: PendingSend.fromJson(
        jsonDecode(row['message'] as String) as Map<String, dynamic>,
        attachmentBytes: bytes,
      ),
      status: OutboxStatus.values.byName(row['status'] as String),
      undoUntil: DateTime.fromMillisecondsSinceEpoch(
        row['undo_until_ms'] as int,
      ),
      error: row['error'] as String?,
    );
  }
}
