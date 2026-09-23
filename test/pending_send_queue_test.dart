import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';

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
}
