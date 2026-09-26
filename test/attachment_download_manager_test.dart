import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/attachment_download_state.dart';
import 'package:kaydetmail/services/attachment_download_manager.dart';

void main() {
  late Directory directory;
  late AttachmentDownloadManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('attachment-cache-');
    manager = AttachmentDownloadManager.forTest(
      directoryProvider: () async => directory,
      maxCacheBytes: 8,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  const key = AttachmentDownloadKey('account', 'mail', 'attachment');

  test('streams progress and only exposes the completed file', () async {
    final progress = <AttachmentDownloading>[];
    final notifier = manager.stateFor(key);
    notifier.addListener(() {
      final state = notifier.value;
      if (state is AttachmentDownloading) progress.add(state);
    });
    final file = await manager.ensureDownloaded(
      key: key,
      filename: 'note.txt',
      sizeBytes: 4,
      open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
        statusCode: 200,
        headers: const {'content-length': '4'},
        stream: Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(manager.stateFor(key).value, isA<AttachmentCompleted>());
    expect(progress, isNotEmpty);
    expect(await manager.cacheSize(), 4);
  });

  test('content length mismatch never exposes a final file', () async {
    await expectLater(
      manager.ensureDownloaded(
        key: key,
        filename: 'bad.bin',
        sizeBytes: 4,
        open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
          statusCode: 200,
          headers: const {'content-length': '4'},
          stream: Stream.value([1, 2]),
        ),
      ),
      throwsA(isA<AttachmentDownloadException>()),
    );
    final folder = Directory(
      '${directory.path}/attachments/account/mail/attachment',
    );
    expect(await File('${folder.path}/bad.bin').exists(), isFalse);
    expect(await File('${folder.path}/bad.bin.part').exists(), isTrue);
    expect(manager.stateFor(key).value, isA<AttachmentFailed>());
  });

  test('retry resumes from the existing partial file on a valid 206', () async {
    final folder = Directory(
      '${directory.path}/attachments/account/mail/attachment',
    );
    await folder.create(recursive: true);
    await File('${folder.path}/resume.txt.part').writeAsBytes([1, 2]);
    int? requestedRange;
    final file = await manager.ensureDownloaded(
      key: key,
      filename: 'resume.txt',
      sizeBytes: 4,
      open: ({rangeStart, abortTrigger}) async {
        requestedRange = rangeStart;
        return HttpStreamResult(
          statusCode: 206,
          headers: const {
            'content-length': '2',
            'content-range': 'bytes 2-3/4',
          },
          stream: Stream.value([3, 4]),
        );
      },
    );
    expect(requestedRange, 2);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
  });

  test('a server ignoring Range restarts from zero', () async {
    final folder = Directory(
      '${directory.path}/attachments/account/mail/attachment',
    );
    await folder.create(recursive: true);
    await File('${folder.path}/restart.bin.part').writeAsBytes([9, 9]);
    final file = await manager.ensureDownloaded(
      key: key,
      filename: 'restart.bin',
      sizeBytes: 3,
      open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
        statusCode: 200,
        headers: const {'content-length': '3'},
        stream: Stream.value([1, 2, 3]),
      ),
    );
    expect(await file.readAsBytes(), [1, 2, 3]);
  });

  test(
    'same-key requests share one transfer and eviction caps cache',
    () async {
      var requests = 0;
      final gate = Completer<void>();
      Future<HttpStreamResult> open({
        int? rangeStart,
        Future<void>? abortTrigger,
      }) async {
        requests++;
        await gate.future;
        return HttpStreamResult(
          statusCode: 200,
          headers: const {'content-length': '6'},
          stream: Stream.value([1, 2, 3, 4, 5, 6]),
        );
      }

      final first = manager.ensureDownloaded(
        key: key,
        filename: 'first.bin',
        sizeBytes: 6,
        open: open,
      );
      final second = manager.ensureDownloaded(
        key: key,
        filename: 'first.bin',
        sizeBytes: 6,
        open: open,
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect(await first, await second);
      expect(requests, 1);

      final other = const AttachmentDownloadKey(
        'account',
        'mail2',
        'attachment',
      );
      await manager.ensureDownloaded(
        key: other,
        filename: 'other.bin',
        sizeBytes: 6,
        open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
          statusCode: 200,
          headers: const {'content-length': '6'},
          stream: Stream.value([7, 8, 9, 10, 11, 12]),
        ),
      );
      expect(await manager.cacheSize(), lessThanOrEqualTo(8));
    },
  );

  test('clear cache deletes completed files', () async {
    await manager.ensureDownloaded(
      key: key,
      filename: 'cached.txt',
      sizeBytes: 2,
      open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
        statusCode: 200,
        headers: const {'content-length': '2'},
        stream: Stream.value([1, 2]),
      ),
    );
    await manager.clearCache();
    expect(await manager.cacheSize(), 0);
    expect(manager.stateFor(key).value, isA<AttachmentIdle>());
  });

  test('account removal only deletes that account cache', () async {
    const other = AttachmentDownloadKey('other-account', 'mail', 'attachment');
    final first = await manager.ensureDownloaded(
      key: key,
      filename: 'first.bin',
      sizeBytes: 2,
      open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
        statusCode: 200,
        headers: const {'content-length': '2'},
        stream: Stream.value([1, 2]),
      ),
    );
    final second = await manager.ensureDownloaded(
      key: other,
      filename: 'second.bin',
      sizeBytes: 2,
      open: ({rangeStart, abortTrigger}) async => HttpStreamResult(
        statusCode: 200,
        headers: const {'content-length': '2'},
        stream: Stream.value([3, 4]),
      ),
    );
    await manager.removeAccount('account');
    expect(await first.exists(), isFalse);
    expect(await second.exists(), isTrue);
  });

  test('cancel aborts the transfer and preserves partial bytes for retry', () async {
    final started = Completer<void>();
    final source = StreamController<List<int>>();
    final download = manager.ensureDownloaded(
      key: key,
      filename: 'cancel.bin',
      sizeBytes: 4,
      open: ({rangeStart, abortTrigger}) async {
        started.complete();
        abortTrigger!.then((_) => source.addError(StateError('aborted')));
        return HttpStreamResult(
          statusCode: 200,
          headers: const {'content-length': '4'},
          stream: source.stream,
        );
      },
    );
    final expectation = expectLater(
      download,
      throwsA(isA<AttachmentDownloadException>()),
    );
    await started.future;
    source.add([1, 2]);
    await Future<void>.delayed(Duration.zero);
    await manager.cancel(key);
    await expectation;
    expect(manager.stateFor(key).value, isA<AttachmentCancelled>());
    expect(
      await File(
        '${directory.path}/attachments/account/mail/attachment/cancel.bin.part',
      ).exists(),
      isTrue,
    );
    await source.close();
  });
}
