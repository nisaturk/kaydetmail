import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _dummyEmail() => Email(
  id: 'sent-1',
  senderName: 'Me',
  senderEmail: 'me@example.com',
  recipients: const ['a@b.com'],
  subject: 'S',
  bodyText: 'B',
  timestamp: DateTime(2024, 1, 1),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => PendingSendQueue.instance.cancelAll());

  testWidgets('enqueue fires the real send only after the undo window elapses', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    var sendCalls = 0;
    List<String>? sentTo;

    PendingSendQueue.instance.enqueue(
      const PendingSend(id: 't1', to: ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail:
          ({
            required List<String> to,
            List<String> cc = const [],
            List<String> bcc = const [],
            required String subject,
            required String body,
            String? bodyHtml,
            List<Attachment> attachments = const [],
            String? from,
            String? fromAccountId,
            String? threadId,
            String? inReplyToId,
          }) async {
            sendCalls++;
            sentTo = to;
            return _dummyEmail();
          },
    );

    expect(PendingSendQueue.instance.isPending('t1'), isTrue);
    await tester.pump(const Duration(seconds: 7));
    expect(sendCalls, 0, reason: 'must not send before the undo window elapses');

    await tester.pump(const Duration(seconds: 2));
    expect(sendCalls, 1);
    expect(sentTo, ['a@b.com']);
    expect(PendingSendQueue.instance.isPending('t1'), isFalse);
  });

  testWidgets('cancel prevents the deferred send from ever firing', (tester) async {
    await tester.pumpWidget(const SizedBox());
    var sendCalls = 0;
    final id = PendingSendQueue.instance.nextId();

    PendingSendQueue.instance.enqueue(
      PendingSend(id: id, to: const ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail:
          ({
            required List<String> to,
            List<String> cc = const [],
            List<String> bcc = const [],
            required String subject,
            required String body,
            String? bodyHtml,
            List<Attachment> attachments = const [],
            String? from,
            String? fromAccountId,
            String? threadId,
            String? inReplyToId,
          }) async {
            sendCalls++;
            return _dummyEmail();
          },
    );

    expect(PendingSendQueue.instance.cancel(id), isTrue);
    expect(
      PendingSendQueue.instance.cancel(id),
      isFalse,
      reason: 'already cancelled — cancelling twice reports false',
    );

    await tester.pump(PendingSendQueue.undoWindow + const Duration(seconds: 1));
    expect(sendCalls, 0);
  });

  testWidgets('the originating draft is deleted only once the deferred send succeeds', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final deletedDrafts = <String>[];

    PendingSendQueue.instance.enqueue(
      const PendingSend(
        id: 't3',
        to: ['a@b.com'],
        subject: 'S',
        body: 'B',
        draftId: 'd1',
      ),
      sendEmail:
          ({
            required List<String> to,
            List<String> cc = const [],
            List<String> bcc = const [],
            required String subject,
            required String body,
            String? bodyHtml,
            List<Attachment> attachments = const [],
            String? from,
            String? fromAccountId,
            String? threadId,
            String? inReplyToId,
          }) async => _dummyEmail(),
      deleteDraft: (draftId) async => deletedDrafts.add(draftId),
    );

    expect(deletedDrafts, isEmpty);
    await tester.pump(PendingSendQueue.undoWindow + const Duration(seconds: 1));
    expect(deletedDrafts, ['d1']);
  });

  testWidgets(
    'cancelling a send never touches the draft it was edited from',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final deletedDrafts = <String>[];
      final id = PendingSendQueue.instance.nextId();

      PendingSendQueue.instance.enqueue(
        PendingSend(
          id: id,
          to: const ['a@b.com'],
          subject: 'S',
          body: 'B',
          draftId: 'd1',
        ),
        sendEmail:
            ({
              required List<String> to,
              List<String> cc = const [],
              List<String> bcc = const [],
              required String subject,
              required String body,
              String? bodyHtml,
              List<Attachment> attachments = const [],
              String? from,
              String? fromAccountId,
              String? threadId,
              String? inReplyToId,
            }) async => _dummyEmail(),
        deleteDraft: (draftId) async => deletedDrafts.add(draftId),
      );

      PendingSendQueue.instance.cancel(id);
      await tester.pump(PendingSendQueue.undoWindow + const Duration(seconds: 1));
      expect(deletedDrafts, isEmpty);
    },
  );

  group('durability', () {
    testWidgets('a queued send is written to durable storage the moment it is enqueued', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());

      PendingSendQueue.instance.enqueue(
        const PendingSend(id: 'durable-1', to: ['a@b.com'], subject: 'S', body: 'B'),
        sendEmail:
            ({
              required List<String> to,
              List<String> cc = const [],
              List<String> bcc = const [],
              required String subject,
              required String body,
              String? bodyHtml,
              List<Attachment> attachments = const [],
              String? from,
              String? fromAccountId,
              String? threadId,
              String? inReplyToId,
            }) async => _dummyEmail(),
      );
      // Let the persistence write-behind (fire-and-forget inside enqueue)
      // actually land before reading it back.
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('pending_send_queue_v1');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(decoded.single['id'], 'durable-1');
      expect(decoded.single['subject'], 'S');

      PendingSendQueue.instance.cancel('durable-1');
    });

    testWidgets('cancelling or completing a send removes it from durable storage', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());

      PendingSendQueue.instance.enqueue(
        const PendingSend(id: 'durable-2', to: ['a@b.com'], subject: 'S', body: 'B'),
        sendEmail:
            ({
              required List<String> to,
              List<String> cc = const [],
              List<String> bcc = const [],
              required String subject,
              required String body,
              String? bodyHtml,
              List<Attachment> attachments = const [],
              String? from,
              String? fromAccountId,
              String? threadId,
              String? inReplyToId,
            }) async => _dummyEmail(),
      );
      await tester.pump();

      PendingSendQueue.instance.cancel('durable-2');
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_send_queue_v1'), isNull);
    });

    testWidgets(
      'a pending send left in storage by a killed run is recovered and sent on next startup',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        // Simulates a previous run that enqueued this send, wrote it to
        // disk, and was killed before its undo-window timer (or its own
        // recovery) ever fired — no corresponding in-memory timer exists in
        // this fresh process, only the durable record.
        const killed = PendingSend(
          id: 'killed-1',
          to: ['a@b.com'],
          subject: 'Kill sırasında bekleyen',
          body: 'B',
          draftId: 'd-killed',
        );
        SharedPreferences.setMockInitialValues({
          'pending_send_queue_v1': jsonEncode([killed.toJson()]),
        });

        var sendCalls = 0;
        List<String>? sentSubject;
        final deletedDrafts = <String>[];

        await PendingSendQueue.instance.recoverPersisted(
          sendEmail:
              ({
                required List<String> to,
                List<String> cc = const [],
                List<String> bcc = const [],
                required String subject,
                required String body,
                String? bodyHtml,
                List<Attachment> attachments = const [],
                String? from,
                String? fromAccountId,
                String? threadId,
                String? inReplyToId,
              }) async {
                sendCalls++;
                sentSubject = [subject];
                return _dummyEmail();
              },
          deleteDraft: (draftId) async => deletedDrafts.add(draftId),
        );

        expect(sendCalls, 1, reason: 'the killed-run send must be recovered, not lost');
        expect(sentSubject, ['Kill sırasında bekleyen']);
        expect(deletedDrafts, ['d-killed']);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('pending_send_queue_v1'),
          isNull,
          reason: 'recovered sends must not be replayed on a later recovery too',
        );
      },
    );

    testWidgets(
      'a recovery failure is recorded as an outbox error instead of being swallowed',
      (tester) async {
        await tester.pumpWidget(const SizedBox());
        const killed = PendingSend(
          id: 'killed-2',
          to: ['a@b.com'],
          subject: 'Başarısız kurtarma',
          body: 'B',
        );
        SharedPreferences.setMockInitialValues({
          'pending_send_queue_v1': jsonEncode([killed.toJson()]),
        });

        await PendingSendQueue.instance.recoverPersisted(
          sendEmail:
              ({
                required List<String> to,
                List<String> cc = const [],
                List<String> bcc = const [],
                required String subject,
                required String body,
                String? bodyHtml,
                List<Attachment> attachments = const [],
                String? from,
                String? fromAccountId,
                String? threadId,
                String? inReplyToId,
              }) async => throw Exception('network down'),
          deleteDraft: (draftId) async {},
        );

        final failures = await PendingSendQueue.readOutboxErrors();
        expect(failures, hasLength(1));
        expect(failures.single.subject, 'Başarısız kurtarma');

        await PendingSendQueue.clearOutboxErrors();
        expect(await PendingSendQueue.readOutboxErrors(), isEmpty);
      },
    );

    testWidgets('flushPending sends every still-counting-down entry immediately', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      var sendCalls = 0;

      PendingSendQueue.instance.enqueue(
        const PendingSend(id: 'flush-1', to: ['a@b.com'], subject: 'S', body: 'B'),
        sendEmail:
            ({
              required List<String> to,
              List<String> cc = const [],
              List<String> bcc = const [],
              required String subject,
              required String body,
              String? bodyHtml,
              List<Attachment> attachments = const [],
              String? from,
              String? fromAccountId,
              String? threadId,
              String? inReplyToId,
            }) async {
              sendCalls++;
              return _dummyEmail();
            },
      );

      expect(PendingSendQueue.instance.isPending('flush-1'), isTrue);
      await PendingSendQueue.instance.flushPending();

      expect(sendCalls, 1, reason: 'backgrounding must not wait out the undo window');
      expect(PendingSendQueue.instance.isPending('flush-1'), isFalse);
    });
  });
}
