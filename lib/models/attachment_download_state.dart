import 'dart:io';

sealed class AttachmentDownloadState {
  const AttachmentDownloadState();
}

final class AttachmentIdle extends AttachmentDownloadState {
  const AttachmentIdle();
}

final class AttachmentDownloading extends AttachmentDownloadState {
  const AttachmentDownloading({required this.receivedBytes, this.totalBytes});

  final int receivedBytes;
  final int? totalBytes;

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0, 1).toDouble();
}

final class AttachmentCompleted extends AttachmentDownloadState {
  const AttachmentCompleted(this.file);

  final File file;
}

final class AttachmentFailed extends AttachmentDownloadState {
  const AttachmentFailed(this.message, {required this.retryable});

  final String message;
  final bool retryable;
}

final class AttachmentCancelled extends AttachmentDownloadState {
  const AttachmentCancelled();
}

class AttachmentDownloadException implements Exception {
  const AttachmentDownloadException(
    this.message, {
    this.retryable = true,
    this.cancelled = false,
  });

  final String message;
  final bool retryable;
  final bool cancelled;

  @override
  String toString() => message;
}
