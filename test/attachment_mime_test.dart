import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/utils/attachment_mime.dart';

void main() {
  test('uses declared MIME, infers extensions, and falls back safely', () {
    expect(attachmentContentType('report.bin', 'text/custom'), 'text/custom');
    expect(attachmentContentType('photo.jpg', null), 'image/jpeg');
    expect(
      attachmentContentType('unknown.data', 'not-a-mime-type'),
      fallbackContentType,
    );
  });
}
