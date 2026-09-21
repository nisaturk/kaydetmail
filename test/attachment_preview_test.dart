import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/utils/attachment_preview.dart';

Uint8List _docx(String documentXml) {
  final bytes = utf8.encode(documentXml);
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('attachmentKindOf', () {
    AttachmentKind kind(String name, [String? mime]) =>
        attachmentKindOf(Attachment(name: name, sizeBytes: 1, mimeType: mime));

    test('detects by mime type or extension', () {
      expect(kind('a.pdf'), AttachmentKind.pdf);
      expect(kind('x', 'application/pdf'), AttachmentKind.pdf);
      expect(kind('photo.JPG'), AttachmentKind.image);
      expect(kind('x', 'image/png'), AttachmentKind.image);
      expect(kind('report.docx'), AttachmentKind.docx);
      expect(kind('notes.txt'), AttachmentKind.text);
      expect(kind('data.csv', 'text/csv'), AttachmentKind.text);
    });

    test('svg and unknown types are not previewable', () {
      expect(kind('logo.svg', 'image/svg+xml'), AttachmentKind.other);
      expect(kind('budget.xlsx'), AttachmentKind.other);
    });
  });

  group('docxToText', () {
    test('joins runs, splits paragraphs, decodes entities', () {
      final text = docxToText(
        _docx(
          '<w:document><w:body>'
          '<w:p><w:r><w:t>Merhaba</w:t></w:r><w:r><w:t xml:space="preserve"> dünya &amp; co</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr>'
          '<w:r><w:t>A</w:t><w:tab/><w:t>B</w:t></w:r></w:p>'
          '</w:body></w:document>',
        ),
      );
      expect(text, 'Merhaba dünya & co\nA\tB');
    });

    test('rejects non-docx bytes', () {
      expect(
        () => docxToText(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });

  group('stripQuotedReply', () {
    test('cuts quoted history', () {
      expect(
        stripQuotedReply('Tamamdır.\n\nOn Mon, Bob wrote:\n> eski\n> mesaj'),
        'Tamamdır.',
      );
      expect(stripQuotedReply('Evet\n> alıntı'), 'Evet');
    });

    test('keeps the full body when nothing else is left', () {
      expect(stripQuotedReply('> sadece alıntı'), '> sadece alıntı');
      expect(stripQuotedReply('düz metin'), 'düz metin');
    });
  });
}
