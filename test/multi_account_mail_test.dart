import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';
import 'package:kaydetmail/services/account_connection.dart';

/// Multi-account mail behavior (spec §21 items 9–27): mailbox isolation,
/// unified inbox, star/pin regression and combined flag independence.
MockMailRepository _repo() => MockMailRepository(
  connection: MockAccountConnection(latency: Duration.zero),
);

String get _primaryId => MockMailRepository.demoEmail;

/// Fresh repo with primary + gmail + outlook connected. Active ends on the
/// last connected account; each test sets its own scope explicitly.
Future<MockMailRepository> _threeAccounts() async {
  final repo = _repo();
  await repo.connectAccount(
    email: 'nisa@gmail.com',
    password: 'secret123',
  );
  await repo.connectAccount(
    email: 'nisa@outlook.com',
    password: 'secret123',
  );
  return repo;
}

Future<void> _freePinSlots(MockMailRepository repo) async {
  final pinned = repo.getAllEmails().where((e) => e.isPinned).toList();
  await repo.setPinned([for (final e in pinned) e.id], false);
}

void main() {
  group('mailbox isolation', () {
    test('account A lists only account A mails', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      for (final folder in MailFolder.values) {
        final mails = repo.getEmailsInFolder(folder);
        expect(
          mails.every((e) => e.accountId == _primaryId),
          isTrue,
          reason: 'folder $folder leaked another account',
        );
      }
    });

    test('account B lists only account B mails', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount('nisa@gmail.com');
      for (final folder in MailFolder.values) {
        final mails = repo.getEmailsInFolder(folder);
        expect(
          mails.every((e) => e.accountId == 'nisa@gmail.com'),
          isTrue,
          reason: 'folder $folder leaked another account',
        );
      }
    });

    test('unified inbox contains both mailboxes without duplicates', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      final aCount = repo.getEmailsInFolder(MailFolder.inbox).length;
      await repo.setActiveAccount('nisa@gmail.com');
      final bCount = repo.getEmailsInFolder(MailFolder.inbox).length;
      expect(bCount, greaterThan(0));
      await repo.setActiveAccount('nisa@outlook.com');
      final cCount = repo.getEmailsInFolder(MailFolder.inbox).length;
      expect(cCount, greaterThan(0));

      await repo.setActiveAccount(null);
      final unified = repo.getEmailsInFolder(MailFolder.inbox);
      expect(unified.length, aCount + bCount + cCount);
      expect(
        unified.map((e) => e.id).toSet().length,
        unified.length,
        reason: 'unified inbox duplicated a mail',
      );
      expect(unified.any((e) => e.id == 'seed-welcome'), isTrue);
      expect(
        unified.any(
          (e) =>
              e.accountId == 'nisa@gmail.com' &&
              e.subject == 'Sprint hedefleri netleşti',
        ),
        isTrue,
      );
    });

    test('every mail carries a known originating account id', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(null);
      for (final mail in repo.getAllEmails()) {
        expect(mail.accountId, isNotEmpty);
        expect(repo.getAccount(mail.accountId), isNotNull);
      }
    });

    test('operations in A leave B untouched', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => e.isRead);
      final bBefore = await repo
          .setActiveAccount('nisa@gmail.com')
          .then(
            (_) => repo
                .getEmailsInFolder(MailFolder.inbox)
                .map((e) => e.id)
                .toSet(),
          );

      await repo.setActiveAccount(_primaryId);
      await repo.markAsUnread([target.id]);
      await repo.moveToTrash([target.id]);

      await repo.setActiveAccount('nisa@gmail.com');
      expect(
        repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id).toSet(),
        bBefore,
      );
    });
  });

  group('star regression', () {
    test('star in account inbox surfaces in unified, B unaffected', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned);

      await repo.setStarred([target.id], true);

      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount(null);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount('nisa@gmail.com');
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });

    test('star and unstar from the unified inbox', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(null);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => e.accountId == 'nisa@outlook.com');

      await repo.setStarred([target.id], true);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount('nisa@outlook.com');
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );

      await repo.setActiveAccount(null);
      await repo.setStarred([target.id], false);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });

    test('star state survives account switching and detail reads', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned);
      await repo.setStarred([target.id], true);

      await repo.setActiveAccount('nisa@gmail.com');
      await repo.setActiveAccount('nisa@outlook.com');
      await repo.setActiveAccount(null);
      await repo.setActiveAccount(_primaryId);

      // The detail screen reads through getEmail — the flag must still hold.
      expect((await repo.getEmail(target.id))?.isStarred, isTrue);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
    });
  });

  group('pin regression', () {
    test('pin in account inbox surfaces in unified, B unaffected', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned);

      await repo.setPinned([target.id], true); // fills the 3rd global slot
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount(null);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount('nisa@gmail.com');
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });

    test('pin and unpin from the unified inbox', () async {
      final repo = await _threeAccounts();
      await _freePinSlots(repo);
      await repo.setActiveAccount(null);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => e.accountId == 'nisa@outlook.com');

      await repo.setPinned([target.id], true);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );
      await repo.setActiveAccount('nisa@outlook.com');
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        contains(target.id),
      );

      await repo.setPinned([target.id], false);
      expect(
        repo.getEmailsInFolder(MailFolder.pinned).map((e) => e.id),
        isNot(contains(target.id)),
      );
    });

    test('pin state survives account switching', () async {
      final repo = await _threeAccounts();
      await _freePinSlots(repo);
      await repo.setActiveAccount('nisa@gmail.com');
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isPinned);
      await repo.setPinned([target.id], true);

      await repo.setActiveAccount(_primaryId);
      await repo.setActiveAccount(null);
      await repo.setActiveAccount('nisa@gmail.com');

      expect((await repo.getEmail(target.id))?.isPinned, isTrue);
    });

    test('pin limit still holds across accounts', () async {
      final repo = await _threeAccounts();
      // Seed starts with 2 pinned mails globally.
      await repo.setActiveAccount(null);
      final candidates = repo
          .getAllEmails()
          .where((e) => !e.isPinned)
          .take(3)
          .map((e) => e.id)
          .toList();

      await repo.setPinned([candidates[0]], true);
      await repo.setPinned([candidates[1], candidates[2]], true);

      final pinned = repo.getEmailsInFolder(MailFolder.pinned);
      expect(pinned.length, MailRepository.maxPinnedMails);
    });
  });

  group('combined flag independence', () {
    test('star and pin are independent', () async {
      final repo = _repo();
      await _freePinSlots(repo);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned);

      await repo.setStarred([target.id], true);
      await repo.setPinned([target.id], true);
      var mail = (await repo.getEmail(target.id))!;
      expect(mail.isStarred, isTrue);
      expect(mail.isPinned, isTrue);

      // Unstarring must not clear the pin (spec §14 example).
      await repo.setStarred([target.id], false);
      mail = (await repo.getEmail(target.id))!;
      expect(mail.isStarred, isFalse);
      expect(mail.isPinned, isTrue);

      // Unpinning must not clear the star.
      await repo.setStarred([target.id], true);
      await repo.setPinned([target.id], false);
      mail = (await repo.getEmail(target.id))!;
      expect(mail.isStarred, isTrue);
      expect(mail.isPinned, isFalse);
    });

    test('star and unread are independent', () async {
      final repo = _repo();
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned && !e.isRead);

      await repo.setStarred([target.id], true);
      await repo.markAsRead([target.id]);
      var mail = (await repo.getEmail(target.id))!;
      expect(mail.isRead, isTrue);
      expect(mail.isStarred, isTrue);

      await repo.markAsUnread([target.id]);
      mail = (await repo.getEmail(target.id))!;
      expect(mail.isRead, isFalse);
      expect(mail.isStarred, isTrue);
    });

    test('pin and unread are independent', () async {
      final repo = _repo();
      await _freePinSlots(repo);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned && !e.isRead);

      await repo.setPinned([target.id], true);
      await repo.markAsRead([target.id]);
      var mail = (await repo.getEmail(target.id))!;
      expect(mail.isRead, isTrue);
      expect(mail.isPinned, isTrue);

      await repo.markAsUnread([target.id]);
      mail = (await repo.getEmail(target.id))!;
      expect(mail.isRead, isFalse);
      expect(mail.isPinned, isTrue);
    });

    test('star, pin and unread coexist correctly', () async {
      final repo = _repo();
      await _freePinSlots(repo);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => !e.isStarred && !e.isPinned && !e.isRead);

      await repo.setStarred([target.id], true);
      await repo.setPinned([target.id], true);
      var mail = (await repo.getEmail(target.id))!;
      expect([mail.isStarred, mail.isPinned, mail.isRead], [true, true, false]);

      await repo.markAsRead([target.id]);
      await repo.setStarred([target.id], false);
      mail = (await repo.getEmail(target.id))!;
      expect([mail.isStarred, mail.isPinned, mail.isRead], [false, true, true]);
    });
  });

  group('cross-account operations', () {
    test('bulk actions in unified touch only the selected ids', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(null);
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      final ids = [
        inbox.firstWhere((e) => e.accountId == _primaryId).id,
        inbox.firstWhere((e) => e.accountId == 'nisa@gmail.com').id,
        inbox.firstWhere((e) => e.accountId == 'nisa@outlook.com').id,
      ];

      await repo.markAsRead(ids);

      final read = {
        for (final m in repo.getAllEmails())
          if (m.isRead) m.id,
      };
      expect(read, containsAll(ids));
      // Sibling mails in the same folders stayed unread where they were.
      await repo.setActiveAccount(_primaryId);
      final untouched = repo
          .getEmailsInFolder(MailFolder.inbox)
          .where((e) => !ids.contains(e.id) && !e.isRead);
      expect(untouched, isNotEmpty);
    });

    test('archive and labels stay account-local', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(null);
      final target = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => e.accountId == 'nisa@gmail.com');

      await repo.moveToFolder([target.id], MailFolder.archive);
      await repo.addLabelsToEmails([target.id], ['lab-work']);

      await repo.setActiveAccount('nisa@gmail.com');
      final archived = repo
          .getEmailsInFolder(MailFolder.archive)
          .map((e) => e.id);
      expect(archived, contains(target.id));

      await repo.setActiveAccount('nisa@outlook.com');
      expect(
        repo.getEmailsInFolder(MailFolder.archive).map((e) => e.id),
        isNot(contains(target.id)),
      );
      final stored = (await repo.getEmail(target.id))!;
      expect(stored.labelIds, contains('lab-work'));
    });

    test('unified search spans all accounts', () async {
      final repo = await _threeAccounts();
      await repo.setActiveAccount(_primaryId); // scoped — search ignores scope
      final all = repo.getAllEmails();
      final sprintHits = all.where((e) => e.matchesQuery('sprint')).toList();
      // The starter template exists in every added mailbox: unified search
      // finds the mail wherever it lives.
      expect(
        sprintHits.map((e) => e.accountId).toSet(),
        containsAll(['nisa@gmail.com', 'nisa@outlook.com']),
      );
      expect(all.where((e) => e.matchesQuery('invoice')), isNotEmpty);
    });

    test('compose from an account files the mail there', () async {
      final repo = await _threeAccounts();
      final sent = await repo.sendEmail(
        to: ['alici@ornek.com'],
        subject: 'Hesaplar arası',
        body: ' outlook hesabından',
        fromAccountId: 'nisa@outlook.com',
      );
      expect(sent.accountId, 'nisa@outlook.com');

      await repo.setActiveAccount('nisa@outlook.com');
      expect(
        repo.getEmailsInFolder(MailFolder.sent).map((e) => e.id),
        contains(sent.id),
      );
      await repo.setActiveAccount(_primaryId);
      expect(
        repo.getEmailsInFolder(MailFolder.sent).map((e) => e.id),
        isNot(contains(sent.id)),
      );
    });
  });
}
