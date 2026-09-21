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
  test('round-trips mails, scopes by account and caps per folder', () {
    final cache = MailCache.inMemory();
    cache.apply('acc', [
      for (var i = 1; i <= 5; i++) _mail('m$i', i),
      _mail('s1', 1, folder: MailFolder.sent),
    ], const []);
    cache.apply('other', [_mail('o1', 1)], const []);

    final all = cache.load('acc');
    expect(all.length, 6);
    final first = all.firstWhere((e) => e.id == 'm5');
    expect(first.isStarred, isTrue);
    expect(first.folder, MailFolder.inbox);
    expect(first.attachments.single.id, 'att');

    final capped = cache.load('acc', perFolder: 2);
    expect(
      capped.where((e) => e.folder == MailFolder.inbox).map((e) => e.id),
      unorderedEquals(['m5', 'm4']),
    );

    cache.apply('acc', const [], ['m1', 'm2']);
    expect(cache.load('acc').length, 4);

    cache.clear('acc');
    expect(cache.load('acc'), isEmpty);
    expect(cache.load('other').length, 1);
  });
}
