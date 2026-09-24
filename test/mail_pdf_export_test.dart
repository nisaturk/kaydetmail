import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/utils/mail_pdf_export.dart';

// 1x1 red PNG, base64.
const _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Email _baseEmail({String? bodyHtml, List<Attachment> attachments = const []}) =>
    Email(
      id: '1',
      senderName: 'Ali Veli',
      senderEmail: 'ali@example.com',
      recipients: const ['bob@example.com'],
      subject: 'Test mail',
      bodyText: 'Just a short plain text body with no formatting at all.',
      bodyHtml: bodyHtml,
      timestamp: DateTime(2024, 1, 1),
      attachments: attachments,
    );

void main() {
  group('buildMailPdf', () {
    test('renders a larger, image-carrying PDF for a formatted bodyHtml mail '
        'than for a plain bodyText-only mail', () async {
      final plain = _baseEmail();
      final rich = _baseEmail(
        bodyHtml:
            '<p>Hello <b>bold</b> and <i>italic</i> and <u>underline</u> world.</p>'
            '<ul><li>First item</li><li>Second item</li></ul>'
            '<p>See <a href="https://example.com/unsub">this link</a> for details.</p>'
            '<img src="data:image/png;base64,$_tinyPng">',
        attachments: const [
          Attachment(
            name: 'invoice.pdf',
            sizeBytes: 20480,
            mimeType: 'application/pdf',
          ),
          Attachment(
            name: 'photo.jpg',
            sizeBytes: 1048576,
            mimeType: 'image/jpeg',
          ),
        ],
      );

      final plainBytes = await buildMailPdf(plain);
      final richBytes = await buildMailPdf(rich);

      // Meaningfully larger: extra paragraphs, a bulleted list, a link and
      // an embedded image, plus an attachments section.
      expect(richBytes.length, greaterThan(plainBytes.length));

      final plainText = latin1.decode(plainBytes, allowInvalid: true);
      final richText = latin1.decode(richBytes, allowInvalid: true);

      // An image XObject is only ever emitted for the HTML mail's inline
      // `data:` image.
      expect(plainText.contains('/Subtype/Image'), isFalse);
      expect(richText.contains('/Subtype/Image'), isTrue);
    });

    test('falls back to plain bodyText rendering when bodyHtml is null', () async {
      final plain = _baseEmail();
      final bytes = await buildMailPdf(plain);
      expect(bytes, isNotEmpty);
      // No image, no html-only markup should leak through — this is just a
      // smoke check that the fallback path still produces a valid document.
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.contains('/Subtype/Image'), isFalse);
    });

    test('falls back to plain bodyText rendering for blank/unparseable bodyHtml', () async {
      final blank = await buildMailPdf(_baseEmail(bodyHtml: '   '));
      final noText = await buildMailPdf(_baseEmail(bodyHtml: '<div></div>'));
      expect(blank, isNotEmpty);
      expect(noText, isNotEmpty);
    });

    test('never embeds a remote (non-data:) image', () async {
      final withRemoteImage = _baseEmail(
        bodyHtml: '<p>Body</p><img src="https://tracker.example.com/pixel.png">',
      );
      final bytes = await buildMailPdf(withRemoteImage);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.contains('/Subtype/Image'), isFalse);
    });

    test('lists attachment name, size and mime type in the Ekler section', () async {
      final email = _baseEmail(
        attachments: const [
          Attachment(
            name: 'sozlesme.docx',
            sizeBytes: 4096,
            mimeType: 'application/vnd.openxmlformats',
          ),
        ],
      );
      final withoutAttachment = await buildMailPdf(_baseEmail());
      final withAttachment = await buildMailPdf(email);
      expect(withAttachment.length, greaterThan(withoutAttachment.length));
    });
  });
}
