import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/state/outbox_store.dart';
import 'package:kaydetmail/state/pending_send_queue.dart';
import 'package:kaydetmail/services/api_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

Email _sent() => Email(
  id: 'sent-1',
  senderName: 'Me',
  senderEmail: 'me@example.com',
  recipients: const ['to@example.com'],
  subject: 'subject',
  bodyText: 'body',
  timestamp: DateTime(2026),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cancel before body completion leaves a retryable failed item',
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final store = OutboxStore.inMemory();
      final queue = PendingSendQueue.forTest(store);
      final uploadStarted = Completer<void>();
      var sendCalls = 0;
      String? key;
      await queue.enqueue(
        const PendingSend(
          id: 'send-1',
          to: ['to@example.com'],
          subject: 'S',
          body: 'B',
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
    String? identityId,
              String? idempotencyKey,
              void Function(int sent, int total)? onProgress,
              Future<void>? abortTrigger,
            }) async {
              sendCalls++;
              key = idempotencyKey;
              onProgress?.call(10, 100);
              uploadStarted.complete();
              await abortTrigger;
              throw const ApiException(status: 0, code: 'upload_cancelled');
            },
      );

      final flush = queue.flushPending();
      await uploadStarted.future;
      expect(queue.uploadProgress.value['send-1']?.sent, 10);
      expect(queue.cancelUpload('send-1'), isTrue);
      await flush;

      final item = store.load().single;
      expect(item.status, OutboxStatus.failed);
      expect(item.error, 'Gönderim iptal edildi.');
      expect(sendCalls, 1);
      expect(key, 'send-1');
    },
  );

  test('cancel is unavailable once the full body has been sent', () async {
    WidgetsFlutterBinding.ensureInitialized();
    final store = OutboxStore.inMemory();
    final queue = PendingSendQueue.forTest(store);
    final release = Completer<void>();
    final started = Completer<void>();
    await queue.enqueue(
      const PendingSend(
        id: 'send-2',
        to: ['to@example.com'],
        subject: 'S',
        body: 'B',
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
    String? identityId,
            String? idempotencyKey,
            void Function(int sent, int total)? onProgress,
            Future<void>? abortTrigger,
          }) async {
            onProgress?.call(100, 100);
            started.complete();
            await release.future;
            return _sent();
          },
    );

    final flush = queue.flushPending();
    await started.future;
    expect(queue.cancelUpload('send-2'), isFalse);
    release.complete();
    await flush;
    expect(store.load(), isEmpty);
  });
}
