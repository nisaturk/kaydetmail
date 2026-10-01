import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/services/local_mail_flags_store.dart';
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('flags and labels persist per account in SQLite', () async {
    final cache = MailCache.inMemory();
    final a = LocalMailFlagsStore('a', cache);
    final b = LocalMailFlagsStore('b', cache);

    await a.writePinned({'m1', 'm2'});
    await a.writeLabelDefs([
      {'id': 'l1', 'name': 'İş', 'color': 0xFF112233},
    ]);
    await a.writeLabelMap({
      'm1': ['l1'],
    });

    expect(await a.readPinned(), {'m1', 'm2'});
    expect(await b.readPinned(), isEmpty);
    expect((await a.readLabelDefs()).single['color'], 0xFF112233);
    expect(await a.readLabelMap(), {
      'm1': ['l1'],
    });

    cache.forgetAccount('a');
    expect(await a.readPinned(), isEmpty);
  });

  test('offline location undo preserves its origin after reopening the store and across accounts', () async {
    final cache = MailCache.inMemory();
    final first = LocalMailFlagsStore('a', cache);
    final other = LocalMailFlagsStore('b', cache);
    await first.queueMutation('mail', 'archive', originFolderId: 'drafts');
    await first.queueMutation('mail', 'trash', originFolderId: 'archive');
    await other.queueMutation('mail', 'trash', originFolderId: 'other-inbox');

    final reopened = LocalMailFlagsStore('a', cache);
    await reopened.queueMutation('mail', 'restore');

    final restored = (await reopened.readQueuedMutations()).single;
    expect(restored.operation, 'move');
    expect(restored.folderId, 'archive');
    final unrelated = (await other.readQueuedMutations()).single;
    expect(unrelated.operation, 'trash');
    expect(unrelated.originFolderId, 'other-inbox');
  });

  test(
    'migrates SharedPreferences state once and removes the old keys',
    () async {
      SharedPreferences.setMockInitialValues({
        'kaydet.local_flags.a.pinned': ['m1'],
        'kaydet.local_flags.a.label_defs': jsonEncode([
          {'id': 'l1', 'name': 'x', 'color': 1},
        ]),
        'kaydet.local_flags.a.label_map': jsonEncode({
          'm1': ['l1'],
        }),
      });
      final store = LocalMailFlagsStore('a', MailCache.inMemory());

      await store.migrateLegacyPrefs();

      expect(await store.readPinned(), {'m1'});
      expect(await store.readLabelMap(), {
        'm1': ['l1'],
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('kaydet.local_flags')),
        isEmpty,
      );
    },
  );
}
