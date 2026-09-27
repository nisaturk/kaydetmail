import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/compose_prefill.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/models/mail_security.dart';
import 'package:kaydetmail/models/reply_reminder.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:kaydetmail/utils/conversation_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _message(String id, String sender, String body, int day) => Email(
  id: id,
  accountId: 'acc',
  threadId: 't1',
  senderName: sender,
  senderEmail: '${sender.toLowerCase()}@example.com',
  recipients: const ['ben@example.com'],
  subject: 'Proje',
  bodyText: body,
  timestamp: DateTime(2026, 9, day),
  isRead: true,
);

class _ThreadRepo extends MailRepository {
  final older = _message(
    'm1',
    'Ayse',
    'İlk mesaj gövdesi.\n\n-- \nAyşe Yılmaz\nŞirket A.Ş.',
    20,
  );
  final newer = _message(
    'm2',
    'Mehmet',
    'Tamam, bakıyorum.\n\n20 Eyl tarihinde Ayşe yazdı:\n> İlk mesaj gövdesi.',
    21,
  );
  final List<String> prefillSources = [];
  bool failPrefill = false;
  final List<String> replied = [];
  bool showDiagnostics = false;
  bool failMarkRead = false;
  bool openedUnread = false;
  bool starred = false;

  List<Email> get _thread => [
    showDiagnostics
        ? newer.copyWith(
            isRead: !openedUnread,
            trackingPixelHosts: const ['tracker.example'],
            remoteImageHosts: const ['tracker.example'],
            remoteImagesAllowed: true,
            security: const MailContentSecurity(signed: 'SMime'),
          )
        : newer.copyWith(isRead: !openedUnread, isStarred: starred),
    older,
  ];

  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'acc', email: 'ben@example.com'),
  ];

  @override
  MailAccount? getAccount(String accountId) => accounts.first;

  @override
  Future<Email?> getEmail(String id) async =>
      _thread.where((m) => m.id == id).firstOrNull;

  /// Local-only copies (e.g. a send echo) the cache holds on top of the
  /// server conversation.
  List<Email> cached = const [];
  void replaceCached(List<Email> copies) {
    cached = copies;
    notifyListeners();
  }

  @override
  List<Email> getThreadEmails(String threadId) => [..._thread, ...cached];

  @override
  Future<List<Email>> fetchThreadEmails(String threadId) async => _thread;

  @override
  List<Email> getAllEmails() => _thread;

  @override
  List<MailLabel> getLabels() => const [];

  @override
  List<ReplyReminder> getReplyReminders() => const [];

  @override
  Future<void> markAsRead(List<String> ids) async {
    if (failMarkRead) throw StateError('read failed');
  }

  @override
  Future<void> setStarred(List<String> ids, bool value) async {
    starred = value;
    notifyListeners();
  }

  @override
  Future<void> markAsReplied(List<String> ids) async => replied.addAll(ids);

  @override
  Future<List<MailIdentity>> listIdentities(
    String accountId, {
    bool refresh = false,
  }) async => const [];

  @override
  Future<ComposePrefill> getComposePrefill(
    String sourceMailId,
    String mode,
  ) async {
    prefillSources.add('$mode:$sourceMailId');
    if (failPrefill) throw StateError('stop before compose');
    return ComposePrefill(
      sourceMailId: sourceMailId,
      to: const ['ayse@example.com'],
      cc: const [],
      suggestedSubject: 'Re: Proje',
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('conversation text helpers', () {
    test('collapses quoted replies and the signature block', () {
      final quoted = collapseQuotedText(
        'Tamam.\n\n20 Eyl tarihinde Ayşe yazdı:\n> eski',
      );
      expect(quoted.collapsed, isTrue);
      expect(quoted.visible, 'Tamam.');

      final signed = collapseQuotedText('Merhaba\n-- \nAyşe');
      expect(signed.visible, 'Merhaba');

      final allQuote = collapseQuotedText('> sadece alıntı');
      expect(allQuote.collapsed, isFalse);
    });

    test('summarizes unique senders oldest first with a count', () {
      final messages = [
        _message('c', 'Ali', '', 3),
        _message('b', 'Mehmet', '', 2),
        _message('a', 'Ayse', '', 1),
        _message('d', 'Ayse', '', 4),
      ];
      expect(threadParticipantSummary(messages), 'Ayse, Mehmet, Ali · 4 ileti');
    });
  });

  group('conversation view', () {
    late _ThreadRepo repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppSettingsController.resetForTest();
      PendingSendQueue.instance.useStoreForTest(OutboxStore.inMemory());
      repo = _ThreadRepo();
      AppConfig.mailRepositoryForTest = repo;
    });

    tearDown(() {
      PendingSendQueue.instance.cancelAll();
      AppConfig.resetForTest();
    });

    Future<void> open(WidgetTester tester, String id) async {
      await tester.pumpWidget(MaterialApp(home: MailDetailScreen(emailId: id)));
      await tester.pumpAndSettle();
    }

    testWidgets('mark-read failure keeps detail visible and reports error', (
      tester,
    ) async {
      repo
        ..openedUnread = true
        ..failMarkRead = true;

      await open(tester, 'm2');

      expect(find.text('Tamam, bakıyorum.'), findsOneWidget);
      expect(find.textContaining('İşlem başarısız:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('star action uses a filled amber icon when starred', (
      tester,
    ) async {
      await open(tester, 'm2');

      expect(find.byIcon(Icons.star_outline), findsOneWidget);
      await tester.tap(find.byTooltip('Yıldızla'));
      await tester.pumpAndSettle();

      final icon = tester.widget<Icon>(find.byIcon(Icons.star));
      expect(icon.color, Colors.amber);
    });

    testWidgets('expand/collapse all and hidden quotes by default', (
      tester,
    ) async {
      await open(tester, 'm2');

      expect(find.text('Ayse, Mehmet · 2 ileti'), findsOneWidget);
      expect(find.textContaining('> İlk mesaj'), findsNothing);
      expect(find.byKey(const Key('message-reply-m1')), findsNothing);

      await tester.tap(find.byKey(const Key('thread-toggle-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-reply-m1')), findsOneWidget);
      expect(find.text('Tümünü kapat'), findsOneWidget);
      // Açık kartta gönderen/alıcı yalnızca kart başlığında görünür; ileti
      // gövdesi aynı başlığı ikinci kez basmaz.
      expect(find.text('Mehmet'), findsOneWidget);
      expect(find.text('mehmet@example.com'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('toggle-quoted-m2')));
      await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('> İlk mesaj'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('thread-toggle-all')));
      await tester.tap(find.byKey(const Key('thread-toggle-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-reply-m2')), findsNothing);
    });

    testWidgets('per-message reply uses that message as the source', (
      tester,
    ) async {
      repo.failPrefill = true;
      await open(tester, 'm2');
      await tester.tap(find.byKey(const Key('thread-toggle-all')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('message-reply-m1')));
      await tester.tap(find.byKey(const Key('message-reply-m1')));
      await tester.pump();

      expect(repo.prefillSources, ['reply:m1']);
    });

    testWidgets('a send echo replaced by the real Sent copy is not duplicated', (
      tester,
    ) async {
      await open(tester, 'm2');
      repo.replaceCached([_message('sent-1', 'Ben', 'Yanıtım', 22)]);
      await tester.pumpAndSettle();
      expect(find.text('Ayse, Mehmet, Ben · 3 ileti'), findsOneWidget);

      repo.replaceCached([_message('m3', 'Ben', 'Yanıtım', 22)]);
      await tester.pumpAndSettle();
      expect(find.text('Ayse, Mehmet, Ben · 3 ileti'), findsOneWidget);
    });

    testWidgets(
      'tracking remains blocked after loading images; signed mail is unverified',
      (tester) async {
        repo.showDiagnostics = true;
        await open(tester, 'm2');
        await tester.tap(find.byKey(const Key('thread-toggle-all')));
        await tester.pumpAndSettle();

        expect(find.text('Takip içeriği engellendi'), findsOneWidget);
        expect(find.text('S/MIME imzalı (doğrulanmadı)'), findsOneWidget);
      },
    );

    testWidgets('quick reply queues a threaded reply through the outbox', (
      tester,
    ) async {
      await open(tester, 'm2');

      await tester.enterText(
        find.byKey(const Key('quick-reply-field')),
        'Teşekkürler',
      );
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('quick-reply-send')));
      await tester.tap(find.byKey(const Key('quick-reply-send')));
      await tester.pumpAndSettle();

      expect(repo.prefillSources, ['reply:m2']);
      expect(repo.replied, ['m2']);
      expect(find.text('Yanıt gönderiliyor'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('quick-reply-field')),
      );
      expect(field.controller!.text, isEmpty);

      PendingSendQueue.instance.cancelAll();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      // Aksiyonlu SnackBar varsayılan olarak kalıcı; geri alma süresi
      // bitince kapanmalı.
      expect(find.text('Yanıt gönderiliyor'), findsNothing);
    });
  });
}
