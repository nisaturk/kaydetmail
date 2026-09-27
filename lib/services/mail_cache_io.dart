import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

const _keyName = 'mail_cache_key_v1';

Future<({String path, String key})>? _prepared;

/// Native (`dart:io`) backend for [MailCache]: an SQLite3MultipleCiphers
/// file under the app's support directory, encrypted with a random key kept
/// in the platform keystore. A legacy plaintext file is encrypted in place;
/// a file whose key was lost cannot be read and is replaced.
Future<CommonDatabase> openPersistent() async {
  final prepared = await (_prepared ??= _prepare().catchError((Object error) {
    _prepared = null;
    throw error;
  }));
  return _openKeyed(prepared.path, prepared.key)!;
}

/// A throwaway in-memory database (nothing persists).
CommonDatabase openInMemory() => sqlite3.openInMemory();

Future<({String path, String key})> _prepare() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  final path = p.join(dir.path, 'mail_cache.db');
  // Device-only and available after first unlock: the key never leaves the
  // device in a backup, and background push handling can still open the DB.
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  var key = await storage.read(key: _keyName);
  if (key == null) {
    final random = Random.secure();
    key = [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await storage.write(key: _keyName, value: key);
  }

  final file = File(path);
  if (!await file.exists()) return (path: path, key: key);
  final keyed = _openKeyed(path, key);
  if (keyed != null) {
    keyed.close();
    return (path: path, key: key);
  }
  final plain = sqlite3.open(path);
  try {
    plain.select('SELECT count(*) FROM sqlite_master');
    plain.execute("PRAGMA rekey = \"x'$key'\"");
    plain.close();
  } on SqliteException {
    plain.close();
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final stale = File('$path$suffix');
      if (await stale.exists()) await stale.delete();
    }
  }
  return (path: path, key: key);
}

CommonDatabase? _openKeyed(String path, String key) {
  final db = sqlite3.open(path);
  try {
    db.execute("PRAGMA key = \"x'$key'\"");
    db.select('SELECT count(*) FROM sqlite_master');
    return db;
  } on SqliteException {
    db.close();
    return null;
  }
}
