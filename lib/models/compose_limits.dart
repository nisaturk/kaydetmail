import '../services/api_exception.dart';
import 'email.dart';

class ComposeLimits {
  const ComposeLimits({
    required this.maxAttachmentBytes,
    required this.maxMessageAttachmentBytes,
    required this.maxAttachmentCount,
  });

  factory ComposeLimits.fromJson(Map<String, dynamic> json) => ComposeLimits(
    maxAttachmentBytes: (json['maxAttachmentBytes'] as num).toInt(),
    maxMessageAttachmentBytes: (json['maxMessageAttachmentBytes'] as num)
        .toInt(),
    maxAttachmentCount: (json['maxAttachmentCount'] as num).toInt(),
  );

  final int maxAttachmentBytes;
  final int maxMessageAttachmentBytes;
  final int maxAttachmentCount;

  String get fileTooLargeMessage =>
      'Bu dosya izin verilen maksimum boyutu (${formatLimitSize(maxAttachmentBytes)}) aşıyor.';

  String get tooManyMessage =>
      'En fazla $maxAttachmentCount dosya ekleyebilirsiniz.';

  String get totalTooLargeMessage =>
      'Eklerin toplam boyutu izin verilen sınırı (${formatLimitSize(maxMessageAttachmentBytes)}) aşıyor.';

  String? violationFor(List<Attachment> attachments) {
    final oversized = attachments.where(
      (a) => a.sizeBytes > maxAttachmentBytes,
    );
    if (oversized.isNotEmpty) {
      return '${oversized.first.name}: $fileTooLargeMessage';
    }
    if (attachments.length > maxAttachmentCount) return tooManyMessage;
    if (totalBytes(attachments) > maxMessageAttachmentBytes) {
      return totalTooLargeMessage;
    }
    return null;
  }

  static int totalBytes(List<Attachment> attachments) =>
      attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
}

String formatLimitSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  final megabytes = bytes / (1024 * 1024);
  final rounded = megabytes.roundToDouble();
  final text = (megabytes - rounded).abs() < 0.05
      ? rounded.toStringAsFixed(0)
      : megabytes.toStringAsFixed(1).replaceAll('.', ',');
  return '$text MB';
}

class AttachmentLimitException extends ApiException {
  const AttachmentLimitException({
    required super.status,
    required super.code,
    super.title,
    super.correlationId,
    super.details,
    required this.message,
  });

  factory AttachmentLimitException.from(
    ApiException error,
    List<Attachment> attachments,
    ComposeLimits? limits,
  ) {
    final tooMany = error.code == 'too_many_attachments';
    final String message;
    if (limits == null) {
      message = tooMany
          ? 'Ek dosya sayısı sınırı aşıldı.'
          : 'Bir ek izin verilen maksimum boyutu aşıyor.';
    } else if (tooMany) {
      message = limits.tooManyMessage;
    } else {
      message = limits.violationFor(attachments) ?? limits.fileTooLargeMessage;
    }
    return AttachmentLimitException(
      status: error.status,
      code: error.code,
      title: error.title,
      correlationId: error.correlationId,
      details: error.details,
      message: message,
    );
  }

  static const codes = {'attachment_too_large', 'too_many_attachments'};

  final String message;

  @override
  String get userMessage => message;
}
