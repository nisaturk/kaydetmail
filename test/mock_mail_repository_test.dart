import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/data/mock/mock_email_generator.dart';
import 'package:kaydetmail/data/mock/mock_emails.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';

void main() {
  group('mock data', () {
    test('seed email ids are unique', () {
      final ids = MockEmails.seed.map((e) => e.id).toSet();
      expect(ids.length, MockEmails.seed.length);
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

    test('getEmailsInFolder filters by folder and sorts newest first',
        () async {
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

      for (var i = 1; i < inbox.length; i++) {
        expect(inbox[i - 1].timestamp.isAfter(inbox[i].timestamp), isTrue);
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

    test('labels can be listed and created', () async {
      final repo = MockMailRepository();
      expect(repo.getLabels(), isNotEmpty);

      final label = await repo.createLabel(
          name: 'Clients', color: const Color.fromARGB(255, 100, 150, 200));
      expect(repo.getLabels().map((l) => l.id), contains(label.id));
    });
  });
}