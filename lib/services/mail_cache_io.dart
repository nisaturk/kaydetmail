import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

/// Native (`dart:io`) backend for [MailCache]: a real SQLite file under the
/// app's support directory, opened through the FFI bindings.
Future<CommonDatabase> openPersistent() async {
  final dir = await getApplicationSupportDirectory();
  await Directory(dir.path).create(recursive: true);
  return sqlite3.open(p.join(dir.path, 'mail_cache.db'));
}

/// A throwaway in-memory database (nothing persists).
CommonDatabase openInMemory() => sqlite3.openInMemory();
