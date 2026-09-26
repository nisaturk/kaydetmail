import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/repositories/mail_repository.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:kaydetmail/state/app_settings_controller.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _sent() => Email(
  id: 'sent-1',
  senderName: 'Me',
  senderEmail: 'me@example.com',
  recipients: const ['a@b.com'],
  subject: 'S',
  bodyText: 'B',
  timestamp: DateTime(2024, 1, 1),
);

SendEmail _send(Future<Email> Function(String? key) action) =>
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
    String? identityId,
      String? idempotencyKey,
      void Function(int sent, int total)? onProgress,
      Future<void>? abortTrigger,
    }) => action(idempotencyKey);

/// Only overrides [sendEmail]/[deleteDraft] — the only two
/// [PendingSendQueue._retryWaitingForNetwork]/`retry()` call on
/// `AppConfig.mailRepository`.
class _FakeMailRepository extends MailRepository {
  int sendCalls = 0;
  bool succeedNextSend = true;

  @override
  Future<Email> sendEmail({
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
    String? identityId,
    String? idempotencyKey,
    void Function(int sent, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    sendCalls++;
    if (!succeedNextSend) {
      throw const ApiException(status: 0, code: 'network_unavailable');
    }
    return _sent();
  }

  @override
  Future<void> deleteDraft(String draftId) async {}

  @override
  Never noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettingsController.resetForTest();
  });

  testWidgets('undo window follows the configured delay', (tester) async {
    await tester.pumpWidget(const SizedBox());
    AppSettingsController.instance.undoSendDelay = UndoSendDelay.seconds20;
    final queue = PendingSendQueue.forTest(OutboxStore.inMemory());
    var sent = 0;
    await queue.enqueue(
      const PendingSend(id: 'send-d', to: ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail: _send((_) async {
        sent++;
        return _sent();
      }),
    );
    await tester.pump(const Duration(seconds: 19));
    expect(sent, 0);
    expect(queue.cancel('send-d'), isTrue);
    await tester.pump(const Duration(seconds: 5));
    expect(sent, 0);
  });

  testWidgets('delay off dispatches without an undo window', (tester) async {
    await tester.pumpWidget(const SizedBox());
    AppSettingsController.instance.undoSendDelay = UndoSendDelay.off;
    final queue = PendingSendQueue.forTest(OutboxStore.inMemory());
    var sent = 0;
    await queue.enqueue(
      const PendingSend(id: 'send-o', to: ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail: _send((_) async {
        sent++;
        return _sent();
      }),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 10));
    expect(sent, 1);
    expect(queue.cancel('send-o'), isFalse);
  });

  testWidgets('undo only cancels a persisted send before dispatch', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final store = OutboxStore.inMemory();
    final queue = PendingSendQueue.forTest(store);
    var sent = 0;
    await queue.enqueue(
      const PendingSend(id: 'send-1', to: ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail: _send((_) async {
        sent++;
        return _sent();
      }),
    );
    expect(store.load().single.send.body, 'B');
    await tester.pump(PendingSendQueue.undoWindow - const Duration(seconds: 1));
    expect(sent, 0);
    expect(queue.cancel('send-1'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(sent, 0);
    expect(store.load(), isEmpty);
  });

  testWidgets(
    'confirmed delivery clears the record and deletes the source draft',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final store = OutboxStore.inMemory();
      final queue = PendingSendQueue.forTest(store);
      final drafts = <String>[];
      String? key;
      await queue.enqueue(
        const PendingSend(
          id: 'send-2',
          to: ['a@b.com'],
          subject: 'S',
          body: 'B',
          draftId: 'draft-1',
        ),
        sendEmail: _send((value) async {
          key = value;
          return _sent();
        }),
        deleteDraft: (id) async => drafts.add(id),
      );
      await tester.pump(PendingSendQueue.undoWindow);
      expect(key, 'send-2');
      expect(store.load(), isEmpty);
      expect(drafts, ['draft-1']);
    },
  );

  testWidgets(
    'definite failure preserves the complete message and attachment bytes',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final store = OutboxStore.inMemory();
      final queue = PendingSendQueue.forTest(store);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await queue.enqueue(
        PendingSend(
          id: 'send-3',
          to: const ['a@b.com'],
          cc: const ['cc@b.com'],
          subject: 'S',
          body: 'Important body',
          bodyHtml: '<p>Important body</p>',
          attachments: [
            Attachment(name: 'file.bin', sizeBytes: 4, bytes: bytes),
          ],
        ),
        sendEmail: _send(
          (_) async =>
              throw const ApiException(status: 400, code: 'invalid_recipient'),
        ),
      );
      await queue.flushPending();
      final item = store.load().single;
      expect(item.status, OutboxStatus.failed);
      expect(item.send.body, 'Important body');
      expect(item.send.cc, ['cc@b.com']);
      expect(item.send.bodyHtml, '<p>Important body</p>');
      expect(item.send.attachments.single.bytes, orderedEquals(bytes));
    },
  );

  testWidgets('confirmed pre-delivery failure remains safely retryable', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final store = OutboxStore.inMemory();
    final queue = PendingSendQueue.forTest(store);
    await queue.enqueue(
      const PendingSend(
        id: 'send-not-delivered',
        to: ['a@b.com'],
        subject: 'S',
        body: 'B',
      ),
      sendEmail: _send((_) async => throw const SendBeforeDeliveryException()),
    );
    await queue.flushPending();
    expect(store.load().single.status, OutboxStatus.failed);
    expect(store.load().single.send.body, 'B');
  });

