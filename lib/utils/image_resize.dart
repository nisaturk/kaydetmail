import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../models/email.dart';

enum ImageResizeChoice {
  original(null),
  large(2048),
  medium(1280),
  small(640);

  const ImageResizeChoice(this.maxEdge);
  final int? maxEdge;
}

bool isResizableImage(Attachment attachment) {
  final name = attachment.name.toLowerCase();
  final mime = attachment.mimeType?.toLowerCase();
  return mime == 'image/jpeg' ||
      mime == 'image/png' ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png');
}

Future<Attachment?> resizeAttachment(
  Attachment attachment,
  ImageResizeChoice choice,
) async {
  final edge = choice.maxEdge;
  final bytes = attachment.bytes;
  if (edge == null || bytes == null || !isResizableImage(attachment)) {
    return null;
  }
  final extension = attachment.name.toLowerCase();
  final isJpeg =
      extension.endsWith('.jpg') ||
      extension.endsWith('.jpeg') ||
      attachment.mimeType?.toLowerCase() == 'image/jpeg';
  final output = await Isolate.run(() => _resizeImage((bytes, edge, isJpeg)));
  if (output == null || output.length >= bytes.length) return null;
  return Attachment(
    id: attachment.id,
    name: attachment.name,
    sizeBytes: output.length,
    mimeType: isJpeg ? 'image/jpeg' : 'image/png',
    bytes: output,
  );
}

Uint8List? _resizeImage((Uint8List, int, bool) input) {
  final (bytes, edge, isJpeg) = input;
  try {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = image.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    if (longest <= edge) return null;
    final resized = image.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? edge : null,
      height: oriented.height > oriented.width ? edge : null,
      interpolation: image.Interpolation.average,
    );
    return Uint8List.fromList(
      isJpeg ? image.encodeJpg(resized, quality: 85) : image.encodePng(resized),
    );
  } catch (_) {
    return null;
  }
}
