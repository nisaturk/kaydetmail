import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/models/mail_template.dart';

void main() {
  const stamps = {
    'createdAt': '2026-01-01T00:00:00Z',
    'updatedAt': '2026-01-01T00:00:00Z',
  };

  group('MailSignature', () {
    test('keeps the plain text and drops any server HTML on write', () {
      final signature = MailSignature.fromJson({
        'id': 's1',
        'name': 'İmza',
        'bodyText': 'Saygılarımla',
        'bodyHtml': '<p>Saygılarımla</p>',
        ...stamps,
      });

      expect(signature.bodyText, 'Saygılarımla');
      expect(signature.toJson(), {
        'name': 'İmza',
        'bodyText': 'Saygılarımla',
        'bodyHtml': null,
      });
    });

    test('flattens an HTML-only legacy signature to text', () {
      final signature = MailSignature.fromJson({
        'id': 's1',
        'name': 'Eski',
        'bodyText': '',
        'bodyHtml': '<p>Ayşe <b>Yılmaz</b></p>',
        ...stamps,
      });

      expect(signature.bodyText, contains('Ayşe'));
      expect(signature.bodyText, contains('Yılmaz'));
      expect(signature.bodyText, isNot(contains('<')));
    });
  });

  group('MailTemplate', () {
    test('keeps the plain text and drops any server HTML on write', () {
      final template = MailTemplate.fromJson({
        'id': 't1',
        'name': 'Ad',
        'subject': 'Konu',
        'bodyText': 'Merhaba',
        'bodyHtml': '<p>Merhaba</p>',
        ...stamps,
      });

      expect(template.bodyText, 'Merhaba');
      expect(template.toJson()['bodyHtml'], isNull);
      expect(template.toJson()['bodyText'], 'Merhaba');
    });

    test('flattens an HTML-only legacy template to text', () {
      final template = MailTemplate.fromJson({
        'id': 't1',
        'name': 'Eski',
        'subject': '',
        'bodyHtml': '<p>Merhaba <i>dünya</i></p>',
        ...stamps,
      });

      expect(template.bodyText, isNotNull);
      expect(template.bodyText, contains('Merhaba'));
      expect(template.bodyText, isNot(contains('<')));
    });
  });
}
