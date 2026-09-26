import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/utils/image_resize.dart';

void main() {
  test('resizes without upscaling and preserves original bytes', () async {
    final original = Uint8List.fromList(
      image.encodePng(
        image.Image(width: 2400, height: 1200)..setPixelRgb(0, 0, 255, 0, 0),
      ),
    );
    final attachment = Attachment(
      name: 'photo.png',
      sizeBytes: original.length,
      mimeType: 'image/png',
      bytes: original,
    );

    final resized = await resizeAttachment(
      attachment,
      ImageResizeChoice.medium,
    );
    expect(resized, isNotNull);
    final decoded = image.decodeImage(resized!.bytes!);
    expect(decoded!.width, 1280);
    expect(decoded.height, 640);
    expect(resized.sizeBytes, lessThan(attachment.sizeBytes));
    expect(attachment.bytes, orderedEquals(original));

    final smallBytes = Uint8List.fromList(
      image.encodePng(image.Image(width: 32, height: 16)),
    );
    final small = Attachment(
      name: 'small.png',
      sizeBytes: smallBytes.length,
      bytes: smallBytes,
    );
    expect(await resizeAttachment(small, ImageResizeChoice.large), isNull);
    expect(small.bytes, orderedEquals(smallBytes));
  });
}
