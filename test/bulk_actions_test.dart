import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/data/mock/mock_emails.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';

void main() {
  group('bulk actions', () {
    test('moveToTrash keeps the mail in the repository', () async {
      final repo = MockMailRepository();
      final mail = repo.getEmailsInFolder(MailFolder.inbox).first;

      await repo.moveToTrash([mail.id]);

      final trash = repo.getEmailsInFolder(MailFolder.trash);
      expect(trash.map((e) => e.id), contains(mail.id));

      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      expect(inbox.map((e) => e.id), isNot(contains(mail.id)));
    });

    test('moveToFolder changes the folder', () async {
      final repo = MockMailRepository();
      final mail = repo.getEmailsInFolder(MailFolder.inbox).first;

      await repo.moveToFolder([mail.id], MailFolder.spam);

      final spam = repo.getEmailsInFolder(MailFolder.spam);
      expect(spam.map((e) => e.id), contains(mail.id));
    });

    test('archive moves mail out of inbox', () async {
      final repo = MockMailRepository();
      final mail = repo.getEmailsInFolder(MailFolder.inbox).first;

      await repo.moveToFolder([mail.id], MailFolder.archive);

      expect(
        repo
            .getEmailsInFolder(MailFolder.inbox)
            .map((e) => e.id),
        isNot(contains(mail.id)),
      );
    });
  });

  group('labels on emails', () {
    test('addLabelsToEmails adds the label id', () async {
      final repo = MockMailRepository();
      final mail = repo.getEmailsInFolder(MailFolder.inbox).first;

      await repo.addLabelsToEmails([mail.id], ['lab-work']);

      final updated = await repo.getEmail(mail.id);
      expect(updated!.labelIds, contains('lab-work'));
    });

    test('removeLabelsFromEmails removes the label id', () async {
      final repo = MockMailRepository();
      final mail = MockEmails.seed.firstWhere((e) => e.id == 'seed-welcome');
      expect(mail.labelIds, contains('lab-important'));

      await repo.removeLabelsFromEmails([mail.id], ['lab-important']);

      final updated = await repo.getEmail(mail.id);
      expect(updated!.labelIds, isNot(contains('lab-important')));
    });

    test('createLabel adds a new label to getLabels()', () async {
      final repo = MockMailRepository();
      final before = repo.getLabels().length;

      await repo.createLabel(name: 'Urgent', color: const Color(0xFFE00000));

      expect(repo.getLabels().length, before + 1);
    });
  });

  group('compose / send / draft', () {
    test('sendEmail places mail in Sent', () async {
      final repo = MockMailRepository();
      final sent = await repo.sendEmail(
        to: ['bob@example.com'],
        subject: 'Test',
        body: 'Hello Bob',
      );
      expect(sent.folder, MailFolder.sent);
      expect(repo.getEmailsInFolder(MailFolder.sent).map((e) => e.id),
          contains(sent.id));
    });

    test('saveDraft places mail in Drafts', () async {
      final repo = MockMailRepository();
      final draft = await repo.saveDraft(
        to: ['alice@example.com'],
        subject: 'Draft subject',
        body: 'Half done',
      );
      expect(draft.folder, MailFolder.drafts);
      expect(repo.getEmailsInFolder(MailFolder.drafts).map((e) => e.id),
          contains(draft.id));
    });
  });
}