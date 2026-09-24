import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/email.dart';
import 'date_format.dart';

/// Renders [email] (subject, from, to/cc, date, body, attachment list) as a
/// PDF document — a utility export, not a branded one: system (base14)
/// fonts only, no bundled assets, one or more pages depending on content
/// length.
///
/// When [Email.bodyHtml] is present, its formatting (bold/italic/underline,
/// lists, links, inline `data:` images) is translated into `pdf` widget
/// primitives — remote images are never embedded, matching the on-screen
/// viewer's policy (`_MessageBody` in `mail_detail_screen.dart`). Mail
/// without an HTML body (plain-text mail, drafts, …) falls back to a plain
/// rendering of [Email.bodyText].
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
        ..._buildBodyWidgets(email),
        ..._buildAttachmentsSection(email, labelStyle),
      ],
    ),
  );

  return doc.save();
}

const _bodyStyle = pw.TextStyle(fontSize: 11, lineSpacing: 3);

/// Plain-text fallback: the raw body as a single flowing text block.
List<pw.Widget> _plainTextBody(Email email) => [
  pw.Text(email.bodyText, style: _bodyStyle, overflow: pw.TextOverflow.span),
];

/// The body section: [Email.bodyHtml] translated into `pdf` primitives when
/// present and non-empty, otherwise [Email.bodyText] as plain text.
List<pw.Widget> _buildBodyWidgets(Email email) {
  final html = email.bodyHtml;
  if (html == null || html.trim().isEmpty) return _plainTextBody(email);

  final root = html_parser.parse(html).body;
  if (root == null) return _plainTextBody(email);

  final widgets = _HtmlPdfRenderer(_bodyStyle).render(root);
  // The HTML had no text/image content translatable into widgets (e.g. only
  // unsupported tags) — fall back rather than emitting a blank body.
  return widgets.isEmpty ? _plainTextBody(email) : widgets;
}

/// A trailing "Ekler:" section listing every attachment's name, size and
/// mime type — attachment bytes are not embedded as extra pages, only the
/// ones already in memory would be available and that's out of scope here.
List<pw.Widget> _buildAttachmentsSection(Email email, pw.TextStyle labelStyle) {
  if (email.attachments.isEmpty) return const [];
  return [
    pw.SizedBox(height: 16),
    pw.Divider(color: PdfColors.grey400),
    pw.SizedBox(height: 12),
    pw.Text('Ekler:', style: labelStyle),
    pw.SizedBox(height: 6),
    for (final attachment in email.attachments)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(
          '-  ${attachment.name} - ${attachment.sizeLabel}'
          '${attachment.mimeType != null ? ' (${attachment.mimeType})' : ''}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey900),
        ),
      ),
  ];
}

/// Running inline formatting state threaded through the HTML walk — nesting
/// (`<b><i>…</i></b>`) combines flags rather than replacing them.
class _InlineStyle {
  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.link = false,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool link;

  _InlineStyle copyWith({bool? bold, bool? italic, bool? underline, bool? link}) =>
      _InlineStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        link: link ?? this.link,
      );

  pw.TextStyle apply(pw.TextStyle base) => base.copyWith(
    fontWeight: bold ? pw.FontWeight.bold : base.fontWeight,
    fontStyle: italic ? pw.FontStyle.italic : base.fontStyle,
    decoration: underline || link
        ? pw.TextDecoration.underline
        : base.decoration,
    color: link ? PdfColors.blue700 : base.color,
  );
}

/// Translates a small, known subset of HTML — the tags compose's
/// `markdownLiteToHtml` and the server's sanitized body actually produce
/// (`p`/`div`, `br`, `b`/`strong`, `i`/`em`, `u`, `a[href]`, `ul`/`ol`/`li`,
/// inline `data:` `img`) — into `pdf` widgets. Unknown tags (e.g. `span`,
/// `table`) are not laid out specially; their text content still surfaces
/// because their children are walked inline. This is deliberately not a
/// general HTML/CSS renderer — kaydetmail's HTML surface is a fixed, tiny
/// subset, so pulling in a heavy HTML-to-PDF dependency would be unused
/// weight.
class _HtmlPdfRenderer {
  _HtmlPdfRenderer(this._baseStyle);

