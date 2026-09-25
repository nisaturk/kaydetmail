import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show MissingPluginException;

import '../models/attachment_download_state.dart';
import '../services/api_exception.dart';

@immutable
class AttachmentDownloadKey {
  const AttachmentDownloadKey(this.accountId, this.mailId, this.attachmentId);

  final String accountId;
  final String mailId;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is AttachmentDownloadKey &&
      other.accountId == accountId &&
      other.mailId == mailId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(accountId, mailId, attachmentId);
}

typedef AttachmentStreamOpener = Future<HttpStreamResult> Function({
  int? rangeStart,
  Future<void>? abortTrigger,
});

class HttpStreamResult {
  const HttpStreamResult({
    required this.statusCode,
    required this.headers,
    required this.stream,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> stream;
}

class AttachmentDownloadManager {
  AttachmentDownloadManager._()
    : _directoryProvider = getApplicationCacheDirectory,
      maxCacheBytes = 500 * 1024 * 1024;

  static final AttachmentDownloadManager instance =
      AttachmentDownloadManager._();

  factory AttachmentDownloadManager.forTest({
    required Future<Directory> Function() directoryProvider,
    int maxCacheBytes = 500 * 1024 * 1024,
  }) => AttachmentDownloadManager._forTest(directoryProvider, maxCacheBytes);

  AttachmentDownloadManager._forTest(
    this._directoryProvider,
    this.maxCacheBytes,
  );

  final Future<Directory> Function() _directoryProvider;
  final int maxCacheBytes;
  final Map<AttachmentDownloadKey, ValueNotifier<AttachmentDownloadState>>
  _states = {};
  final Map<AttachmentDownloadKey, _Job> _jobs = {};
  Future<Directory>? _rootFuture;

  ValueNotifier<AttachmentDownloadState> stateFor(AttachmentDownloadKey key) =>
      _states.putIfAbsent(
        key,
        () => ValueNotifier<AttachmentDownloadState>(const AttachmentIdle()),
      );

  Future<File?> cachedFile(AttachmentDownloadKey key, String filename) async {
    final file = File(p.join(await _keyDirectory(key), _safe(filename)));
    if (!await file.exists()) return null;
    await file.setLastModified(DateTime.now());
    stateFor(key).value = AttachmentCompleted(file);
    return file;
  }

  Future<File> ensureDownloaded({
    required AttachmentDownloadKey key,
    required String filename,
    required int sizeBytes,
    required AttachmentStreamOpener open,
  }) async {
    final cached = await cachedFile(key, filename);
    if (cached != null) return cached;
    final existing = _jobs[key];
    if (existing != null) return existing.future;
    final job = _Job();
    _jobs[key] = job;
    final future = _run(key, filename, sizeBytes, open, job);
    job.future = future;
    try {
      return await future;
    } finally {
      if (identical(_jobs[key], job)) _jobs.remove(key);
    }
  }

  Future<void> cancel(AttachmentDownloadKey key) async {
    final job = _jobs[key];
    if (job == null) return;
    job.cancelled = true;
    if (!job.abort.isCompleted) job.abort.complete();
    try {
      await job.future;
    } catch (_) {}
  }

  Future<int> cacheSize() async {
    final root = await _root();
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    final root = await _root();
    if (!await root.exists()) return;
    final entities = await root
        .list(recursive: true, followLinks: false)
        .toList();
    final activeDirectories = await Future.wait(_jobs.keys.map(_keyDirectory));
    for (final entity in entities.whereType<File>()) {
      final belongsToActiveDownload = activeDirectories.any(
        (directory) => p.isWithin(directory, entity.path),
      );
      if (!belongsToActiveDownload) await entity.delete();
    }
    final directories = entities.whereType<Directory>().toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      if (activeDirectories.any(
        (active) =>
            active == directory.path || p.isWithin(directory.path, active),
      )) {
        continue;
      }
      try {
        await directory.delete();
      } on FileSystemException {
        continue;
      }
    }
    for (final entry in _states.entries) {
      if (!_jobs.containsKey(entry.key)) {
        entry.value.value = const AttachmentIdle();
      }
    }
  }

  Future<void> removeAccount(String accountId) async {
    final jobs = _jobs.entries
        .where((entry) => entry.key.accountId == accountId)
        .map((entry) => entry.key)
        .toList();
    for (final key in jobs) {
      await cancel(key);
    }
    try {
      final directory = Directory(p.join(await _rootPath(), _safe(accountId)));
      if (await directory.exists()) await directory.delete(recursive: true);
    } on MissingPluginException {
      return;
    }
    for (final entry in _states.entries) {
      if (entry.key.accountId == accountId) {
        entry.value.value = const AttachmentIdle();
      }
    }
  }

  Future<File> _run(
    AttachmentDownloadKey key,
    String filename,
    int sizeBytes,
    AttachmentStreamOpener open,
    _Job job,
  ) async {
    final directory = Directory(await _keyDirectory(key));
    await directory.create(recursive: true);
    final finalFile = File(p.join(directory.path, _safe(filename)));
    final partFile = File('${finalFile.path}.part');
    stateFor(key).value = const AttachmentIdle();
    job.partPath = partFile.path;
    try {
      var rangeStart = await partFile.exists() ? await partFile.length() : 0;
      for (var attempt = 0; attempt < 2; attempt++) {
        late HttpStreamResult result;
        try {
          result = await open(
            rangeStart: rangeStart == 0 ? null : rangeStart,
            abortTrigger: job.abort.future,
          );
        } on ApiException catch (error) {
          if (error.status != 416 || rangeStart == 0 || attempt != 0) rethrow;
          await partFile.writeAsBytes(const []);
          rangeStart = 0;
          continue;
        }
        final headers = {
          for (final e in result.headers.entries) e.key.toLowerCase(): e.value,
        };
        var append = false;
        if (rangeStart > 0 && result.statusCode == 206) {
          final match = RegExp(
            r'^bytes (\d+)-(\d+)/(\d+|\*)$',
            caseSensitive: false,
          ).firstMatch(headers['content-range'] ?? '');
          if (match == null || int.parse(match.group(1)!) != rangeStart) {
            await result.stream.listen((_) {}).cancel();
            await partFile.writeAsBytes(const []);
            rangeStart = 0;
            continue;
          }
          append = true;
        } else if (result.statusCode == 200) {
          rangeStart = 0;
          append = false;
        } else {
          throw ApiException.fromResponse(result.statusCode, '');
        }
        final contentLength = int.tryParse(headers['content-length'] ?? '');
        final contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(headers['content-range'] ?? '');
        final rangeTotal = result.statusCode == 206 && contentRange != null
            ? int.parse(contentRange.group(3)!)
            : null;
        final total =
            rangeTotal ??
            (result.statusCode == 206 && contentLength != null
                ? rangeStart + contentLength
                : contentLength);
        final estimate = total ?? (sizeBytes > 0 ? sizeBytes : null);
        var received = append ? rangeStart : 0;
        stateFor(key).value = AttachmentDownloading(
          receivedBytes: received,
          totalBytes: estimate,
        );
        final handle = await partFile.open(
          mode: append ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in result.stream) {
            if (job.cancelled) {
              throw const AttachmentDownloadException(
                'İndirme iptal edildi.',
                cancelled: true,
              );
            }
            await handle.writeFrom(chunk);
            received += chunk.length;
            stateFor(key).value = AttachmentDownloading(
              receivedBytes: received,
              totalBytes: estimate,
            );
          }
          await handle.flush();
        } finally {
          await handle.close();
        }
        final expectedBytes =
            contentLength ??
            (result.statusCode == 206 && contentRange != null
                ? int.parse(contentRange.group(2)!) -
                      int.parse(contentRange.group(1)!) +
                      1
                : null);
        final bodyBytes = received - (append ? rangeStart : 0);
        if (expectedBytes != null && bodyBytes != expectedBytes) {
          throw const AttachmentDownloadException(
            'Ek eksik indirildi. Tekrar deneyin.',
          );
        }
        if (total != null && received != total) {
          throw const AttachmentDownloadException(
            'Ek eksik indirildi. Tekrar deneyin.',
          );
        }
        if (await partFile.length() != received) {
          throw const AttachmentDownloadException(
            'Ek kaydedilemedi. Tekrar deneyin.',
          );
        }
        await partFile.rename(finalFile.path);
        await finalFile.setLastModified(DateTime.now());
        stateFor(key).value = AttachmentCompleted(finalFile);
        await _evict(keep: finalFile);
        return finalFile;
      }
      throw const AttachmentDownloadException(
        'Ek indirilemedi. Tekrar deneyin.',
      );
    } catch (error) {
      if (job.cancelled ||
          error is AttachmentDownloadException && error.cancelled) {
        stateFor(key).value = const AttachmentCancelled();
        throw const AttachmentDownloadException(
          'İndirme iptal edildi.',
          cancelled: true,
        );
      }
      final message = _message(error);
      stateFor(key).value = AttachmentFailed(
        message,
        retryable: _retryable(error),
      );
      rethrow;
    }
  }

