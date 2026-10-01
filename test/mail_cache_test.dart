import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/services/mail_cache.dart';

Email _mail(String id, int day, {MailFolder folder = MailFolder.inbox}) =>
    Email(
      id: id,
      senderName: 'A',
      senderEmail: 'a@x.com',
      recipients: const ['b@x.com'],
      subject: 's$id',
      bodyText: 'body',
      timestamp: DateTime.utc(2026, 1, day),
      isStarred: true,
      folder: folder,
      accountId: 'acc',
      attachments: const [Attachment(id: 'att', name: 'f.pdf', sizeBytes: 3)],
    );

void main() {
  test('round-trips every cached mail and scopes by account', () {
    final cache = MailCache.inMemory();
    cache.apply('acc', [
      for (var i = 1; i <= 150; i++) _mail('m$i', 1 + i % 28),
      _mail('s1', 1, folder: MailFolder.sent),
    ], const []);
    cache.apply('other', [_mail('o1', 1)], const []);

    final all = cache.load('acc');
    expect(all.length, 151);
    final first = all.firstWhere((e) => e.id == 'm5');
    expect(first.isStarred, isTrue);
    expect(first.folder, MailFolder.inbox);
    expect(first.attachments.single.id, 'att');

    cache.apply('acc', const [], ['m1', 'm2']);
    expect(cache.load('acc').length, 149);

    cache.clear('acc');
    expect(cache.load('acc'), isEmpty);
    expect(cache.load('other').length, 1);
  });

  test('round-trips custom folder buckets and keeps accounts isolated', () {
    final cache = MailCache.inMemory();
    cache.apply(
      'acc',
      [_mail('custom-1', 3)],
      const [],
      customFolderId: 'folder-projects',
    );
    cache.apply(
      'other',
      [_mail('custom-2', 4)],
      const [],
      customFolderId: 'folder-projects',
    );

    expect(cache.load('acc'), isEmpty);
    expect(
      cache.loadCustomFolders('acc')['folder-projects']!.map((mail) => mail.id),
      ['custom-1'],
    );
    expect(
      cache
          .loadCustomFolders('other')['folder-projects']!
          .map((mail) => mail.id),
      ['custom-2'],
    );

    cache.replaceCustomFolder('acc', 'folder-projects', [
      _mail('custom-new', 5),
    ]);
    expect(
      cache.loadCustomFolders('acc')['folder-projects']!.map((mail) => mail.id),
      ['custom-new'],
    );
  });

  test('round-trips the folder id -> type map, scoped by account', () {
    final cache = MailCache.inMemory();
    cache.saveFolders('acc', {'folder-1': 'inbox', 'folder-2': 'sent'});
    cache.saveFolders('other', {'folder-9': 'trash'});

    expect(cache.loadFolders('acc'), {'folder-1': 'inbox', 'folder-2': 'sent'});
    expect(cache.loadFolders('other'), {'folder-9': 'trash'});

    // Re-saving replaces the previous map instead of merging into it.
    cache.saveFolders('acc', {'folder-3': 'archive'});
    expect(cache.loadFolders('acc'), {'folder-3': 'archive'});

    cache.forgetAccount('acc');
    expect(cache.loadFolders('acc'), isEmpty);
    expect(cache.loadFolders('other'), isNotEmpty);
  });

  test(
    'forgetAccount clears every account-scoped table, snoozes and outbox',
    () {
      final cache = MailCache.inMemory();
      final db = cache.db;
      // Every table with an account_id column must be in the purge list, so a
      // future schema addition cannot silently survive account removal.
      final scoped = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .where(
            (table) => db
                .select('PRAGMA table_info($table)')
                .any((column) => column['name'] == 'account_id'),
          )
          .toSet();
      expect(MailCache.accountScopedTables.toSet(), scoped);

      db.execute("INSERT INTO snoozes VALUES ('acc', 'm1', 1)");
      db.execute("INSERT INTO snoozes VALUES ('other', 'm2', 1)");
      // The send journal is owned by OutboxStore; create its tables the way it
      // does and check they are wiped too (attachments via their send id).
      db.execute(
        'CREATE TABLE outbox (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, '
        'status TEXT, undo_until_ms INTEGER, message TEXT, error TEXT)',
      );
      db.execute(
        'CREATE TABLE outbox_attachments (send_id TEXT, position INTEGER, '
        'data BLOB)',
      );
      db.execute("INSERT INTO outbox (id, account_id) VALUES ('s1', 'acc')");
      db.execute("INSERT INTO outbox (id, account_id) VALUES ('s2', 'other')");
      db.execute("INSERT INTO outbox_attachments VALUES ('s1', 0, x'01')");
      db.execute("INSERT INTO outbox_attachments VALUES ('s2', 0, x'02')");

      cache.forgetAccount('acc');

      expect(
        db.select("SELECT * FROM snoozes WHERE account_id = 'acc'"),
        isEmpty,
      );
      expect(db.select('SELECT * FROM snoozes'), hasLength(1));
      expect(db.select('SELECT id FROM outbox').single['id'], 's2');
      expect(
        db.select('SELECT send_id FROM outbox_attachments').single['send_id'],
        's2',
      );
    },
  );

  test('forgetAccount works before the outbox tables exist', () {
    final cache = MailCache.inMemory();
    expect(() => cache.forgetAccount('acc'), returnsNormally);
  });
}