  final pw.TextStyle _baseStyle;
  final List<pw.Widget> _blocks = [];
  List<pw.TextSpan> _spans = [];

  List<pw.Widget> render(dom.Element root) {
    _walkChildren(root, const _InlineStyle());
    _flushParagraph();
    return _blocks;
  }

  void _walkChildren(dom.Element element, _InlineStyle style) {
    for (final node in element.nodes) {
      _walk(node, style);
    }
  }

  void _walk(dom.Node node, _InlineStyle style) {
    if (node is dom.Text) {
      final collapsed = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (collapsed.trim().isEmpty) return;
      _spans.add(pw.TextSpan(text: collapsed, style: style.apply(_baseStyle)));
      return;
    }
    if (node is! dom.Element) return;

    switch (node.localName) {
      case 'br':
        _spans.add(pw.TextSpan(text: '\n', style: style.apply(_baseStyle)));
        return;
      case 'b':
      case 'strong':
        _walkChildren(node, style.copyWith(bold: true));
        return;
      case 'i':
      case 'em':
        _walkChildren(node, style.copyWith(italic: true));
        return;
      case 'u':
        _walkChildren(node, style.copyWith(underline: true));
        return;
      case 'a':
        final href = node.attributes['href']?.trim();
        _walkChildren(node, style.copyWith(link: true));
        if (href != null && href.isNotEmpty) {
          _spans.add(
            pw.TextSpan(
              text: ' ($href)',
              style: style
                  .copyWith(link: true)
                  .apply(_baseStyle)
                  .copyWith(fontSize: (_baseStyle.fontSize ?? 11) - 1),
            ),
          );
        }
        return;
      case 'p':
      case 'blockquote':
        _walkChildren(node, style);
        _flushParagraph();
        return;
      case 'ul':
      case 'ol':
        _flushParagraph();
        _renderList(node, ordered: node.localName == 'ol');
        return;
      case 'img':
        _renderImage(node);
        return;
      default:
        // 'div', 'span', 'table', 'tr', 'td', … : no dedicated layout, but
        // their text still needs to reach the page.
        _walkChildren(node, style);
        return;
    }
  }

  void _renderList(dom.Element listElement, {required bool ordered}) {
    var index = 1;
    for (final item in listElement.children.where((c) => c.localName == 'li')) {
      final saved = _spans;
      _spans = [];
      _walkChildren(item, const _InlineStyle());
      final itemSpans = _spans;
      _spans = saved;
      if (itemSpans.isEmpty) continue;
      final bullet = ordered ? '${index++}.' : '-';
      _blocks.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 14, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 18,
                child: pw.Text(bullet, style: _baseStyle),
              ),
              pw.Expanded(
                child: pw.RichText(text: pw.TextSpan(children: itemSpans)),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _renderImage(dom.Element img) {
    final src = img.attributes['src'] ?? '';
    // Remote images are never embedded — same policy as the on-screen
    // viewer, which only renders inline `data:` images too.
    if (!src.startsWith('data:')) return;
    final bytes = _decodeDataUrl(src);
    if (bytes == null) return;
    pw.MemoryImage image;
    try {
      image = pw.MemoryImage(bytes);
    } catch (_) {
      return; // unsupported image codec — skip rather than fail the PDF
    }
    _flushParagraph();
    _blocks.add(
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Image(image, fit: pw.BoxFit.contain, height: 160),
      ),
    );
  }

  void _flushParagraph() {
    if (_spans.isEmpty) return;
    _blocks.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.RichText(text: pw.TextSpan(children: _spans)),
      ),
    );
    _spans = [];
  }
}

final _dataUrlPattern = RegExp(r'^data:[^;,]*(;charset=[^;,]+)?(;base64)?,(.*)$');

Uint8List? _decodeDataUrl(String src) {
  final match = _dataUrlPattern.firstMatch(src);
  if (match == null) return null;
  final isBase64 = match.group(2) != null;
  final data = match.group(3) ?? '';
  try {
    if (isBase64) {
      return base64Decode(data.replaceAll(RegExp(r'\s'), ''));
    }
    return Uint8List.fromList(Uri.decodeComponent(data).codeUnits);
  } catch (_) {
    return null;
  }
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
