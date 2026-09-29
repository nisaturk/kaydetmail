import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/services/account_data_purger.dart';
import 'package:kaydetmail/services/attachment_download_manager.dart';
import 'package:kaydetmail/services/contacts_store.dart';
import 'package:kaydetmail/services/mail_cache.dart';
import 'package:kaydetmail/services/signature_store.dart';
import 'package:shared_preferences/shared_preferences.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ContactsStore.resetForTest();
  });

  test('purge wipes cache rows, legacy signature and the contact book', () async {
    final cache = MailCache.inMemory();
    cache.db.execute("INSERT INTO snoozes VALUES ('acc', 'm1', 1)");
    await SignatureStore.save('me@x.com', 'Best, me');
    await ContactsStore.ingest([
      Email(
        id: 'm1',
        senderName: 'A',
        senderEmail: 'a@x.com',
        recipients: const ['b@x.com'],
        subject: 'S',
        bodyText: 'B',
        timestamp: DateTime.utc(2026, 1, 1),
      ),
    ]);
    expect(ContactsStore.cachedPersisted, isNotEmpty);

    await AccountDataPurger(
      attachments: AttachmentDownloadManager.instance,
    ).purge(accountId: 'acc', accountEmail: 'me@x.com', cache: cache);

    expect(cache.db.select('SELECT * FROM snoozes'), isEmpty);
    expect(await SignatureStore.load('me@x.com'), '');
    expect(ContactsStore.cachedPersisted, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString('contacts_store_v1'),
      isNull,
    );
  });

  test('purge without a cache still clears the rest', () async {
    await SignatureStore.save('me@x.com', 'Best, me');

    await AccountDataPurger().purge(accountId: 'acc', accountEmail: 'me@x.com');

    expect(await SignatureStore.load('me@x.com'), '');
  });
}
