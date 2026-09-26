import '../models/email.dart';

final _quoteHeader = RegExp(
  r'^(on .+ wrote:|.+ tarihinde .+ yazdı:?|-{2,}\s*original message\s*-{2,}|-{3}\s*iletilen mesaj\s*-{3})',
  caseSensitive: false,
);

({String visible, bool collapsed}) collapseQuotedText(String body) {
  final lines = body.split('\n');
  final cut = lines.indexWhere((line) {
    final trimmed = line.trim();
    return trimmed.startsWith('>') ||
        _quoteHeader.hasMatch(trimmed) ||
        line == '-- ' ||
        line == '--';
  });
  if (cut <= 0) return (visible: body, collapsed: false);
  final visible = lines.sublist(0, cut).join('\n').trimRight();
  if (visible.trim().isEmpty) return (visible: body, collapsed: false);
  return (visible: visible, collapsed: true);
}

const _quoteClasses = {
  'gmail_quote',
  'gmail_signature',
  'yahoo_quoted',
  'moz-cite-prefix',
  'moz-signature',
};

const _quoteIds = {'divRplyFwdMsg', 'appendonsend', 'Signature'};

bool isQuotedHtmlElement(
  String? localName,
  Iterable<String> classes,
  String id,
) =>
    localName == 'blockquote' ||
    classes.any(_quoteClasses.contains) ||
    _quoteIds.contains(id);

final _quotedHtmlMarker = RegExp(
  r'<blockquote|gmail_quote|gmail_signature|yahoo_quoted|moz-cite-prefix|moz-signature|divRplyFwdMsg|appendonsend|id="Signature"',
  caseSensitive: false,
);

bool htmlHasQuotedContent(String html) => _quotedHtmlMarker.hasMatch(html);

String threadParticipantSummary(List<Email> messages) {
  final names = <String>[];
  final seen = <String>{};
  for (final message in messages.reversed) {
    final key = message.senderEmail.toLowerCase();
    if (!seen.add(key)) continue;
    final name = message.senderName.trim();
    names.add(name.isEmpty ? message.senderEmail : name);
  }
  final people = names.length <= 3
      ? names.join(', ')
      : '${names.take(2).join(', ')} ve ${names.length - 2} kişi daha';
  return '$people · ${messages.length} ileti';
}
