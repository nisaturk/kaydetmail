import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';

import 'mail_cache.dart';

/// One offline-queued mail mutation waiting to reach the backend — see
/// [LocalMailFlagsStore.queueMutation]/`ApiMailRepository._replayQueuedMutations`.
class QueuedMutation {
  const QueuedMutation({
    required this.mailId,
    required this.operation,
    this.folderId,
    required this.queuedAtMs,
  });

  final String mailId;

  /// The bulk-action verb this replays as: `read`, `unread`, `star`,
  /// `unstar`, `archive`, `trash`, `restore`, or `move`.
  final String operation;

  /// Target folder id — only set (and only meaningful) for `move`.
  final String? folderId;
  final int queuedAtMs;
}

/// Mutations in the same category are mutually exclusive for one mail — a
/// later queued mutation in the same category replaces the earlier one
/// instead of stacking, so e.g. read→unread→read collapses to a single
/// replayed `read`, and archive→trash collapses to a single `trash` (see
/// spec docs-dev §8 "Replay kuralları").
String mutationCategoryFor(String operation) => switch (operation) {
  'read' || 'unread' => 'read_state',
  'star' || 'unstar' => 'star_state',
  'archive' || 'trash' || 'restore' || 'move' => 'location',
  _ => operation,
};

/// Local cache for mail state, in the on-device SQLite database
/// ([MailCache]).
///
/// Pin/snooze/labels are synced through the backend now (see
/// [ApiMailRepository]); this store is their offline-read fallback and
/// write-behind mirror, re-seeded from the server on every successful
/// fetch. "Replied"/"forwarded" mark the moment the user opened the
/// reply/forward compose screen and have no backend equivalent, so they
/// stay purely local. Everything is scoped per account so switching
/// accounts never leaks one inbox's state into another's.
class LocalMailFlagsStore {
  LocalMailFlagsStore(this._accountId, MailCache cache) : _db = cache.db;

  final String _accountId;
  final CommonDatabase _db;

  Future<Set<String>> _read(String kind) async => {
    for (final r in _db.select(
      'SELECT mail_id FROM flags WHERE account_id = ? AND kind = ?',
      [_accountId, kind],
    ))
      r['mail_id'] as String,
  };

  void _write(String kind, Set<String> ids) => _tx(() {
    _db.execute('DELETE FROM flags WHERE account_id = ? AND kind = ?', [
      _accountId,
      kind,
    ]);
    final stmt = _db.prepare('INSERT INTO flags VALUES (?, ?, ?)');
    for (final id in ids) {
      stmt.execute([_accountId, kind, id]);
    }
    stmt.close();
  });