  String _message(Object error) => switch (error) {
    AttachmentDownloadException e => e.message,
    ApiException e when e.status == 404 => 'Ek bulunamadı.',
    ApiException e => e.userMessage,
    _ => 'Ek indirilemedi. Tekrar deneyin.',
  };

  bool _retryable(Object error) => switch (error) {
    AttachmentDownloadException e => e.retryable,
    ApiException e => e.isTransient,
    _ => true,
  };

  Future<void> _evict({required File keep}) async {
    final root = await _root();
    final files = <File>[];
    var total = 0;
    if (await root.exists()) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File ||
            _jobs.values.any((job) => job.partPath == entity.path)) {
          continue;
        }
        total += await entity.length();
        if (entity.path != keep.path) files.add(entity);
      }
    }
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final file in files) {
      if (total <= maxCacheBytes) break;
      final length = await file.length();
      await file.delete();
      total -= length;
      for (final entry in _states.entries) {
        final state = entry.value.value;
        if (state is AttachmentCompleted && state.file.path == file.path) {
          entry.value.value = const AttachmentIdle();
        }
      }
    }
  }

  Future<String> _keyDirectory(AttachmentDownloadKey key) async => p.join(
    await _rootPath(),
    _safe(key.accountId),
    _safe(key.mailId),
    _safe(key.attachmentId),
  );

  Future<String> _rootPath() async => (await _root()).path;

  Future<Directory> _root() => _rootFuture ??= _directoryProvider()
      .then((directory) => Directory(p.join(directory.path, 'attachments')))
      .catchError((Object error) {
        _rootFuture = null;
        throw error;
      });

  String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe == '.' || safe == '..' || safe.isEmpty ? '_' : safe;
  }
}

class _Job {
  final Completer<void> abort = Completer<void>();
  bool cancelled = false;
  String? partPath;
  late Future<File> future;
}
