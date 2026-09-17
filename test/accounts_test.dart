import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';
import 'package:kaydetmail/services/account_connection.dart';

/// Accounts (spec Â§21 items 1â€“8): connecting, coexistence, switching,
/// removal and active-account state.
MockMailRepository _repo() => MockMailRepository(
  connection: MockAccountConnection(latency: Duration.zero),
);

void main() {
  group('accounts', () {
    test('fresh repository has exactly one connected account', () {
      final repo = _repo();
      expect(repo.accounts.length, 1);
      expect(repo.accounts.single.email, MockMailRepository.demoEmail);
      expect(repo.activeAccountId, repo.accounts.single.id);
      expect(repo.currentUser, MockMailRepository.demoEmail);
    });

    test('connecting an account adds it with provider and mailbox', () async {
      final repo = _repo();
      final account = await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );

      expect(account.email, 'nisa@gmail.com');
      expect(account.provider, AccountProvider.google);
      expect(repo.accounts.length, 2);
      // The new account arrives with its own starter mailbox.
      await repo.setActiveAccount(account.id);
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      expect(inbox, isNotEmpty);
      expect(inbox.every((e) => e.accountId == account.id), isTrue);
    });

    test('outlook address is detected as Microsoft', () async {
      final repo = _repo();
      final account = await repo.connectAccount(
        email: 'nisa@outlook.com',
        password: 'secret123',
      );
      expect(account.provider, AccountProvider.microsoft);
    });

    test('three or more accounts can coexist', () async {
      final repo = _repo();
      await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );
      await repo.connectAccount(
        email: 'nisa@outlook.com',
        password: 'secret123',
      );
      await repo.connectAccount(
        email: 'nisa@kisisel.com',
        password: 'secret123',
      );

      expect(repo.accounts.length, 4);
      expect(
        repo.accounts.map((a) => a.id).toSet().length,
        repo.accounts.length,
      );
    });

    test('connecting the same email twice does not duplicate it', () async {
      final repo = _repo();
      final first = await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );
      final second = await repo.connectAccount(
        email: 'NISA@gmail.com',
        password: 'secret123',
      );

      expect(repo.accounts.length, 2);
      expect(second.id, first.id);
      expect(repo.activeAccountId, first.id);
    });

    test('account switching scopes the mailbox; null is unified', () async {
      final repo = _repo();
      final gmail = await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );

      await repo.setActiveAccount(gmail.id);
      expect(repo.activeAccountId, gmail.id);
      expect(repo.currentUser, 'nisa@gmail.com');

      await repo.setActiveAccount(null);
      expect(repo.activeAccountId, isNull);

      // Unknown ids are ignored so stray navigation never blanks the list.
      await repo.setActiveAccount('yok@ornek.com');
      expect(repo.activeAccountId, isNull);
    });

    test('removing an account drops only its mails', () async {
      final repo = _repo();
      final primaryId = repo.activeAccountId!;
      final primaryInboxCount = repo.getEmailsInFolder(MailFolder.inbox).length;

      final gmail = await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );
      await repo.setActiveAccount(null);
      final unifiedCount = repo.getAllEmails().length;

      await repo.removeAccount(gmail.id);

      expect(repo.accounts.length, 1);
      expect(repo.getAccount(gmail.id), isNull);
      expect(repo.getAllEmails().every((e) => e.accountId != gmail.id), isTrue);
      await repo.setActiveAccount(primaryId);
      expect(
        repo.getEmailsInFolder(MailFolder.inbox).length,
        primaryInboxCount,
      );
      expect(repo.getAllEmails().length, lessThan(unifiedCount));
    });

    test('removing the active account falls back to unified', () async {
      final repo = _repo();
      final gmail = await repo.connectAccount(
        email: 'nisa@gmail.com',
        password: 'secret123',
      );
      expect(repo.activeAccountId, gmail.id);

      await repo.removeAccount(gmail.id);
      expect(repo.activeAccountId, isNull);
    });

    test('the last remaining account cannot be removed', () async {
      final repo = _repo();
      expect(() => repo.removeAccount(repo.activeAccountId!), throwsStateError);
      expect(repo.accounts.length, 1);
    });

    test('provider inference follows the documented rule', () {
      expect(
        AccountProvider.inferFromEmail('a@gmail.com'),
        AccountProvider.google,
      );
      expect(
        AccountProvider.inferFromEmail('a@hotmail.com'),
        AccountProvider.microsoft,
      );
      expect(
        AccountProvider.inferFromEmail('a@outlook.com'),
        AccountProvider.microsoft,
      );
      expect(
        AccountProvider.inferFromEmail('a@live.com'),
        AccountProvider.microsoft,
      );
      expect(
        AccountProvider.inferFromEmail('a@sirket.com'),
        AccountProvider.other,
      );
    });
  });
}
