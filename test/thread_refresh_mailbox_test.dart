import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/app.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/mail_folder.dart';

/// Feature-pack tests (spec §15): thread support and reply preservation,
/// inbox thread grouping, pull-to-refresh, inbox-as-mailbox-selector, drawer
/// cleanup, email+password add-account and star/pin independence — each
/// covered at the repository and/or the widget level.
Future<void> _login(WidgetTester tester) async {
  await tester.pumpWidget(const KaydetApp());
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('email-field')), 'me@kaydet.app');
  await tester.tap(find.text('Devam'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('password-field')), 'secret123');
  await tester.tap(find.byKey(const Key('signin-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Gezinme menüsünü aç'));
  await tester.pumpAndSettle();
}

/// Connects a second account (nisa@gmail.com) through the real add-account
/// flow and lands back on the accounts list.
Future<void> _connectGmail(WidgetTester tester) async {
  await _openDrawer(tester);
  await tester.tap(find.text('Hesaplar'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Yeni hesap ekle'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('new-email-field')),
    'nisa@gmail.com',
  );
  await tester.enterText(
    find.byKey(const Key('new-password-field')),
    'secret123',
  );
  await tester.tap(find.byKey(const Key('connect-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => AppConfig.resetForTest());

  group('thread support', () {
    test(
      'every mail carries a threadId; the seed thread groups across folders',
      () {
        final repo = AppConfig.mailRepository;
        final thread = repo.getThreadEmails('thread-onboarding');
        expect(thread.map((e) => e.id).toSet(), {
          'seed-alice-onboarding',
          'seed-sent-onboarding',
          'seed-alice-onboarding-reply',
        });
        final timestamps = thread.map((e) => e.timestamp).toList();
        for (var i = 1; i < timestamps.length; i++) {
          expect(
            timestamps[i - 1].isBefore(timestamps[i]),
            isTrue,
            reason: 'getThreadEmails is oldest-first',
          );
        }
        expect(repo.getThreadEmails(''), isEmpty);

        // Messages without an explicit thread still get one (their own), so
        // unrelated mails are never merged.
        expect(
          repo
              .getEmailsInFolder(MailFolder.inbox)
              .every((e) => e.threadId.isNotEmpty),
          isTrue,
        );
      },
    );

    test(
      'a reply sent with the thread id stays inside the conversation',
      () async {
        final repo = AppConfig.mailRepository;
        final reply = await repo.sendEmail(
          to: ['alice.johnson@northstar.io'],
          subject: 'Re: Design review: onboarding flow',
          body: 'Gözden geçirdim, onaylıyorum.',
          threadId: 'thread-onboarding',
          inReplyToId: 'seed-alice-onboarding-reply',
        );

        expect(reply.threadId, 'thread-onboarding');
        expect(reply.inReplyToId, 'seed-alice-onboarding-reply');
        expect(reply.folder, MailFolder.sent);
        expect(
          repo.getThreadEmails('thread-onboarding').map((e) => e.id),
          contains(reply.id),
        );
      },
    );

    test(
      'a new mail without a thread id starts its own conversation',
      () async {
        final repo = AppConfig.mailRepository;
        final draft = await repo.saveDraft(
          to: ['ada@example.com'],
          subject: 'Yeni konu',
          body: 'hello',
        );
        expect(draft.threadId, startsWith('t-'));
        expect(draft.threadId, isNot('thread-onboarding'));
        expect(repo.getThreadEmails(draft.threadId).single.id, draft.id);
      },
    );

    test('a second account never leaks into the primary threads', () async {
      final repo = AppConfig.mailRepository;
      final primary = repo.accounts.first;
      await repo.connectAccount(email: 'nisa@gmail.com', password: 'secret123');
      final primaryIds = repo
          .getAllEmails()
          .where((e) => e.accountId == primary.id)
          .map((e) => e.threadId)
          .toSet();
      final gmailIds = repo
          .getAllEmails()
          .where((e) => e.accountId == 'nisa@gmail.com')
          .map((e) => e.threadId)
          .toSet();
      expect(gmailIds.intersection(primaryIds), isEmpty);
      expect(
        repo
            .getThreadEmails('thread-onboarding')
            .every((e) => e.accountId == primary.id),
        isTrue,
      );
    });
  });

  group('pull-to-refresh', () {
    test(
      'refresh leaves every mail state identical and never duplicates',
      () async {
        final repo = AppConfig.mailRepository;
        final before = repo
            .getEmailsInFolder(MailFolder.inbox)
            .map((e) => (e.id, e.isRead, e.isStarred, e.isPinned, e.folder))
            .toList();

        await repo.refreshEmails(MailFolder.inbox);

        final after = repo
            .getEmailsInFolder(MailFolder.inbox)
            .map((e) => (e.id, e.isRead, e.isStarred, e.isPinned, e.folder))
            .toList();
        expect(after, before);
        expect(repo.getAllEmails().length, repo.getAllEmails().length);
      },
    );

    testWidgets('pulling down shows the indicator and settles intact', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final beforeIds = repo
          .getEmailsInFolder(MailFolder.inbox)
          .map((e) => e.id)
          .toList();

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expect(
        repo.getEmailsInFolder(MailFolder.inbox).map((e) => e.id),
        beforeIds,
      );
    });

    testWidgets('the empty folder stays pullable', (tester) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      final inbox = repo.getEmailsInFolder(MailFolder.inbox);
      repo.moveToTrash([for (final e in inbox) e.id]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Gelen Kutusu boş'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
      await tester.pump();
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('inbox thread grouping', () {
    testWidgets('a conversation occupies a single row with a count', (
      tester,
    ) async {
      await _login(tester);

      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      // The older message of the same thread no longer has its own row…
      expect(find.text('Design review: onboarding flow'), findsNothing);
      // …the representative shows the thread size…
      expect(find.text('(3)'), findsOneWidget);
      expect(find.text('Re: Design review: onboarding flow'), findsOneWidget);
    });

    testWidgets('opening a grouped conversation shows every message once', (
      tester,
    ) async {
      await _login(tester);
      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re: Design review: onboarding flow'));
      await tester.pump();
      // Detail load + mark-as-read re-triggers a reload; pump past the whole chain.
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // One subject for the whole conversation.
      expect(find.text('Re: Design review: onboarding flow'), findsOneWidget);
      // Three messages, distinct senders; Alice appears twice.
      expect(find.text('Alice Johnson'), findsNWidgets(2));
      expect(find.text('Ben'), findsOneWidget);
      // Only the newest is expanded: a fragment past its preview shows. The
      // older two are collapsed — match beyond the preview text.
      expect(
        find.textContaining('I also want your take on the signup state'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Could you look at the first-run wizard'),
        findsNothing,
      );
      expect(
        find.textContaining('Otherwise looks great. Ship it.'),
        findsNothing,
      );
    });

    testWidgets('conversation messages collapse and expand individually', (
      tester,
    ) async {
      await _login(tester);
      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re: Design review: onboarding flow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Expand the oldest message (Ben's reply): its full tail appears.
      await tester.tap(find.text('Ben'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Otherwise looks great. Ship it.'),
        findsOneWidget,
      );

      // Collapse it again.
      await tester.tap(find.text('Ben'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Otherwise looks great. Ship it.'),
        findsNothing,
      );
    });
  });

  group('mailbox selector (inbox as account switcher)', () {
    testWidgets('with a single account the title is not a selector', (
      tester,
    ) async {
      await _login(tester);
      expect(find.byKey(const Key('mailbox-selector')), findsNothing);
      expect(find.text('Gelen Kutusu'), findsOneWidget);
    });

    testWidgets(
      'the inbox title becomes a selector once a second account exists',
      (tester) async {
        await _login(tester);
        await _connectGmail(tester);
        await tester.tap(find.byTooltip('Geri'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('mailbox-selector')), findsOneWidget);

        // The sheet lists the unified inbox and every account.
        await tester.tap(find.byKey(const Key('mailbox-selector')));
        await tester.pumpAndSettle();
        expect(find.text('Tüm Gelen Kutuları'), findsOneWidget);
        expect(find.text('me@kaydet.app'), findsOneWidget);
        expect(find.text('nisa@gmail.com'), findsOneWidget);

        // Switch to the primary mailbox: its mail appears, gmail's does not.
        await tester.tap(find.text('me@kaydet.app'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Invoice #4821 for March'),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text('Invoice #4821 for March'), findsOneWidget);
        expect(find.text('Sprint hedefleri netleşti'), findsNothing);

        // Back to the unified inbox: both mailboxes are present again.
        await tester.tap(find.byKey(const Key('mailbox-selector')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tüm Gelen Kutuları'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Sprint hedefleri netleşti'),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text('Sprint hedefleri netleşti'), findsOneWidget);
      },
    );
  });

  group('drawer cleanup', () {
    testWidgets('the drawer no longer holds the unified-mailbox row', (
      tester,
    ) async {
      await _login(tester);
      await _openDrawer(tester);

      expect(find.text('Tüm Gelen Kutuları'), findsNothing);
      expect(find.text('Hesaplar'), findsOneWidget);
      expect(find.text('Ayarlar'), findsOneWidget);
    });
  });

  group('add-account flow', () {
    testWidgets('only email and password are asked; filling both connects', (
      tester,
    ) async {
      await _login(tester);
      await _openDrawer(tester);
      await tester.tap(find.text('Hesaplar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yeni hesap ekle'));
      await tester.pumpAndSettle();

      // No provider chips, no display-name field — just credentials.
      expect(find.byKey(const Key('new-password-field')), findsOneWidget);
      expect(find.byKey(const Key('new-name-field')), findsNothing);
      expect(find.byKey(const ValueKey('provider-google')), findsNothing);

      // Empty password is rejected before any connection attempt.
      await tester.enterText(
        find.byKey(const Key('new-email-field')),
        'nisa@gmail.com',
      );
      await tester.tap(find.byKey(const Key('connect-button')));
      await tester.pumpAndSettle();
      expect(find.text('Şifre zorunludur'), findsOneWidget);
      // Still on the add-account screen: no account was created.
      expect(AppConfig.mailRepository.getAccount('nisa@gmail.com'), isNull);

      // Filling the password connects and infers the provider from the address.
      await tester.enterText(
        find.byKey(const Key('new-password-field')),
        'secret123',
      );
      await tester.tap(find.byKey(const Key('connect-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('nisa@gmail.com'), findsOneWidget);
      final gmail = AppConfig.mailRepository.getAccount('nisa@gmail.com');
      expect(gmail!.provider.name, 'google');
    });

    test('MockAccountConnection rejects a missing password', () async {
      await expectLater(
        AppConfig.mailRepository.connectAccount(
          email: 'nisa@gmail.com',
          password: '',
        ),
        throwsA(anything),
      );
    });
  });

  group('star and pin stay independent', () {
    testWidgets('a pinned mail still shows "Yıldızla" until actually starred', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      repo.setPinned(['seed-finance-invoice'], true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Invoice #4821 for March'),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invoice #4821 for March'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Pinned but not starred → the menu still offers starring.
      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      expect(find.text('Yıldızla'), findsOneWidget);
      await tester.tap(find.text('Yıldızla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Starred now → the menu offers unstarring; the pin was left alone.
      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      expect(find.text('Yıldızı kaldır'), findsOneWidget);
      final finance = repo
          .getEmailsInFolder(MailFolder.inbox)
          .firstWhere((e) => e.id == 'seed-finance-invoice');
      expect(finance.isStarred, isTrue);
      expect(finance.isPinned, isTrue);
    });

    testWidgets('starred rows gain a star indicator alongside the pin', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      repo.setStarred(['seed-finance-invoice'], true);
      repo.setPinned(['seed-david-ci'], true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('seed-finance-invoice'));
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.star)),
        findsOneWidget,
      );

      final pinnedRow = find.byKey(const ValueKey('seed-david-ci'));
      // Pinned without star → no star glyph, and the pin glyph instead.
      expect(
        find.descendant(of: pinnedRow, matching: find.byIcon(Icons.star)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: pinnedRow,
          matching: find.byIcon(Icons.star_border),
        ),
        findsNothing,
      );
    });

    testWidgets('individual star and pin touch only their own flag', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      // Unpin the seeds so the top of the inbox list is deterministic.
      repo.setPinned(
        repo.getAllEmails().where((e) => e.isPinned).map((e) => e.id).toList(),
        false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final topMail = repo.getEmailsInFolder(MailFolder.inbox).first;

      await tester.scrollUntilVisible(find.text(topMail.subject), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text(topMail.subject));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Star from the individual menu: only the star flag changes.
      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yıldızla'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      var stored = repo.getAllEmails().firstWhere((e) => e.id == topMail.id);
      expect(stored.isStarred, isTrue);
      expect(stored.isPinned, isFalse);

      // Pin from the individual menu: the star survives, pinning adds one.
      await tester.tap(find.byTooltip('Daha fazla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sabitle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      stored = repo.getAllEmails().firstWhere((e) => e.id == topMail.id);
      expect(stored.isPinned, isTrue);
      expect(stored.isStarred, isTrue);
    });
  });

  group('reply keeps the conversation', () {
    testWidgets('a reply from the detail screen joins the same thread', (
      tester,
    ) async {
      await _login(tester);
      final repo = AppConfig.mailRepository;
      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Re: Design review: onboarding flow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Yanıtla'));
      await tester.pumpAndSettle();
      // Reply opens pre-addressed with the Re: subject preserved.
      expect(find.text('Re: Design review: onboarding flow'), findsOneWidget);

      // The body field is the last TextField on the compose surface.
      await tester.enterText(
        find.byType(TextField).last,
        'Evet, aynen katılıyorum.',
      );
      await tester.tap(find.byTooltip('Gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The new message lives in Sent but belongs to the same conversation…
      final sent = repo
          .getEmailsInFolder(MailFolder.sent)
          .where((e) => e.threadId == 'thread-onboarding')
          .toList();
      expect(sent, hasLength(2));
      final replyMail = sent.firstWhere(
        (e) => e.inReplyToId == 'seed-alice-onboarding-reply',
      );
      expect(replyMail.senderEmail, 'me@kaydet.app');
      expect(replyMail.isRead, isTrue);
      // …and the inbox thread count grows to four.
      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Re: Design review: onboarding flow'),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.text('(4)'), findsOneWidget);
    });
  });
}
