import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';

void main() {
  test('literal terms can span fields but cannot join their boundaries', () {
    final recipients = ['COOK@example.test'];
    final email = Email(
      id: 'mail',
      senderName: 'Chef',
      senderEmail: 'chef@example.test',
      recipients: recipients,
      cc: ['copy@example.test'],
      bcc: ['hidden@example.test'],
      subject: 'Domatesli nefis',
      bodyText: 'Sıcak çorba',
      timestamp: DateTime.utc(2026),
      attachments: [const Attachment(name: '50%_tarif.pdf', sizeBytes: 1)],
      headers: {'Message-Id': '<unique@example.test>'},
    );

    expect(
      email.matchesQuery(' DOMATES\tÇORBA chef cook copy hidden tarif unique '),
      isTrue,
    );
    expect(email.matchesQuery('domates domates'), isTrue);
    expect(email.matchesQuery('50%_tarif'), isTrue);
    expect(email.matchesQuery('nefisSıcak'), isFalse);
    expect(email.matchesQuery('domates missing'), isFalse);
    expect(email.matchesQuery(' \t\n '), isTrue);
    expect(email.matchesQuery('replacement'), isFalse);
    recipients[0] = 'replacement@example.test';
    expect(email.matchesQuery('replacement'), isTrue);
    expect(email.matchesQuery('cook'), isFalse);
    expect(
      email.copyWith(bodyText: 'Yeni içerik').matchesQuery('çorba'),
      isFalse,
    );
  });
}
