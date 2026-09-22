import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/email.dart';
import '../models/mail_folder.dart';

/// On-device SQLite copy of the mails the API repository has loaded, so the
/// app can paint the last known mailbox instantly on cold start and then
/// revalidate in the background. One row per mail, scoped by account.
///
/// Attachment bytes are never stored, only their metadata.
class MailCache {
  MailCache._(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS mails (
        account_id TEXT NOT NULL,
        id TEXT NOT NULL,
        folder TEXT NOT NULL,
        ts INTEGER NOT NULL,
        json TEXT NOT NULL,
        PRIMARY KEY (account_id, id)
      )''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS mails_folder ON mails(account_id, folder, ts DESC)',
    );
    // Client-only state the API has no concept of (see LocalMailFlagsStore).
    _db.execute('''
      CREATE TABLE IF NOT EXISTS flags (
        account_id TEXT NOT NULL, kind TEXT NOT NULL, mail_id TEXT NOT NULL,
        PRIMARY KEY (account_id, kind, mail_id)
      )''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS labels (
        account_id TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL,
        color INTEGER NOT NULL, sort INTEGER NOT NULL,
        PRIMARY KEY (account_id, id)
      )''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS mail_labels (
        account_id TEXT NOT NULL, mail_id TEXT NOT NULL, label_id TEXT NOT NULL,
        PRIMARY KEY (account_id, mail_id, label_id)
      )''');
    // Server folder id -> logical MailFolder name, so the repository can
    // still resolve folders (and thus act on cached mail) after a cold
    // start with no network reachable yet.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        account_id TEXT NOT NULL, folder_id TEXT NOT NULL, folder_type TEXT NOT NULL,
        PRIMARY KEY (account_id, folder_id)
      )''');
  }

  final Database _db;

  /// Raw handle for [LocalMailFlagsStore]; everything else goes through the
  /// typed methods above.
  Database get db => _db;

  static Future<MailCache> open() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    return MailCache._(sqlite3.open(p.join(dir.path, 'mail_cache.db')));
  }

  factory MailCache.inMemory() => MailCache._(sqlite3.openInMemory());

  /// Newest [perFolder] mails of every folder for [accountId].
  List<Email> load(String accountId, {int perFolder = 100}) {
    final rows = _db.select(
      '''SELECT json FROM (
           SELECT json, ROW_NUMBER() OVER (PARTITION BY folder ORDER BY ts DESC) AS n
           FROM mails WHERE account_id = ?
         ) WHERE n <= ?''',
      [accountId, perFolder],
    );
    return [
      for (final row in rows)
        _fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
    ];
  }

  /// Upserts [changed] and deletes [removedIds] for [accountId] atomically.
  void apply(
    String accountId,
    Iterable<Email> changed,
    Iterable<String> removedIds,
  ) {
    _db.execute('BEGIN');
    try {
      final del = _db.prepare(
        'DELETE FROM mails WHERE account_id = ? AND id = ?',
      );
      for (final id in removedIds) {
        del.execute([accountId, id]);
      }
      del.close();
      final ins = _db.prepare(
        'INSERT OR REPLACE INTO mails VALUES (?, ?, ?, ?, ?)',
      );
      for (final e in changed) {
        ins.execute([
          accountId,
          e.id,
          e.folder.name,
          e.timestamp.millisecondsSinceEpoch,
          jsonEncode(_toJson(e)),
        ]);
      }
      ins.close();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Drops the cached mails of [accountId]. Flags and labels are user data
  /// and survive (they are keyed by mail id and reattach on the next load).
  void clear(String accountId) =>
      _db.execute('DELETE FROM mails WHERE account_id = ?', [accountId]);

  /// Removes everything stored for a deleted account, user state included.
  void forgetAccount(String accountId) {
    for (final table in ['mails', 'flags', 'labels', 'mail_labels', 'folders']) {
      _db.execute('DELETE FROM $table WHERE account_id = ?', [accountId]);
    }
  }

  /// Replaces the stored folder map for [accountId] with [idToType]
  /// (server folder id -> [MailFolder.name]).
  void saveFolders(String accountId, Map<String, String> idToType) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM folders WHERE account_id = ?', [accountId]);
      final ins = _db.prepare(
        'INSERT INTO folders VALUES (?, ?, ?)',
      );
      for (final entry in idToType.entries) {
        ins.execute([accountId, entry.key, entry.value]);
      }
      ins.close();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The last-known folder map for [accountId] (server folder id ->
  /// [MailFolder.name]), or empty when nothing was ever synced.
  Map<String, String> loadFolders(String accountId) {
    final rows = _db.select(
      'SELECT folder_id, folder_type FROM folders WHERE account_id = ?',
      [accountId],
    );
    return {
      for (final row in rows)
        row['folder_id'] as String: row['folder_type'] as String,
    };
  }

  static Map<String, dynamic> _toJson(Email e) => {
    'id': e.id,
    'senderName': e.senderName,
    'senderEmail': e.senderEmail,
    'recipients': e.recipients,
    'cc': e.cc,
    'bcc': e.bcc,
    'subject': e.subject,
    'bodyText': e.bodyText,
    'hasRemoteContent': e.hasRemoteContent,
    'ts': e.timestamp.millisecondsSinceEpoch,
    'isRead': e.isRead,
    'isStarred': e.isStarred,
    'folder': e.folder.name,
    'accountId': e.accountId,
    'threadId': e.threadId,
    'inReplyToId': e.inReplyToId,
    'attachments': [
      for (final a in e.attachments)
        {'id': a.id, 'name': a.name, 'size': a.sizeBytes, 'mime': a.mimeType},
    ],
  };

  // Pin/replied/forwarded/labels are not stored here: the repository stamps
  // them from LocalMailFlagsStore, which stays their source of truth.
  static Email _fromJson(Map<String, dynamic> j) => Email(
    id: j['id'] as String,
    senderName: j['senderName'] as String,
    senderEmail: j['senderEmail'] as String,
    recipients: (j['recipients'] as List).cast<String>(),
    cc: (j['cc'] as List).cast<String>(),
    bcc: (j['bcc'] as List).cast<String>(),
    subject: j['subject'] as String,
    bodyText: j['bodyText'] as String,
    hasRemoteContent: j['hasRemoteContent'] as bool,
    timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
    isRead: j['isRead'] as bool,
    isStarred: j['isStarred'] as bool,
    folder: MailFolder.values.byName(j['folder'] as String),
    accountId: j['accountId'] as String,
    threadId: j['threadId'] as String,
    inReplyToId: j['inReplyToId'] as String?,
    attachments: [
      for (final a in (j['attachments'] as List).cast<Map<String, dynamic>>())
        Attachment(
          id: a['id'] as String?,
          name: a['name'] as String,
          sizeBytes: a['size'] as int,
          mimeType: a['mime'] as String?,
        ),
    ],
  );
}
