import 'package:sqlite3/wasm.dart';

/// The loaded sqlite3 WebAssembly module, cached after the first
/// [openPersistent] call so a later [openInMemory] can reuse it
/// synchronously instead of re-fetching `sqlite3.wasm`.
WasmSqlite3? _sqlite3;

/// Web backend for [MailCache].
///
/// Browsers can't touch the real filesystem, so this loads sqlite3 compiled
/// to WebAssembly (served as `web/sqlite3.wasm`, fetched from the app's own
/// origin — see `web/index.html`) and stores pages in an IndexedDB-backed
/// virtual file system instead of a plain file. Both the module fetch and
/// the IndexedDB handshake can fail (offline first load, private-browsing
/// tabs that block IndexedDB, storage quota); either failure is left
/// unhandled here so it propagates to [ApiMailRepository]'s existing
/// `_openCacheOrMemory` fallback, which retries with [openInMemory] exactly
/// like it already does for the native backend.
Future<CommonDatabase> openPersistent() async {
  final sqlite3 = _sqlite3 ??= await WasmSqlite3.loadFromUrlString(
    'sqlite3.wasm',
  );
  final fs = await IndexedDbFileSystem.open(dbName: 'kaydetmail_mail_cache');
  sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
  return sqlite3.open('mail_cache.db');
}

/// A throwaway in-memory database (nothing persists).
///
/// Only reachable once the sqlite3 wasm module has already been loaded by a
/// prior [openPersistent] call in this session: [MailCache.open] always
/// runs first in the real app and caches the module above even when the
/// IndexedDB step that follows it fails, so the common "storage blocked"
/// case still degrades to a working (if non-persistent) database. If the
/// module itself never loaded at all — `sqlite3.wasm` could not be fetched,
/// e.g. the app is being served without that asset — there is no
/// synchronous fallback available in a browser, and this throws rather than
/// silently pretending to have a cache.
CommonDatabase openInMemory() {
  final sqlite3 = _sqlite3;
  if (sqlite3 == null) {
    throw StateError(
      'sqlite3 wasm module unavailable: MailCache.open() must be attempted '
      'at least once (even if it fails) before MailCache.inMemory() can '
      'work on web.',
    );
  }
  return sqlite3.open(':memory:');
}
