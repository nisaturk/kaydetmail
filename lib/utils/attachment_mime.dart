import 'package:http/http.dart' show MediaType;
import 'package:mime/mime.dart';

const String fallbackContentType = 'application/octet-stream';

MediaType attachmentMediaType(String fileName, String? declaredMimeType) {
  final declared = _parse(declaredMimeType);
  if (declared != null) return declared;
  final inferred = _parse(lookupMimeType(fileName));
  return inferred ?? MediaType.parse(fallbackContentType);
}

String attachmentContentType(String fileName, String? declaredMimeType) =>
    attachmentMediaType(fileName, declaredMimeType).mimeType;

MediaType? _parse(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  try {
    final type = MediaType.parse(trimmed);
    if (type.type.isEmpty || type.subtype.isEmpty) return null;
    return type;
  } on FormatException {
    return null;
  }
}