  void _tx(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Set<String>> readPinned() => _read('pinned');
  Future<Set<String>> readReplied() => _read('replied');
  Future<Set<String>> readForwarded() => _read('forwarded');

  /// ThreadId-keyed companions to [readReplied]/[readForwarded]: a reply or
  /// forward is stamped on every message in the conversation, not only the
  /// one the user actually opened — so the inbox row for a thread whose
  /// answered message isn't currently loaded into memory (e.g. it lives in
  /// an unfetched folder) still shows the icon. See [ApiMailRepository]
  /// `stampLocalFlags`.
  Future<Set<String>> readRepliedThreads() => _read('replied_threads');
  Future<Set<String>> readForwardedThreads() => _read('forwarded_threads');

  /// ThreadId-keyed set of Sent-folder conversations that have received an
  /// inbound reply — the mirror direction of [readRepliedThreads]: that one
  /// marks a thread the user replied *into*, this one marks a thread the
  /// user *sent* that got answered back. Powers the Sent-folder
  /// "Yanıtlanmadı" nudge in `MailListItem`. See
  /// `ApiMailRepository._markSentThreadsAnswered`.
  Future<Set<String>> readAnsweredThreads() => _read('answered_threads');
  Future<void> writePinned(Set<String> ids) async => _write('pinned', ids);
  Future<void> writeReplied(Set<String> ids) async => _write('replied', ids);
  Future<void> writeForwarded(Set<String> ids) async =>
      _write('forwarded', ids);
  Future<void> writeRepliedThreads(Set<String> ids) async =>
      _write('replied_threads', ids);
  Future<void> writeForwardedThreads(Set<String> ids) async =>
      _write('forwarded_threads', ids);
  Future<void> writeAnsweredThreads(Set<String> ids) async =>
      _write('answered_threads', ids);

  Future<List<Map<String, dynamic>>> readContacts() async => [
    for (final r in _db.select(
      'SELECT id, email, display_name FROM manual_contacts WHERE account_id = ?',
      [_accountId],
    ))
      {'id': r['id'], 'email': r['email'], 'displayName': r['display_name']},
  ];

  Future<void> writeContacts(List<Map<String, dynamic>> contacts) async =>
      _tx(() {
        _db.execute(
          'DELETE FROM manual_contacts WHERE account_id = ?',
          [_accountId],
        );
        final stmt = _db.prepare(
          'INSERT INTO manual_contacts VALUES (?, ?, ?, ?)',
        );
        for (final c in contacts) {
          stmt.execute([
            _accountId,
            c['id'],
            c['email'],
            c['displayName'],
          ]);
        }
        stmt.close();
      });

  Future<List<Map<String, dynamic>>> readLabelDefs() async => [
    for (final r in _db.select(
      'SELECT id, name, color FROM labels WHERE account_id = ? ORDER BY sort',
      [_accountId],
    ))
      {'id': r['id'], 'name': r['name'], 'color': r['color']},
  ];

  Future<void> writeLabelDefs(List<Map<String, dynamic>> defs) async => _tx(() {
    _db.execute('DELETE FROM labels WHERE account_id = ?', [_accountId]);
    final stmt = _db.prepare('INSERT INTO labels VALUES (?, ?, ?, ?, ?)');
    for (var i = 0; i < defs.length; i++) {
      final d = defs[i];
      stmt.execute([_accountId, d['id'], d['name'], d['color'], i]);
    }
    stmt.close();
  });

  static const defaultLabels = [
    {'id': 'label-default-work', 'name': 'İş', 'color': 0xFF3E7CB1},
    {'id': 'label-default-personal', 'name': 'Kişisel', 'color': 0xFF2E8B6E},
    {'id': 'label-default-finance', 'name': 'Finans', 'color': 0xFFC77D2E},
    {'id': 'label-default-shopping', 'name': 'Alışveriş', 'color': 0xFF8E7CC3},
    {'id': 'label-default-travel', 'name': 'Seyahat', 'color': 0xFF1B998B},
  ];

  Future<Map<String, List<String>>> readLabelMap() async {
    final map = <String, List<String>>{};
    for (final r in _db.select(
      'SELECT mail_id, label_id FROM mail_labels WHERE account_id = ?',
      [_accountId],
    )) {
      (map[r['mail_id'] as String] ??= []).add(r['label_id'] as String);
    }
    return map;
  }

  Future<void> writeLabelMap(Map<String, List<String>> map) async => _tx(() {
    _db.execute('DELETE FROM mail_labels WHERE account_id = ?', [_accountId]);
    final stmt = _db.prepare('INSERT INTO mail_labels VALUES (?, ?, ?)');
    for (final e in map.entries) {
      for (final label in e.value) {
        stmt.execute([_accountId, e.key, label]);
      }
    }
    stmt.close();
  });

  /// Snooze timestamps (mail id -> epoch millis it should reappear).
  /// Purely client-side, same rationale as pin/replied/forwarded above.
  Future<Map<String, int>> readSnoozed() async => {
    for (final r in _db.select(
      'SELECT mail_id, until_ms FROM snoozes WHERE account_id = ?',
      [_accountId],
    ))
      r['mail_id'] as String: r['until_ms'] as int,
  };

  Future<void> writeSnoozed(Map<String, int> untilByMailId) async => _tx(() {
    _db.execute('DELETE FROM snoozes WHERE account_id = ?', [_accountId]);
    final stmt = _db.prepare('INSERT INTO snoozes VALUES (?, ?, ?)');
    for (final entry in untilByMailId.entries) {
      stmt.execute([_accountId, entry.key, entry.value]);
    }
    stmt.close();
  });

  /// Queues [operation] for [mailId] — [folderId] only for `move` — after a
  /// network failure stopped it from reaching the backend, so it can be
  /// replayed once the account reconnects (see
  /// `ApiMailRepository._replayQueuedMutations`). A later call in the same
  /// [mutationCategoryFor] category for the same mail overwrites the
  /// earlier one — only the final desired state ever needs to replay.
  Future<void> queueMutation(
    String mailId,
    String operation, {
    String? folderId,
  }) async => _tx(() {
    _db.execute(
      'INSERT OR REPLACE INTO offline_mutations '
      '(account_id, mail_id, category, operation, folder_id, queued_at_ms) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        _accountId,
        mailId,
        mutationCategoryFor(operation),
        operation,
        folderId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  });

  /// Every queued mutation, oldest first.
  Future<List<QueuedMutation>> readQueuedMutations() async => [
    for (final r in _db.select(
      'SELECT mail_id, operation, folder_id, queued_at_ms FROM offline_mutations '
      'WHERE account_id = ? ORDER BY queued_at_ms',
      [_accountId],
    ))
      QueuedMutation(
        mailId: r['mail_id'] as String,
        operation: r['operation'] as String,
        folderId: r['folder_id'] as String?,
        queuedAtMs: r['queued_at_ms'] as int,
      ),
  ];

  /// Clears one mail's queued mutation in [category] — either it replayed
  /// successfully, or it came back as an unretryable conflict (see
  /// `ApiMailRepository.offlineMutationConflicts`). Scoped to [category]
  /// (not just [mailId]) so clearing a replayed `location` mutation never
  /// drops an unrelated still-queued `star_state` mutation on the same mail.
  Future<void> clearQueuedMutation(String mailId, String category) async =>
      _tx(() {
        _db.execute(
          'DELETE FROM offline_mutations WHERE account_id = ? AND mail_id = ? '
          'AND category = ?',
          [_accountId, mailId, category],
        );
      });

  /// One-time import of the SharedPreferences storage this class used before
  /// SQLite. Runs only while the account has no SQLite state yet, and removes
  /// the old keys afterwards.
  Future<void> migrateLegacyPrefs() async {
    final has = _db.select(
      'SELECT 1 FROM flags WHERE account_id = ? '
      'UNION SELECT 1 FROM labels WHERE account_id = ? LIMIT 1',
      [_accountId, _accountId],
    );
    final prefs = await SharedPreferences.getInstance();
    String key(String f) => 'kaydet.local_flags.$_accountId.$f';
    final legacy = [
      'pinned',
      'replied',
      'forwarded',
      'label_defs',
      'label_map',
    ].where((f) => prefs.containsKey(key(f))).toList();
    if (legacy.isEmpty) return;
    if (has.isEmpty) {
      for (final kind in ['pinned', 'replied', 'forwarded']) {
        final ids = prefs.getStringList(key(kind));
        if (ids != null) _write(kind, ids.toSet());
      }
      final defs = prefs.getString(key('label_defs'));
      if (defs != null) {
        await writeLabelDefs(
          (jsonDecode(defs) as List).cast<Map<String, dynamic>>(),
        );
      }
      final map = prefs.getString(key('label_map'));
      if (map != null) {
        await writeLabelMap(
          (jsonDecode(map) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as List).cast<String>()),
          ),
        );
      }
    }
    for (final f in legacy) {
      await prefs.remove(key(f));
    }
  }
}
