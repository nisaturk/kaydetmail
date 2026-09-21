import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/email.dart';

/// How an attachment can be shown inside the app. Everything else falls back
/// to the share sheet.
enum AttachmentKind { image, pdf, docx, text, other }

const _docxMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

AttachmentKind attachmentKindOf(Attachment attachment) {
  final name = attachment.name.toLowerCase();
  final mime = (attachment.mimeType ?? '').toLowerCase();
  bool ext(List<String> exts) => exts.any(name.endsWith);

  if (mime == 'application/pdf' || name.endsWith('.pdf')) {
    return AttachmentKind.pdf;
  }
  if (mime == _docxMime || name.endsWith('.docx')) return AttachmentKind.docx;
  // SVG is an `image/*` mime but Image.memory can't decode it.
  if ((mime.startsWith('image/') && !mime.contains('svg')) ||
      ext(['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'])) {
    return AttachmentKind.image;
  }
  if (mime.startsWith('text/') ||
      ext(['.txt', '.csv', '.md', '.log', '.json', '.xml'])) {
    return AttachmentKind.text;
  }
  return AttachmentKind.other;
}

/// Plain text of a .docx (paragraphs, tabs, line breaks). Formatting, tables'
/// layout and images are dropped — this is a reading preview, not a renderer.
/// Throws [FormatException] when [bytes] isn't a valid docx.
String docxToText(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Not a valid docx file');
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) throw const FormatException('word/document.xml missing');
  final xml = utf8.decode(entry.readBytes()!, allowMalformed: true);

  final token = RegExp(
    r'<w:t(?:\s[^>]*)?>([^<]*)</w:t>|<w:tab\s*/>|<w:br(?:\s[^>]*)?/>|</w:p>',
  );
  final out = StringBuffer();
  for (final match in token.allMatches(xml)) {
    final text = match.group(1);
    if (text != null) {
      out.write(_unescapeXml(text));
    } else if (match.group(0)!.startsWith('<w:tab')) {
      out.write('\t');
    } else {
      out.write('\n');
    }
  }
  return out.toString().trim();
}

String _unescapeXml(String s) => s
    .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m[2]!, radix: m[1] == 'x' ? 16 : 10);
      return code == null ? m[0]! : String.fromCharCode(code);
    })
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// The part of a reply the sender actually wrote: cuts at the first quoted
/// line (`> …`) or "On … wrote:" style header so chat bubbles don't repeat the
/// whole history. Falls back to the full [body] when nothing is left.
String stripQuotedReply(String body) {
  final header = RegExp(
    r'^(on .+ wrote:|.+ tarihinde .+ yazdı:?|-{2,}\s*original message\s*-{2,})',
    caseSensitive: false,
  );
  final lines = body.split('\n');
  final cut = lines.indexWhere((l) {
    final t = l.trim();
    return t.startsWith('>') || header.hasMatch(t);
  });
  if (cut < 0) return body.trim();
  final kept = lines.sublist(0, cut).join('\n').trim();
  return kept.isEmpty ? body.trim() : kept;
}
