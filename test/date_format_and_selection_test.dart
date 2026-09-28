import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/state/mail_selection_controller.dart';
import 'package:kaydetmail/utils/date_format.dart';

void main() {
  test('formats yesterday distinctly across midnight', () {
    final now = DateTime(2026, 9, 28, 9);

    expect(formatMailTime(DateTime(2026, 9, 27, 23, 30), now: now), 'dün');
    expect(formatMailTime(DateTime(2026, 9, 26, 23, 30), now: now), 'Cmt');
  });

  test('exits selection mode after last mail is deselected', () {
    final selection = MailSelectionController();

    selection.toggle('mail-1');
    selection.toggle('mail-1');

    expect(selection.isActive, isFalse);
    expect(selection.count, 0);
  });
}
