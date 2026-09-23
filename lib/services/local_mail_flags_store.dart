import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';

import 'mail_cache.dart';

/// Persists mail state the backend has no concept of, in the on-device
/// SQLite database ([MailCache]).
///
/// Pinning is a purely client-side favoriting feature — the API never sees
/// it. "Replied"/"forwarded" mark the moment the user opened the reply/
/// forward compose screen, and labels are user-defined tags; no API response
/// carries an equivalent. Everything is scoped per account so switching
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

  Future<void> writePinned(Set<String> ids) async => _write('pinned', ids);
  Future<void> writeReplied(Set<String> ids) async => _write('replied', ids);
  Future<void> writeForwarded(Set<String> ids) async =>
      _write('forwarded', ids);
  Future<void> writeRepliedThreads(Set<String> ids) async =>
      _write('replied_threads', ids);
  Future<void> writeForwardedThreads(Set<String> ids) async =>
      _write('forwarded_threads', ids);

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

  /// Gives a fresh account the default labels exactly once. They are ordinary
  /// labels afterwards (editable, deletable) and are never re-added, so a
  /// deletion sticks. Accounts that already have labels are left untouched.
  Future<void> seedDefaultLabels() async {
    final seeded = await _read('labels_seeded');
    if (seeded.isNotEmpty) return;
    if ((await readLabelDefs()).isEmpty) await writeLabelDefs(defaultLabels);
    _write('labels_seeded', {'1'});
  }

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
