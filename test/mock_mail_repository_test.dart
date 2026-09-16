import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/data/mock/mock_email_generator.dart';
import 'package:kaydetmail/data/mock/mock_emails.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';

void main() {
  group('mock data', () {
    test('seed email ids are unique', () {
      final ids = MockEmails.seed.map((e) => e.id).toSet();
      expect(ids.length, MockEmails.seed.length);
    });

    test('seed covers the documented test scenarios', () {
      final seed = MockEmails.seed;

      // Several inbox messages, some read and some unread.
      final inbox = seed.where((e) => e.folder == MailFolder.inbox).toList();
      expect(inbox.length, greaterThanOrEqualTo(5));
      expect(inbox.any((e) => e.isRead), isTrue);
      expect(inbox.any((e) => !e.isRead), isTrue);

      // Multiple senders and different dates.
      expect(inbox.map((e) => e.senderEmail).toSet().length,
          greaterThanOrEqualTo(3));
      expect(inbox.map((e) => e.timestamp).toSet().length,
          greaterThanOrEqualTo(3));

      // Long subject and long body (for preview truncation).
      expect(inbox.any((e) => e.subject.length >= 80), isTrue);
      expect(inbox.any((e) => e.bodyText.length >= 400), isTrue);

      // Pinned, sent, draft, trash and spam.
      expect(seed.any((e) => e.isPinned), isTrue);
      expect(seed.any((e) => e.folder == MailFolder.sent), isTrue);
      expect(seed.any((e) => e.folder == MailFolder.drafts), isTrue);
      expect(seed.any((e) => e.folder == MailFolder.trash), isTrue);
      expect(seed.any((e) => e.folder == MailFolder.spam), isTrue);

      // Badges/noisy messages (for spam-filtering UI tests).
      expect(seed.any((e) => e.senderEmail.contains('claim-now')), isTrue);
      expect(seed.any((e) => e.senderEmail.contains('dealzone')), isTrue);

      // Searchable by sender, subject and body.
      expect(inbox.any((e) => e.matchesQuery('david')), isTrue);
      expect(inbox.any((e) => e.matchesQuery('invoice')), isTrue);
      expect(inbox.any((e) => e.matchesQuery('migration')), isTrue);

      // Labels exist and are attached to at least one message.
      expect(inbox.any((e) => e.labelIds.isNotEmpty), isTrue);
    });

    test('documented mock account is accepted by login', () async {
      // The mock-only documented credentials stay easy to find.
      expect(MockMailRepository.demoEmail, 'nisa@kaydet.com');
      expect(MockMailRepository.demoPassword, 'kaydet123');

      final repo = MockMailRepository();
      final ok = await repo.login(
        email: MockMailRepository.demoEmail,
        password: MockMailRepository.demoPassword,
      );
      expect(ok, isTrue);
      expect(repo.currentUser, MockMailRepository.demoEmail);
    });

    test('resetMockData restores the pristine dataset', () async {
      final repo = MockMailRepository();
      expect(repo.currentUser, MockMailRepository.demoEmail);

      // Mutate: trash mail, add a label, delete "permanently", pin, generate.
      final target = repo.getEmailsInFolder(MailFolder.inbox).first;
      await repo.moveToTrash([target.id]);
      await repo.createLabel(
          name: 'Temp', color: const Color.fromARGB(255, 1, 2, 3));

      final pristineInboxCount = MockEmails.seed
          .where((e) => e.folder == MailFolder.inbox)
          .length;
      final mutatedCount = repo.getEmailsInFolder(MailFolder.inbox).length;
      expect(mutatedCount, lessThan(pristineInboxCount));

      repo.resetMockData();

      // Back to the exact seed count, pristine labels, no generated emails,
      // and the default current user again.
      expect(
        repo.getEmailsInFolder(MailFolder.inbox).length,
        pristineInboxCount,
      );
      expect(
        repo.getLabels().map((l) => l.id),
        containsAll(MockLabels.all.map((l) => l.id)),
      );
      expect(
        repo
            .getEmailsInFolder(MailFolder.inbox)
            .any((e) => e.id.startsWith('gen-')),
        isFalse,
      );
      expect(repo.currentUser, MockMailRepository.demoEmail);
    });

    test('resetMockData after loadMoreEmails drops the extra pages', () async {
      final repo = MockMailRepository();
      await repo.loadMoreEmails(MailFolder.inbox);

      final genCountBefore =
          repo.getEmailsInFolder(MailFolder.inbox).where((e) =>
              e.id.startsWith('gen-')).length;
      expect(genCountBefore, greaterThan(0));

      repo.resetMockData();

      expect(
        repo
            .getEmailsInFolder(MailFolder.inbox)
            .any((e) => e.id.startsWith('gen-')),
        isFalse,
      );
    });

    test('generated email ids never collide across batches', () {
      final seen = <String>{};
      for (var i = 0; i < 5; i++) {
        final batch = MockEmailGenerator.generateMoreEmails(count: 50);
        for (final email in batch) {
          expect(seen.add(email.id), isTrue,
              reason: 'duplicate id ${email.id}');
          expect(email.id.startsWith('gen-'), isTrue);
        }
      }
      // Generated ids must also never collide with the seeded ones.
      for (final email in MockEmails.seed) {
        expect(seen.contains(email.id), isFalse);
      }
    });

    test('generated emails are realistic (non-empty subject and body)', () {
      final batch = MockEmailGenerator.generateMoreEmails(count: 10);
      for (final email in batch) {
        expect(email.subject, isNotEmpty);
        expect(email.bodyText, isNotEmpty);
        expect(email.preview, isNotEmpty);
        expect(email.senderName, isNotEmpty);
      }
    });
  });

  group('MockMailRepository', () {
    test('login succeeds and logout resets', () async {
      final repo = MockMailRepository();
      expect(await repo.login(email: 'me@kaydet.app', password: 'secret1'),
          isTrue);
      await repo.logout();
      // Logging in again after logout still works.
      expect(await repo.login(email: 'me@kaydet.app', password: 'secret2'),
          isTrue);
    });

    test('getEmailsInFolder keeps pinned mails on top', () async {
      final repo = MockMailRepository();
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      final trash = repo.getEmailsInFolder(MailFolder.trash);

      expect(inbox, isNotEmpty);
      expect(trash, isNotEmpty);
      expect(
        inbox.every((e) => e.folder != MailFolder.trash),
        isTrue,
      );
      expect(inbox.any((e) => e.isRead), isTrue);
      expect(inbox.any((e) => !e.isRead), isTrue);

      // One continuous list: all pinned mails first, newest-first preserved
      // inside the pinned and unpinned groups.
      final firstUnpinned = inbox.indexWhere((e) => !e.isPinned);
      expect(firstUnpinned, greaterThan(0));
      expect(
        inbox.sublist(firstUnpinned).every((e) => !e.isPinned),
        isTrue,
      );
      for (var i = 1; i < inbox.length; i++) {
        final prev = inbox[i - 1];
        final curr = inbox[i];
        if (prev.isPinned == curr.isPinned) {
          expect(prev.timestamp.isAfter(curr.timestamp), isTrue);
        }
      }
    });

    test('pinned folder returns pinned emails from everywhere', () {
      final repo = MockMailRepository();
      final pinned = repo.getEmailsInFolder(MailFolder.pinned);
      expect(pinned, isNotEmpty);
      expect(pinned.every((e) => e.isPinned), isTrue);
    });

    test('loadMoreEmails appends without replacing existing ones', () async {
      final repo = MockMailRepository();
      final beforeIds = repo
          .getEmailsInFolder(MailFolder.inbox)
          .map((e) => e.id)
          .toSet();

      final batch = await repo.loadMoreEmails(MailFolder.inbox);
      final afterIds =
          repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id).toSet();

      expect(batch.length, 20);
      expect(afterIds.length, beforeIds.length + batch.length);
      expect(afterIds, containsAll(beforeIds));
    });

    test('markAsRead and markAsUnread update state', () async {
      final repo = MockMailRepository();
      final target = repo.getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isRead);
      final targetId = target.id;

      await repo.markAsRead([targetId]);
      expect(repo.getEmailsInFolder(MailFolder.inbox)
              .firstWhere((e) => e.id == targetId)
              .isRead,
          isTrue);

      await repo.markAsUnread([targetId]);
      expect(repo.getEmailsInFolder(MailFolder.inbox)
              .firstWhere((e) => e.id == targetId)
              .isRead,
          isFalse);
    });

    test('setPinned toggles the pin state', () async {
      final repo = MockMailRepository();
      final target = repo.getEmailsInFolder(MailFolder.inbox).first;
      final targetId = target.id;
      final wasPinned = target.isPinned;

      await repo.setPinned([targetId], !wasPinned);
      expect(repo.getEmailsInFolder(MailFolder.inbox)
              .firstWhere((e) => e.id == targetId)
              .isPinned,
          !wasPinned);

      await repo.setPinned([targetId], wasPinned);
      expect(repo.getEmailsInFolder(MailFolder.inbox)
              .firstWhere((e) => e.id == targetId)
              .isPinned,
          wasPinned);
    });

    test('at most 3 mails can be pinned at the same time', () async {
      final repo = MockMailRepository();
      final unpinned = repo
          .getEmailsInFolder(MailFolder.inbox)
          .where((e) => !e.isPinned)
          .take(3)
          .map((e) => e.id)
          .toList();
      expect(unpinned.length, 3);

      // Seed starts with 2 pinned mails: the first extra pin fills the
      // third slot, the second one is ignored.
      await repo.setPinned([unpinned[0]], true);
      await repo.setPinned([unpinned[1], unpinned[2]], true);

      final pinned = repo.getEmailsInFolder(MailFolder.pinned);
      expect(pinned.length, MailRepository.maxPinnedMails);
      expect(pinned.map((e) => e.id), contains(unpinned[0]));
      expect(pinned.map((e) => e.id), isNot(contains(unpinned[1])));

      // Unpinning frees a slot again.
      await repo.setPinned([unpinned[0]], false);
      await repo.setPinned([unpinned[1]], true);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(unpinned[1]),
      );
    });

    test('moveToTrash moves a mail into the trash folder', () async {
      final repo = MockMailRepository();
      final inboxMail = repo.getEmailsInFolder(MailFolder.inbox).first;
      expect(inboxMail.folder, isNot(MailFolder.trash));

      await repo.moveToTrash([inboxMail.id]);
      expect(repo.getEmailsInFolder(MailFolder.trash).map((e) => e.id),
          contains(inboxMail.id));
      expect(repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
          isNot(contains(inboxMail.id)));
    });

    test('moveToFolder moves the mail and notifies', () async {
      final repo = MockMailRepository();
      var notified = 0;
      repo.addListener(() => notified++);

      final mail = repo.getEmailsInFolder(MailFolder.inbox).first;
      await repo.moveToFolder([mail.id], MailFolder.spam);

      expect(notified, greaterThan(0));
      expect(repo.getEmailsInFolder(MailFolder.spam).map((e) => e.id),
          contains(mail.id));
    });

    test('sendEmail lands in Sent, saveDraft in Drafts', () async {
      final repo = MockMailRepository();
      await repo.login(email: 'me@kaydet.app', password: 'secret1');

      final sent = await repo.sendEmail(
        to: ['alice@example.com'],
        subject: 'Hello',
        body: 'Hi Alice',
      );
      expect(sent.folder, MailFolder.sent);
      expect(sent.isRead, isTrue);
      expect(repo.getEmailsInFolder(MailFolder.sent).map((e) => e.id),
          contains(sent.id));

      final draft = await repo.saveDraft(
        to: ['alice@example.com'],
        subject: 'Unfinished',
        body: 'Half written',
      );
      expect(draft.folder, MailFolder.drafts);
      expect(repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
          contains(draft.id));
    });

    test('sendEmail with attachments preserves the metadata', () async {
      final repo = MockMailRepository();
      final sent = await repo.sendEmail(
        to: ['alice@example.com'],
        subject: 'With files',
        body: 'Here they are',
        attachments: const [
          Attachment(name: 'report.pdf', sizeBytes: 2048, mimeType: 'pdf'),
          Attachment(
              name: 'a-very-very-long-attachment-filename.pdf',
              sizeBytes: 10 * 1024 * 1024),
        ],
      );

      expect(sent.folder, MailFolder.sent);
      expect(sent.attachments.length, 2);
      expect(sent.attachments.first.name, 'report.pdf');
      expect(sent.attachments.first.sizeBytes, 2048);
      expect(sent.attachments.first.sizeLabel, '2 KB');
      expect(sent.attachments.last.sizeLabel, '10.0 MB');

      // The stored mail in Sent keeps the same attachment metadata.
      final stored = repo
          .getEmailsInFolder(MailFolder.sent)
          .firstWhere((e) => e.id == sent.id);
      expect(stored.attachments.map((a) => a.name), contains('report.pdf'));
      expect(stored.attachments.last.sizeBytes, 10 * 1024 * 1024);
    });

    test('saveDraft keeps attachment metadata in the draft', () async {
      final repo = MockMailRepository();
      final draft = await repo.saveDraft(
        to: ['alice@example.com'],
        subject: '',
        body: '',
        attachments: const [
          Attachment(name: 'draft-notes.txt', sizeBytes: 512),
        ],
      );
      expect(draft.folder, MailFolder.drafts);
      expect(draft.attachments.single.name, 'draft-notes.txt');
      expect(draft.attachments.single.sizeBytes, 512);
    });

    test('labels can be listed and created', () async {
      final repo = MockMailRepository();
      expect(repo.getLabels(), isNotEmpty);

      final label = await repo.createLabel(
          name: 'Clients', color: const Color.fromARGB(255, 100, 150, 200));
      expect(repo.getLabels().map((l) => l.id), contains(label.id));
    });
  });
}