/// Minimal, dependency-free HTML → plain-text fallback for mail bodies.
///
/// The backend sends both `bodyText` and `body.html`. Plain text is always
/// preferred; this converter is only the fallback for HTML-only messages.
/// It never renders anything: unsafe blocks (`script`, `style`, `iframe`,
/// …) are dropped *with their content*, every other tag is stripped, and
/// nothing external is fetched — so remote images, CSS, fonts and tracking
/// pixels can never load through it. `cid:` references degrade to nothing;
/// inline-image rendering is a separate future task.
String htmlToPlainText(String html) {
  var text = html.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');
  // Drop non-content blocks together with everything inside them.
  for (final tag in [
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'noscript',
    'template',
    'head',
    'svg',
  ]) {
    text = text.replaceAll(
      RegExp('<$tag\\b.*?</$tag\\s*>', caseSensitive: false, dotAll: true),
      ' ',
    );
  }
  // Block-level elements become line breaks so paragraphs don't merge.
  text = text.replaceAll(
    RegExp(
      r'<\s*(br|p|div|li|tr|h[1-6]|blockquote|hr|section|article)[^>]*>',
      caseSensitive: false,
    ),
    '\n',
  );
  text = text.replaceAll(
    RegExp(
      r'</\s*(p|div|li|tr|h[1-6]|blockquote|section|article)[^>]*>',
      caseSensitive: false,
    ),
    '\n',
  );
  // Strip whatever tags remain (inline formatting, links keep their text).
  text = text.replaceAll(RegExp(r'<[^>]*>'), '');
  text = _decodeEntities(text);
  // Collapse runs of whitespace, keep single newlines between blocks.
  final lines = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t\r\f\v]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  return lines.join('\n');
}

String _decodeEntities(String text) {
  const named = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&#39;': "'",
    '&#x27;': "'",
    '&#x2F;': '/',
  };
  var out = text;
  named.forEach((entity, char) => out = out.replaceAll(entity, char));
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  return out;
}
