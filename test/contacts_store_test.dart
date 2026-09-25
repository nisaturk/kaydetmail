import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/services/contacts_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal [MailRepository] double exposing only [getAllEmails] plus a way
/// to simulate mail syncing in later and notifying listeners — everything
/// else is unused by [ContactsStore].
class _FakeRepo extends MailRepository {
  _FakeRepo(this._emails);

  List<Email> _emails;

  @override
  List<Email> getAllEmails() => List.unmodifiable(_emails);

  void addSyncedMail(List<Email> more) {
    _emails = [..._emails, ...more];
    notifyListeners();
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Email _mail({
  required String id,
  required String senderEmail,
  String senderName = '',
  List<String> to = const [],
  List<String> cc = const [],
  List<String> bcc = const [],
  required DateTime timestamp,
}) => Email(
  id: id,
  senderName: senderName,
  senderEmail: senderEmail,
  recipients: to,
  cc: cc,
  bcc: bcc,
  subject: 'S',
  bodyText: 'B',
  timestamp: timestamp,
);

void main() {
  test('derives one contact per unique address across From/To/Cc/Bcc', () {
    final contacts = ContactsStore.fromEmails([
      _mail(
        id: '1',
        senderEmail: 'alice@example.com',
        senderName: 'Alice',
        to: const ['bob@example.com'],
        cc: const ['carol@example.com'],
        timestamp: DateTime(2024, 1, 1),
      ),
    ]);
    expect(contacts.map((c) => c.email).toSet(), {
      'alice@example.com',
      'bob@example.com',
      'carol@example.com',
    });
  });

  test('addresses are deduplicated case-insensitively, keeping the newest known name', () {
    final contacts = ContactsStore.fromEmails([
      _mail(
        id: '1',
        senderEmail: 'Alice@Example.com',
        senderName: 'Alice A',
        timestamp: DateTime(2024, 1, 1),
      ),
      _mail(
        id: '2',
        senderEmail: 'alice@example.com',
        senderName: 'Alice A.',
        timestamp: DateTime(2024, 1, 5),
      ),
    ]);
    expect(contacts.length, 1);
    expect(contacts.single.displayName, 'Alice A.');
  });

  test('a recipient-only address (never a sender) falls back to the address itself', () {
    final contacts = ContactsStore.fromEmails([
      _mail(
        id: '1',
        senderEmail: 'me@example.com',
        to: const ['nobody@example.com'],
        timestamp: DateTime(2024, 1, 1),
      ),
    ]);
    final nobody = contacts.firstWhere((c) => c.email == 'nobody@example.com');
    expect(nobody.displayName, 'nobody@example.com');
  });

  test('sorts most-recently-seen first', () {
    final contacts = ContactsStore.fromEmails([
      _mail(
        id: '1',
        senderEmail: 'old@example.com',
        timestamp: DateTime(2024, 1, 1),
      ),
      _mail(
        id: '2',
        senderEmail: 'new@example.com',
        timestamp: DateTime(2024, 6, 1),
      ),
    ]);
    expect(contacts.map((c) => c.email).toList(), [
      'new@example.com',
      'old@example.com',
    ]);
  });

  test('a later mail without a name never overwrites a known name with the bare address', () {
    final contacts = ContactsStore.fromEmails([
      _mail(
        id: '1',
        senderEmail: 'alice@example.com',
        senderName: 'Alice',
        timestamp: DateTime(2024, 1, 1),
      ),
      _mail(
        id: '2',
        senderEmail: 'me@example.com',
        to: const ['alice@example.com'],
        timestamp: DateTime(2024, 6, 1),
      ),
    ]);
    final alice = contacts.firstWhere((c) => c.email == 'alice@example.com');
    expect(alice.displayName, 'Alice');
    expect(alice.lastSeen, DateTime(2024, 6, 1));
  });

  test('search matches email or display name, case-insensitively, and requires a query', () {
    final contacts = [
      Contact(
        email: 'alice@example.com',
        displayName: 'Alice A',
        lastSeen: DateTime(2024, 1, 1),
      ),
      Contact(
        email: 'bob@example.com',
        displayName: 'Bob B',
        lastSeen: DateTime(2024, 1, 1),
      ),
    ];
    expect(ContactsStore.search(contacts, 'ali').map((c) => c.email), [
      'alice@example.com',
    ]);
    expect(ContactsStore.search(contacts, 'EXAMPLE').length, 2);
    expect(ContactsStore.search(contacts, ''), isEmpty);
  });

  group('persisted address book', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ContactsStore.resetForTest();
    });

    test('merge dedupes by email, keeping whichever sighting is newer', () {
      final older = Contact(
        email: 'a@b.com',
        displayName: 'Eski İsim',
        lastSeen: DateTime(2024, 1, 1),
      );
      final newer = Contact(
        email: 'A@B.com',
        displayName: 'Yeni İsim',
        lastSeen: DateTime(2024, 6, 1),
      );

      final merged = ContactsStore.merge([older], [newer]);

      expect(merged, hasLength(1));
      expect(merged.single.displayName, 'Yeni İsim');
    });

    test(
      'ingest persists contacts so loadPersisted finds them after a restart',
      () async {
        await ContactsStore.ingest([
          _mail(
            id: 'm1',
            senderEmail: 'kalici@x.com',
            senderName: 'Kalıcı Kişi',
            timestamp: DateTime(2024, 1, 1),
          ),
        ]);

        // Simulates a fresh app start: drop the in-memory cache and reload
        // purely from SharedPreferences.
        ContactsStore.resetForTest();
        final persisted = await ContactsStore.loadPersisted();

        expect(persisted.map((c) => c.email), contains('kalici@x.com'));
      },
    );

    test('a contact from mail synced after startListening was called becomes searchable', () async {
      final repo = _FakeRepo(const []);
      ContactsStore.startListening(repo);
      await pumpEventQueue();

      expect(
        ContactsStore.search(ContactsStore.cachedPersisted, 'sonradan'),
        isEmpty,
      );

      repo.addSyncedMail([
        _mail(
          id: 'm2',
          senderEmail: 'sonradan@x.com',
          senderName: 'Sonradan Gelen',
          timestamp: DateTime(2024, 2, 1),
        ),
      ]);
      await pumpEventQueue();

      final found = ContactsStore.search(
        ContactsStore.cachedPersisted,
        'sonradan',
      );
      expect(found.map((c) => c.email), contains('sonradan@x.com'));
    });

    test(
      'startListening only re-ingests mail with an id not seen before',
      () async {
        final mail = _mail(
          id: 'm3',
          senderEmail: 'tekrar@x.com',
          timestamp: DateTime(2024, 1, 1),
        );
        final repo = _FakeRepo([mail]);
        ContactsStore.startListening(repo);
        await pumpEventQueue();

        // An unrelated notification (same mail, no new ids) must not throw or
        // duplicate anything — merge already keeps this idempotent either way,
        // this just proves the id-diffing skip path is exercised safely.
        repo.addSyncedMail(const []);
        await pumpEventQueue();

        final persisted = await ContactsStore.loadPersisted();
        expect(persisted.where((c) => c.email == 'tekrar@x.com'), hasLength(1));
      },
    );
  });
}
