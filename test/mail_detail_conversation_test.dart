import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/compose_prefill.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/models/mail_account.dart';
import 'package:kaydetmail/models/mail_label.dart';
import 'package:kaydetmail/models/mail_folder.dart';
import 'package:kaydetmail/models/mail_signature.dart';
import 'package:kaydetmail/models/mail_security.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/screens/mail_detail_screen.dart';
import 'package:kaydetmail/screens/mail_detail/message_body.dart';
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
  final List<String> deletedIds = [];

  @override
  Future<void> deletePermanently(List<String> ids) async {
    deletedIds.addAll(ids);
    history = _thread.where((mail) => !ids.contains(mail.id)).toList();
    notifyListeners();
  }

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
  group('conversation body separation', () {
    test('plain replies and signatures toggle independently in source order', () {
      final body = ConversationBody.text(
        'Current answer\n-- \nMy signature\n'
        'On Tuesday, Alice wrote:\n> Previous answer\n> -- \n> Alice signature',
      );
      expect(body.hasQuotes, isTrue);
      expect(body.hasSignatures, isTrue);
      expect(
        body.render(showQuotes: false, showSignatures: false),
        'Current answer',
      );
      final signed = body.render(showQuotes: false, showSignatures: true);
      expect(signed, contains('My signature'));
      expect(signed, isNot(contains('Previous answer')));
      final quoted = body.render(showQuotes: true, showSignatures: false);
      expect(quoted, contains('Previous answer'));
      expect(quoted, isNot(contains('signature')));
      final all = body.render(showQuotes: true, showSignatures: true);
      expect(all, contains('My signature'));
      expect(all, contains('Alice signature'));
    });

    test(
      'inline answers and ordinary content are not mistaken for metadata',
      () {
        final body = ConversationBody.text(
          '> Question\nAnswer\n--not a delimiter\nFrom: my notes',
        );
        expect(
          body.render(showQuotes: false, showSignatures: false),
          'Answer\n--not a delimiter\nFrom: my notes',
        );
        final inline = ConversationBody.text(
          'Current\nOn Tuesday, Alice wrote:\n> Question\nMy inline answer',
        );
        expect(
          inline.render(showQuotes: false, showSignatures: false),
          contains('My inline answer'),
        );
        final html = ConversationBody.html(
          '<p>Current</p><blockquote>A literary quotation</blockquote>'
          '<p>gmail_quote is a class name, not metadata in text.</p>',
        );
        expect(html.hasQuotes, isFalse);
        expect(
          html.render(showQuotes: false, showSignatures: false),
          contains('A literary quotation'),
        );
      },
    );

    test(
      'HTML client signatures remain independent from sibling citations',
      () {
        for (final html in [
          '<p>Current</p><div class="gmail_signature">Signature</div>'
              '<div class="gmail_quote">Previous</div>',
          "<p>Current</p><div id='Signature'>Signature</div>"
              "<div id='divRplyFwdMsg'>From: Alice</div><p>Previous</p>Loose tail",
          '<p>Current</p><div class="moz-signature">Signature</div>'
              '<div class="moz-cite-prefix">On Tuesday, Alice wrote:</div>'
              '<blockquote>Previous</blockquote><p>Inline answer</p>',
        ]) {
          final body = ConversationBody.html(html);
          final hidden = body.render(showQuotes: false, showSignatures: false);
          expect(hidden, contains('Current'));
          expect(hidden, isNot(contains('Signature')));
          expect(hidden, isNot(contains('Previous')));
          expect(hidden, isNot(contains('Loose tail')));
          final signature = body.render(
            showQuotes: false,
            showSignatures: true,
          );
          expect(signature, contains('Signature'));
          expect(signature, isNot(contains('Previous')));
          final quotes = body.render(showQuotes: true, showSignatures: false);
          expect(quotes, contains('Previous'));
          expect(quotes, isNot(contains('Signature')));
          if (html.contains('Inline answer')) {
            expect(hidden, contains('Inline answer'));
          }
        }
      },
    );

    test(
      'deduplicates only complete represented quotes and preserves media',
      () {
        final plain = ConversationBody.text(
          'Current\nOn Tuesday, Alice wrote:\n> Previous',
        );
        expect(
          plain.render(
            showQuotes: true,
            showSignatures: false,
            representedBodies: ['Previous'],
          ),
          'Current',
        );
        expect(
          plain.render(
            showQuotes: true,
            showSignatures: false,
            representedBodies: ['Different'],
          ),
          contains('Previous'),
        );
        final html = ConversationBody.html(
          '<p>Current</p><div class="gmail_quote">'
          'Previous<img src="https://example.com/unique.png"></div>',
        );
        expect(
          html.render(
            showQuotes: true,
            showSignatures: false,
            representedBodies: ['Previous'],
          ),
          contains('unique.png'),
        );
        final partial = ConversationBody.text(
          'Current\nOn Tuesday, Alice wrote:\n> Previous\n> Unloaded content',
        );
        expect(
          partial.render(
            showQuotes: true,
            showSignatures: false,
            representedBodies: ['Previous'],
          ),
          contains('Unloaded content'),
        );
        final meaningfulHeader = ConversationBody.text(
          'Current\nOn Tuesday, Alice wrote:\n> Previous\n> From: my private notes',
        );
        expect(
          meaningfulHeader.render(
            showQuotes: true,
            showSignatures: false,
            representedBodies: ['Previous'],
          ),
          contains('my private notes'),
        );
      },
    );

    group('quoted history that the thread already shows', () {
      // Shapes taken from a real thread: Gmail wraps its quote in
      // `gmail_quote`; the other client flattened its history into plain
      // lines inside one <p>, with no quote marker of any kind.
      final first = ConversationBody.text('Mesaj 1\n');
      final second = ConversationBody.html(
        '<div dir="auto">Mesaj 2</div><br>'
        '<div class="gmail_quote"><div class="gmail_attr">On Wed, Sep 30, '
        '2026, 10:41  &lt;<a href="mailto:a@example.com">a@example.com</a>'
        '&gt; wrote:<br></div><blockquote class="gmail_quote">Mesaj 1<br>\n'
        '</blockquote></div>',
      );
      final flat = ConversationBody.html(
        '<p>Mesaj 3<br/><br/>--<br/>Sevgiler,<br/>Nisa Türk<br/><br/>'
        'Çar, 30 Eyl 2026, 10:42 tarihinde b@example.com yazdı:<br/>Mesaj 2<br/>'
        'On Wed, Sep 30, 2026, 10:41  &lt;a@example.com&gt; wrote:<br/>'
        'Mesaj 1</p><blockquote><br/></blockquote><p><br/></p>',
      );
      final earlier = [first, second];

      String render(
        ConversationBody body, {
        bool showQuotes = false,
        List<ConversationBody> thread = const [],
      }) => body.render(
        showQuotes: showQuotes,
        showSignatures: false,
        representedBodies: thread.map((mail) => mail.unquotedText),
        earlier: thread,
      );

      test('flattened html history is a quote: hidden until asked for', () {
        expect(flat.hasQuotes, isTrue);
        final hidden = render(flat, thread: earlier);
        expect(hidden, contains('Mesaj 3'));
        expect(hidden, contains('Nisa Türk'));
        expect(hidden, isNot(contains('yazdı')));
        expect(hidden, isNot(contains('Mesaj 2')));
        expect(hidden, isNot(contains('Mesaj 1')));
      });

      test('flattened history is not repeated when quotes are shown', () {
        final shown = render(flat, showQuotes: true, thread: earlier);
        expect(shown, contains('Mesaj 3'));
        expect(shown, isNot(contains('Mesaj 2')));
        expect(shown, isNot(contains('Mesaj 1')));
      });

      test('flattened history the thread lacks stays available', () {
        final shown = render(
          flat,
          showQuotes: true,
          thread: [ConversationBody.text('Something else entirely')],
        );
        expect(shown, contains('Mesaj 2'));
        expect(shown, contains('Mesaj 1'));
      });

      test('a short quoted reply is recognised as repeating the thread', () {
        final shown = render(second, showQuotes: true, thread: [first]);
        expect(shown, contains('Mesaj 2'));
        expect(shown, isNot(contains('Mesaj 1')));
      });

      test('an attribution before a marked citation keeps the answer', () {
        final body = ConversationBody.html(
          '<p>Current</p><div>On Tuesday, Alice wrote:</div>'
          '<blockquote type="cite">Previous</blockquote>'
          '<p>Inline answer</p>',
        );
        final hidden = render(body);
        expect(hidden, contains('Current'));
        expect(hidden, contains('Inline answer'));
        expect(hidden, isNot(contains('Previous')));
        expect(hidden, isNot(contains('wrote')));
      });

      test('multi-message nested plain quote is hidden when shown', () {
        final body = ConversationBody.text(
          'Mesaj 4\n\nOn Tuesday, Ayse wrote:\n> Mesaj 3\n>\n'
          '> On Monday, Ali wrote:\n>> Mesaj 2',
        );
        expect(
          render(
            body,
            showQuotes: true,
            thread: [
              ConversationBody.text('Mesaj 2'),
              ConversationBody.text(
                'Mesaj 3\nOn Monday, Ali wrote:\n> Mesaj 2',
              ),
            ],
          ),
          'Mesaj 4',
        );
      });

      test('a quote with an image is never dropped for matching text', () {
        final body = ConversationBody.html(
          '<p>Current</p><div class="gmail_quote">Mesaj 1'
          '<img src="https://example.com/a.png"></div>',
        );
        expect(
          render(body, showQuotes: true, thread: [first]),
          contains('a.png'),
        );
      });
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

    testWidgets('permanent delete removes only the opened trashed message', (
      tester,
    ) async {
      repo.history = [
        repo.older.copyWith(folder: MailFolder.trash),
        repo.newer.copyWith(folder: MailFolder.trash),
      ];
      await open(tester, 'm2');
      expect(find.text('2 ileti'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kalıcı olarak sil'));
      await tester.pumpAndSettle();
      expect(find.text('E-posta kalıcı olarak silinsin mi?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Kalıcı olarak sil'));
      await tester.pumpAndSettle();

      expect(repo.deletedIds, ['m2']);
      expect(repo.getAllEmails().map((mail) => mail.id), ['m1']);
      expect(repo.getAllEmails().single.folder, MailFolder.trash);
    });

    testWidgets('wide HTML table stays inside the available message width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo.history = [
        repo.newer.copyWith(
          bodyText: 'Tablo',
          bodyHtml:
              '<p>Normal metin</p><table style="width:1200px">'
              '<tr><td>Birinci sütun</td><td>İkinci sütun</td></tr></table>',
        ),
      ];
      await open(tester, 'm2');
      expect(
        tester.getSize(find.byKey(const Key('message-body-m2'))).width,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'one opened body reveals history and signatures independently',
      (tester) async {
        await open(tester, 'm2');
        expect(find.byKey(const Key('message-history-m1')), findsNothing);
        expect(find.byKey(const Key('message-overflow-m2')), findsOneWidget);
        await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
        await tester.pumpAndSettle();
        expect(find.textContaining('İlk mesaj gövdesi.'), findsOneWidget);
        expect(find.textContaining('> İlk mesaj'), findsNothing);
        expect(find.textContaining('Şirket A.Ş.'), findsNothing);
        expect(find.byKey(const Key('message-overflow-m1')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('toggle-signature-m2')),
        );
        await tester.tap(find.byKey(const Key('toggle-signature-m2')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Şirket A.Ş.'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('toggle-quoted-m2')));
        await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('message-history-m1')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('toggle-quoted-m2')));
        await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Şirket A.Ş.'), findsOneWidget);
      },
    );

    for (final useHtml in [false, true]) {
      testWidgets(
        'single ${useHtml ? 'HTML' : 'plain'} mail has effective independent toggles',
        (tester) async {
          final email = repo.newer.copyWith(
            bodyText:
                'Current\n-- \nSignature\nOn Tuesday, Alice wrote:\n> Previous',
            bodyHtml: useHtml
                ? '<p>Current</p><div class="gmail_signature">Signature</div>'
                      '<div class="gmail_quote">Previous</div>'
                : null,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: MessageBody(email: email)),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Current', findRichText: true),
            findsWidgets,
          );
          expect(
            find.textContaining('Signature', findRichText: true),
            findsNothing,
          );
          expect(
            find.textContaining('Previous', findRichText: true),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Previous', findRichText: true),
            findsWidgets,
          );
          expect(
            find.textContaining('Signature', findRichText: true),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('toggle-signature-m2')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Signature', findRichText: true),
            findsWidgets,
          );
          await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Previous', findRichText: true),
            findsNothing,
          );
          expect(
            find.textContaining('Signature', findRichText: true),
            findsWidgets,
          );
          await tester.tap(find.byKey(const Key('toggle-signature-m2')));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Signature', findRichText: true),
            findsNothing,
          );
        },
      );
    }

    for (final useHtml in [false, true]) {
      testWidgets(
        'older ${useHtml ? 'HTML' : 'plain'} messages step inward and shrink without reply metadata',
        (tester) async {
          final history = [
            for (var index = 0; index < 12; index++)
              _message(
                'history-$index',
                'Alice',
                'Message $index',
                index + 1,
              ).copyWith(
                bodyHtml: useHtml
                    ? '<p style="font-size: 15px">Message $index</p>'
                    : null,
              ),
          ];
          final opened = _message('opened', 'Bob', 'Current message', 23);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: SizedBox(
                      width: 320,
                      child: MessageBody(
                        email: opened,
                        history: history.reversed.toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('toggle-quoted-opened')));
          await tester.pumpAndSettle();

          double renderedFontSize(String id) {
            double? size;
            void visitText(
              InlineSpan span,
              double inheritedSize,
              TextScaler scaler,
            ) {
              final fontSize = span.style?.fontSize ?? inheritedSize;
              if (span is TextSpan) {
                if (span.text?.contains('Message') == true ||
                    span.text?.contains('Current message') == true) {
                  size = scaler.scale(fontSize);
                }
                for (final child in span.children ?? const <InlineSpan>[]) {
                  visitText(child, fontSize, scaler);
                }
              }
            }

            void visit(RenderObject object) {
              if (size != null) return;
              if (object is RenderEditable) {
                visitText(object.text!, 15, object.textScaler);
              } else if (object is RenderParagraph) {
                visitText(object.text, 15, object.textScaler);
              } else {
                object.visitChildren(visit);
              }
            }

            visit(tester.renderObject(find.byKey(Key('message-body-$id'))));
            return size!;
          }

          var previousLeft = tester
              .getRect(find.byKey(const Key('message-body-opened')))
              .left;
          var previousTop = double.negativeInfinity;
          var previousFontSize = renderedFontSize('opened');
          for (final message in history.reversed) {
            final rect = tester.getRect(
              find.byKey(Key('message-history-${message.id}')),
            );
            final fontSize = renderedFontSize(message.id);
            expect(rect.left, greaterThan(previousLeft));
            if (previousTop.isFinite) {
              expect(rect.left - previousLeft, closeTo(1, 0.001));
            }
            expect(rect.top, greaterThan(previousTop));
            expect(rect.right, lessThanOrEqualTo(320));
            expect(rect.width, greaterThan(200));
            expect(fontSize, lessThan(previousFontSize));
            expect(fontSize, greaterThanOrEqualTo(24));
            previousLeft = rect.left;
            previousTop = rect.top;
            previousFontSize = fontSize;
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

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
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, 'm3');
      await tester.tap(find.byKey(const Key('toggle-quoted-m3')));
      await tester.pumpAndSettle();
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
      repo.history = [m4];
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
      await tester.ensureVisible(find.byKey(const Key('toggle-quoted-m4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-quoted-m4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-history-m3')), findsOneWidget);
    });

    testWidgets('only the opened message keeps inline compose actions', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester, 'm2');
      for (final action in ['reply', 'reply-all', 'forward']) {
        expect(find.byKey(Key('message-$action-m2')), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const Key('toggle-quoted-m2')));
      await tester.tap(find.byKey(const Key('toggle-quoted-m2')));
      await tester.pumpAndSettle();
      for (final action in ['reply', 'reply-all', 'forward']) {
        expect(find.byKey(Key('message-$action-m1')), findsNothing);
      }
      expect(find.byKey(const Key('message-overflow-m1')), findsNothing);
      expect(find.byKey(const Key('message-star-m1')), findsNothing);
    });

    for (final mode in ['reply', 'reply-all', 'forward']) {
      testWidgets('opened message menu $mode targets the selected message', (
        tester,
      ) async {
        repo.failPrefill = true;
        await open(tester, 'm2');
        await tester.scrollUntilVisible(
          find.byKey(const Key('message-overflow-m2')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('message-overflow-m2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('message-menu-$mode-m2')));
        await tester.pumpAndSettle();

        expect(repo.prefillSources, ['$mode:m2']);
        expect(find.byKey(Key('message-menu-$mode-m2')), findsNothing);
      });
    }

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

    testWidgets('a five-message chain lists every earlier message', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo.history = [
        _message('m1', 'Ayse', 'Birinci', 20),
        _message('m2', 'Mehmet', 'İkinci', 21),
        _message('m3', 'Ali', 'Üçüncü', 22),
        _message('m4', 'Derya', 'Dördüncü', 23),
        _message('m5', 'Can', 'Beşinci', 24),
      ];
      await open(tester, 'm5');

      expect(find.byKey(const Key('thread-message-count')), findsOneWidget);
      expect(find.text('5 ileti'), findsOneWidget);
      expect(find.byKey(const Key('message-history-m4')), findsNothing);
      await tester.tap(find.byKey(const Key('toggle-quoted-m5')));
      await tester.pumpAndSettle();
      for (final id in ['m4', 'm3', 'm2', 'm1']) {
        expect(find.byKey(Key('message-history-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single message shows no count or earlier heading', (
      tester,
    ) async {
      repo.history = [repo.newer];
      await open(tester, 'm2');

      expect(find.byKey(const Key('thread-message-count')), findsNothing);
      expect(find.text('Önceki iletiler'), findsNothing);
    });

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
