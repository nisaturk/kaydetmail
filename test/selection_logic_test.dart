import 'package:flutter_test/flutter_test.dart';

import 'package:kaydetmail/data/mock/mock_emails.dart';
import 'package:kaydetmail/state/mail_selection_controller.dart';

void main() {
  group('matchesQuery', () {
    final email = MockEmails.seed.firstWhere((e) => e.id == 'seed-david-ci');

    test('matches sender name, email, subject and body', () {
      expect(email.matchesQuery('david'), isTrue);
      expect(email.matchesQuery('david.chen@northstar.io'), isTrue);
      expect(email.matchesQuery('CI pipeline'), isTrue);
      expect(email.matchesQuery('certificate'), isTrue);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(email.matchesQuery('  DAVID CHEN  '), isTrue);
    });

    test('empty query matches everything', () {
      expect(email.matchesQuery(''), isTrue);
      expect(email.matchesQuery('   '), isTrue);
    });

    test('unrelated terms do not match', () {
      expect(email.matchesQuery('quantica'), isFalse);
    });
  });

  group('MailSelectionController', () {
    test('toggle enters selection mode and tracks ids', () {
      final selection = MailSelectionController();
      expect(selection.isActive, isFalse);

      selection.toggle('a');
      expect(selection.isActive, isTrue);
      expect(selection.count, 1);
      expect(selection.selectedIds, contains('a'));

      selection.toggle('a');
      expect(selection.count, 0);
    });

    test('selectAllVisible selects the synced ids', () {
      final selection = MailSelectionController();
      selection.enter();
      selection.syncVisibleIds(['a', 'b', 'c']);
      selection.selectAllVisible();

      expect(selection.count, 3);
      expect(selection.selectedIds, containsAll(['a', 'b', 'c']));
    });

    test('exit clears selection and leaves selection mode', () {
      final selection = MailSelectionController();
      selection.toggle('a');
      selection.selectAllVisible(); // unchanged set

      selection.exit();
      expect(selection.isActive, isFalse);
      expect(selection.count, 0);
    });
  });
}