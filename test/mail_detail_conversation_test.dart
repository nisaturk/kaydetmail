import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/compose_prefill.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/models/mail_security.dart';
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
  Completer<Email?>? detailGate;
  Completer<List<Email>>? enrichmentGate;
  List<Email>? history;

  List<Email> get _thread =>
      history ??
      [
        older,
        showDiagnostics
            ? newer.copyWith(
                isRead: !openedUnread,
                trackingPixelHosts: const ['tracker.example'],
                remoteImageHosts: const ['tracker.example'],
                remoteImagesAllowed: true,
                security: const MailContentSecurity(signed: 'SMime'),
              )
            : newer.copyWith(isRead: !openedUnread, isStarred: starred),
      ];

  @override
  List<MailAccount> get accounts => const [
    MailAccount(id: 'acc', email: 'ben@example.com'),
  ];

  @override
  MailAccount? getAccount(String accountId) => accounts.first;

  @override
  Future<Email?> getEmail(String id) =>
      detailGate?.future ??
      Future.value(_thread.where((m) => m.id == id).firstOrNull);

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
  Future<List<Email>> fetchThreadEmails(String threadId) async =>
      enrichmentGate?.future ?? _thread;

  @override
  List<Email> getAllEmails() => _thread;

  @override
  List<MailLabel> getLabels() => const [];

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

    testWidgets('list seed renders before detail request completes', (
      tester,
    ) async {
      repo.detailGate = Completer<Email?>();

      await tester.pumpWidget(
        MaterialApp(
          home: MailDetailScreen(emailId: repo.newer.id, seed: repo.newer),
        ),
      );
      await tester.pump();

      expect(find.text('Tamam, bakıyorum.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      repo.detailGate!.complete(repo.newer);
      await tester.pumpAndSettle();
    });

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
      expect(find.byIcon(Icons.star_outline), findsWidgets);
      await tester.tap(find.byTooltip('Yıldızla').first);
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byIcon(Icons.star).first);
      expect(icon.color, Colors.amber);
    });

    testWidgets('plain and HTML bodies use the available thread width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo.history = [
        repo.older.copyWith(bodyText: 'Kısa eski ileti'),
        repo.newer.copyWith(bodyText: 'Kısa ileti', bodyHtml: '<p>Kısa ileti</p>'),
      ];
      await open(tester, 'm2');
      expect(tester.getSize(find.byKey(const Key('message-body-m2'))).width, 328);
      await tester.scrollUntilVisible(
        find.byKey(const Key('message-body-m1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(find.byKey(const Key('message-body-m1'))).width, 328);
      await tester.binding.setSurfaceSize(const Size(900, 700));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const Key('message-body-m1'))).width, 868);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide HTML table stays inside the available message width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo.history = [
        repo.newer.copyWith(
          bodyText: 'Tablo',
          bodyHtml: '<p>Normal metin</p><table style="width:1200px">'
              '<tr><td>Birinci sütun</td><td>İkinci sütun</td></tr></table>',
        ),
      ];
      await open(tester, 'm2');
      expect(tester.getSize(find.byKey(const Key('message-body-m2'))).width, 288);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'm2 opens first, older m1 stays expanded; quote alone toggles',
      (tester) async {
        await open(tester, 'm2');
        expect(find.byKey(const Key('thread-toggle-all')), findsNothing);
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(scroll.pixels, 0);
        expect(find.text('Mehmet'), findsOneWidget);
        expect(find.byType(Card), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('message-reply-m1')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('İlk mesaj gövdesi.'), findsWidgets);
        expect(find.byKey(const Key('message-reply-m1')), findsOneWidget);
        expect(find.textContaining('> İlk mesaj'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const Key('toggle-quoted-m2')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
        await tester.pumpAndSettle();
        expect(find.textContaining('> İlk mesaj'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('message-recipients-m2')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('message-recipients-m2')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Kimden: '), findsOneWidget);
      },
    );

    testWidgets('compact header reveals recipients only on summary tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester, 'm2');

      expect(find.text('E-posta'), findsNothing);
      expect(find.text('bana'), findsWidgets);
      expect(find.textContaining('Kimden: '), findsNothing);
      expect(find.byKey(const Key('quick-reply')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('message-recipients-m2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Kimden: '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening m1 excludes newer m2 and replies target m1', (
      tester,
    ) async {
      repo.failPrefill = true;
      await open(tester, 'm1');
      expect(find.textContaining('İlk mesaj gövdesi.'), findsWidgets);
      expect(find.text('Tamam, bakıyorum.'), findsNothing);
      await tester.tap(find.byKey(const Key('message-reply-m1')));
      await tester.pump();
      expect(repo.prefillSources, ['reply:m1']);
    });

    testWidgets('same timestamp follows server order, not cache order', (
      tester,
    ) async {
      final m3 = _message('m3', 'Ali', 'Üçüncü ileti', 21);
      repo.history = [repo.older, repo.newer, m3];
      await open(tester, 'm2');
      expect(find.text('Üçüncü ileti'), findsNothing);
      expect(find.text('Tamam, bakıyorum.'), findsOneWidget);
      await open(tester, 'm3');
      expect(find.text('Tamam, bakıyorum.'), findsOneWidget);
    });

    testWidgets('m4 opens at zero; delayed older history keeps scroll offset', (
      tester,
    ) async {
      final m4 = _message(
        'm4',
        'Derya',
        List.filled(36, 'Açılan ileti').join('\n'),
        24,
      );
      final m3 = _message('m3', 'Ali', 'Üçüncü ileti', 23);
      repo.history = [repo.older, repo.newer, m3, m4];
      repo.enrichmentGate = Completer<List<Email>>();
      await tester.pumpWidget(
        MaterialApp(
          home: MailDetailScreen(emailId: 'm4', seed: m4),
        ),
      );
      await tester.pump();
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(scroll.pixels, 0);
      scroll.jumpTo(120);
      await tester.pump();
      repo.history = [repo.older, repo.newer, m3, m4];
      repo.enrichmentGate!.complete(repo.history!);
      await tester.pump();
      expect(scroll.pixels, 120);
      expect(find.byKey(const Key('thread-toggle-all')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('message-reply-m3')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('message-reply-m3')), findsOneWidget);
    });

    testWidgets('per-message reply uses that message as the source', (
      tester,
    ) async {
      repo.failPrefill = true;
      await open(tester, 'm2');
      expect(find.byKey(const Key('thread-toggle-all')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('message-reply-m1')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('message-reply-m1')));
      await tester.pump();

      expect(repo.prefillSources, ['reply:m1']);
    });

    testWidgets('newer send echoes stay out of opened m2 history', (
      tester,
    ) async {
      await open(tester, 'm2');
      repo.replaceCached([_message('m3', 'Ben', 'Yanıtım', 22)]);
      await tester.pumpAndSettle();
      expect(find.text('Yanıtım'), findsNothing);
      expect(find.text('Tamam, bakıyorum.'), findsOneWidget);
    });

    testWidgets(
      'tracking remains blocked after loading images; signed mail is unverified',
      (tester) async {
        repo.showDiagnostics = true;
        await open(tester, 'm2');
        expect(find.byKey(const Key('thread-toggle-all')), findsNothing);

        expect(find.text('Takip içeriği engellendi'), findsOneWidget);
        expect(find.text('S/MIME imzalı (doğrulanmadı)'), findsOneWidget);
      },
    );

    testWidgets('quick reply queues a threaded reply through the outbox', (
      tester,
    ) async {
      await open(tester, 'm2');
      await tester.scrollUntilVisible(
        find.byKey(const Key('quick-reply-field')),
        250,
        scrollable: find.byType(Scrollable).first,
      );

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
