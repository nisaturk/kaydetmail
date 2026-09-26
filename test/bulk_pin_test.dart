import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/utils/bulk_pin.dart';

Email _mail(String id, {String account = 'a', bool pinned = false}) => Email(
  id: id,
  accountId: account,
  senderName: 'S',
  senderEmail: 's@example.com',
  recipients: const ['r@example.com'],
  subject: id,
  bodyText: '',
  timestamp: DateTime(2026),
  isPinned: pinned,
);

void main() {
  test('allows filling the remaining slots exactly', () {
    final all = [_mail('p1', pinned: true), _mail('m1'), _mail('m2')];
    expect(bulkPinLimitError(all, ['m1', 'm2']), isNull);
  });

  test('rejects the whole batch when one account would exceed the cap', () {
    final all = [
      _mail('p1', pinned: true),
      _mail('p2', pinned: true),
      _mail('m1'),
      _mail('m2'),
    ];
    final error = bulkPinLimitError(all, ['m1', 'm2']);
    expect(error, contains('en fazla 1 tane daha'));
    expect(error, contains('Hiçbiri sabitlenmedi'));
  });

  test('counts the cap per account and ignores already pinned picks', () {
    final all = [
      _mail('p1', pinned: true),
      _mail('p2', pinned: true),
      _mail('p3', pinned: true),
      _mail('b1', account: 'b'),
      _mail('b2', account: 'b'),
    ];
    expect(bulkPinLimitError(all, ['p1', 'b1', 'b2']), isNull);
  });
}
