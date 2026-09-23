import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/email.dart';
import 'date_format.dart';

/// Renders [email] (subject, from, to/cc, date, plain-text body) as a plain
/// PDF document — a utility export, not a branded one: system (base14)
/// fonts only, no bundled assets, one or more pages depending on body
/// length.
Future<Uint8List> buildMailPdf(Email email) async {
  final doc = pw.Document();

  const labelStyle = pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey700,
  );
  const valueStyle = pw.TextStyle(fontSize: 10, color: PdfColors.grey900);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Text(
          email.subject.trim().isEmpty ? '(Konu yok)' : email.subject,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 14),
        _field('Kimden', '${email.senderName} <${email.senderEmail}>',
            labelStyle, valueStyle),
        if (email.recipients.isNotEmpty)
          _field('Kime', email.recipients.join(', '), labelStyle, valueStyle),
        if (email.cc.isNotEmpty)
          _field('Cc', email.cc.join(', '), labelStyle, valueStyle),
        _field(
          'Tarih',
          formatMailDateFull(email.timestamp),
          labelStyle,
          valueStyle,
        ),
        pw.SizedBox(height: 16),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 16),
        pw.Text(
          email.bodyText,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          overflow: pw.TextOverflow.span,
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _field(
  String label,
  String value,
  pw.TextStyle labelStyle,
  pw.TextStyle valueStyle,
) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: '$label: ', style: labelStyle),
          pw.TextSpan(text: value, style: valueStyle),
        ],
      ),
    ),
  );
}

/// Opens the OS print dialog for [email]'s rendered PDF.
Future<void> printMailPdf(Email email) async {
  final bytes = await buildMailPdf(email);
  await Printing.layoutPdf(
    onLayout: (format) async => bytes,
    name: _fileBaseName(email),
  );
}

/// Opens the OS share sheet with [email]'s rendered PDF, so the user can
/// save it, send it on, or hand it to another app.
Future<void> shareMailPdf(Email email) async {
  final bytes = await buildMailPdf(email);
  await Printing.sharePdf(
    bytes: bytes,
    filename: '${_fileBaseName(email)}.pdf',
  );
}

/// A filesystem/share-sheet-safe file name derived from the subject.
String _fileBaseName(Email email) {
  final subject = email.subject.trim();
  final base = subject.isEmpty ? 'eposta' : subject;
  final sanitized = base
      .replaceAll(RegExp(r'[^\w\-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final trimmed = sanitized.length > 60
      ? sanitized.substring(0, 60)
      : sanitized;
  return trimmed.isEmpty ? 'eposta' : trimmed;
}
