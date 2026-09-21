import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/config/app_config.dart';
import 'package:kaydetmail/models/email.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';
import 'package:kaydetmail/screens/attachment_preview_screen.dart';
import 'package:kaydetmail/utils/attachment_preview.dart';

Uint8List _docx(String documentXml) {
  final bytes = utf8.encode(documentXml);
  final archive = Archive()
    ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _BytesRepository extends MockMailRepository {
  _BytesRepository(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List> downloadAttachment(
    String mailId,
    Attachment attachment,
  ) async => bytes;
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

  group('AttachmentPreviewScreen', () {
    Future<void> open(
      WidgetTester tester,
      Attachment a,
      Uint8List bytes,
    ) async {
      AppConfig.resetForTest();
      AppConfig.mailRepositoryForTest = _BytesRepository(bytes);
      await tester.pumpWidget(
        MaterialApp(
          home: AttachmentPreviewScreen(mailId: 'm', attachment: a),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows plain text content', (tester) async {
      await open(
        tester,
        const Attachment(name: 'not.txt', sizeBytes: 5),
        Uint8List.fromList(utf8.encode('gizli not')),
      );
      expect(find.text('gizli not'), findsOneWidget);
    });

    testWidgets('shows docx text', (tester) async {
      await open(
        tester,
        const Attachment(name: 'r.docx', sizeBytes: 5),
        _docx('<w:p><w:r><w:t>Rapor özeti</w:t></w:r></w:p>'),
      );
      expect(find.text('Rapor özeti'), findsOneWidget);
    });

    testWidgets('unsupported type offers the share fallback', (tester) async {
      await open(
        tester,
        const Attachment(name: 'b.xlsx', sizeBytes: 5),
        Uint8List.fromList([1, 2, 3]),
      );
      expect(
        find.text('Bu dosya türü uygulama içinde açılamıyor.'),
        findsOneWidget,
      );
      expect(find.text('Başka uygulamada aç'), findsOneWidget);
    });

    testWidgets('empty download shows an error with retry', (tester) async {
      await open(
        tester,
        const Attachment(name: 'not.txt', sizeBytes: 5),
        Uint8List(0),
      );
      expect(find.text('Ek indirilemedi.'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
    });
  });
}