  testWidgets('timeout or interrupted delivery is never retried on recovery', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final store = OutboxStore.inMemory();
    final queue = PendingSendQueue.forTest(store);
    var calls = 0;
    await queue.enqueue(
      const PendingSend(id: 'send-4', to: ['a@b.com'], subject: 'S', body: 'B'),
      sendEmail: _send((_) async {
        calls++;
        throw const ApiException(status: 408, code: 'request_timeout');
      }),
    );
    await queue.flushPending();
    expect(store.load().single.status, OutboxStatus.uncertain);
    final restarted = PendingSendQueue.forTest(store);
    await restarted.recoverPersisted(
      sendEmail: _send((_) async {
        calls++;
        return _sent();
      }),
    );
    expect(calls, 1);
    expect(store.load().single.status, OutboxStatus.uncertain);
    await expectLater(restarted.retry('send-4'), throwsStateError);
  });

  testWidgets('a killed in-flight send is marked uncertain, not replayed', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final store = OutboxStore.inMemory();
    store.save(
      OutboxItem(
        send: const PendingSend(
          id: 'send-5',
          to: ['a@b.com'],
          subject: 'S',
          body: 'B',
        ),
        status: OutboxStatus.sending,
        undoUntil: DateTime.now(),
      ),
    );
    var calls = 0;
    await PendingSendQueue.forTest(store).recoverPersisted(
      sendEmail: _send((_) async {
        calls++;
        return _sent();
      }),
    );
    expect(calls, 0);
    expect(store.load().single.status, OutboxStatus.uncertain);
  });

  testWidgets(
    'editing a failed send atomically replaces it with a new pending send',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final store = OutboxStore.inMemory();
      store.save(
        OutboxItem(
          send: const PendingSend(
            id: 'old',
            to: ['a@b.com'],
            subject: 'Old',
            body: 'B',
          ),
          status: OutboxStatus.failed,
          undoUntil: DateTime.now(),
        ),
      );
      final queue = PendingSendQueue.forTest(store);
      await queue.enqueue(
        const PendingSend(
          id: 'new',
          to: ['b@c.com'],
          subject: 'Edited',
          body: 'New',
        ),
        replacesId: 'old',
        sendEmail: _send((_) async => _sent()),
      );
      expect(store.load().single.send.subject, 'Edited');
      expect(store.contains('old'), isFalse);
      queue.cancelAll();
    },
  );

  testWidgets('legacy persisted send migrates before being dispatched', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final store = OutboxStore.inMemory();
    const legacy = PendingSend(
      id: 'old-id',
      to: ['a@b.com'],
      subject: 'Legacy',
      body: 'Saved body',
    );
    SharedPreferences.setMockInitialValues({
      'pending_send_queue_v1': jsonEncode([legacy.toJson()]),
    });
    final queue = PendingSendQueue.forTest(store);
    String? key;
    await queue.recoverPersisted(
      sendEmail: _send((value) async {
        key = value;
        return _sent();
      }),
    );
    expect(key, isNotNull);
    expect(key, isNot('old-id'));
    expect(store.load(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_send_queue_v1'), isNull);
  });

  testWidgets(
    'a definite network-unavailable failure is marked waitingForNetwork, '
    'not uncertain, and the message stays intact for auto-retry',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final store = OutboxStore.inMemory();
      final queue = PendingSendQueue.forTest(store);
      await queue.enqueue(
        const PendingSend(
          id: 'send-offline',
          to: ['a@b.com'],
          subject: 'S',
          body: 'B',
        ),
        sendEmail: _send(
          (_) async =>
              throw const ApiException(status: 0, code: 'network_unavailable'),
        ),
      );
      await queue.flushPending();
      expect(store.load().single.status, OutboxStatus.waitingForNetwork);
      expect(store.load().single.send.body, 'B');
      queue.cancelAll();
    },
  );

  testWidgets(
    'a waitingForNetwork send is eligible for manual retry, unlike failed '
    'being the only retryable status before',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      addTearDown(AppConfig.resetForTest);
      final fake = _FakeMailRepository();
      AppConfig.mailRepositoryForTest = fake;
      final store = OutboxStore.inMemory();
      final queue = PendingSendQueue.forTest(store);
      await queue.enqueue(
        const PendingSend(
          id: 'send-retry',
          to: ['a@b.com'],
          subject: 'S',
          body: 'B',
        ),
        sendEmail: _send(
          (_) async =>
              throw const ApiException(status: 0, code: 'network_unavailable'),
        ),
      );
      await queue.flushPending();
      expect(store.load().single.status, OutboxStatus.waitingForNetwork);

      await queue.retry('send-retry');
      expect(fake.sendCalls, 1);
      expect(store.load(), isEmpty);
      queue.cancelAll();
    },
  );

  testWidgets('a waitingForNetwork send is redispatched automatically once the '
      'network-retry timer fires, with no user action', (tester) async {
    await tester.pumpWidget(const SizedBox());
    addTearDown(AppConfig.resetForTest);
    final fake = _FakeMailRepository()..succeedNextSend = false;
    AppConfig.mailRepositoryForTest = fake;
    final store = OutboxStore.inMemory();
    final queue = PendingSendQueue.forTest(store);
    await queue.enqueue(
      const PendingSend(
        id: 'send-auto',
        to: ['a@b.com'],
        subject: 'S',
        body: 'B',
      ),
      sendEmail: _send(
        (_) async =>
            throw const ApiException(status: 0, code: 'network_unavailable'),
      ),
    );
    await queue.flushPending();
    expect(store.load().single.status, OutboxStatus.waitingForNetwork);

    // Network is back by the time the timer fires.
    fake.succeedNextSend = true;
    await tester.pump(const Duration(seconds: 16));
    expect(fake.sendCalls, 1);
    expect(store.load(), isEmpty);
    queue.cancelAll();
  });
}
