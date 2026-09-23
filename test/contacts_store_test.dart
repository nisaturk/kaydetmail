import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/services/contacts_store.dart';

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
      _mail(id: '1', senderEmail: 'old@example.com', timestamp: DateTime(2024, 1, 1)),
      _mail(id: '2', senderEmail: 'new@example.com', timestamp: DateTime(2024, 6, 1)),
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
      Contact(email: 'alice@example.com', displayName: 'Alice A', lastSeen: DateTime(2024, 1, 1)),
      Contact(email: 'bob@example.com', displayName: 'Bob B', lastSeen: DateTime(2024, 1, 1)),
    ];
    expect(
      ContactsStore.search(contacts, 'ali').map((c) => c.email),
      ['alice@example.com'],
    );
    expect(ContactsStore.search(contacts, 'EXAMPLE').length, 2);
    expect(ContactsStore.search(contacts, ''), isEmpty);
  });
}
