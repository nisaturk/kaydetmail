/// Converts compose's lightweight markdown-lite markup — `**bold**`,
/// `*italic*`, `__underline__`, `- ` bullet and `1. ` numbered lines (nested
/// by two-space indentation), `> ` quote lines and `[text](url)` links —
/// into a small, safe HTML fragment.
///
/// Deliberately regex-based instead of pulling in a markdown package: the
/// syntax compose's formatting toolbar actually produces is a fixed, tiny
/// subset, so a full parser would be unused weight (see
/// `_ComposeScreenState`'s formatting toolbar in `compose_screen.dart`).
/// Every line is HTML-escaped before any marker substitution runs, so the
/// input can never inject markup of its own; only `http(s)://`/`mailto:`
/// link targets are honored, so a stray `javascript:` URL in `[text](url)`
/// degrades to plain text instead of becoming an anchor.
///
/// Compose calls this (via [hasMarkdownLiteMarkup]) to build the `bodyHtml`
/// alternative sent alongside the plain `bodyText` whenever the user
/// actually used the formatting toolbar — see
/// `_ComposeScreenState._bodyHtmlFor` in `compose_screen.dart`.
String markdownLiteToHtml(String source) {
  if (source.isEmpty) return '';
  final buffer = StringBuffer();
  _writeBlocks(source.split('\n'), buffer);
  return buffer.toString();
}

class MarkdownLiteLine {
  MarkdownLiteLine._(
    this.quote,
    this.indent,
    this.marker,
    this.markerGap,
    this.content,
  );

  factory MarkdownLiteLine.parse(String line) {
    final match = _linePattern.firstMatch(line)!;
    return MarkdownLiteLine._(
      match.group(1)!,
      match.group(2)!,
      match.group(3),
      match.group(4) ?? '',
      match.group(5)!,
    );
  }

  final String quote;
  final String indent;
  final String? marker;
  final String markerGap;
  final String content;

  int get quoteDepth => '>'.allMatches(quote).length;
  int get indentLevel => indent.replaceAll('\t', '  ').length ~/ 2;
  bool get isListItem => marker != null;
  bool get isBullet => marker == '-';
  bool get isNumbered => marker != null && marker != '-';
  int get prefixLength =>
      quote.length + indent.length + (marker?.length ?? 0) + markerGap.length;

  MarkdownLiteLine copyWith({
    String? quote,
    String? indent,
    String? marker,
    bool clearMarker = false,
    String? markerGap,
    String? content,
  }) {
    final nextMarker = clearMarker ? null : (marker ?? this.marker);
    return MarkdownLiteLine._(
      quote ?? this.quote,
      indent ?? this.indent,
      nextMarker,
      nextMarker == null ? '' : (markerGap ?? this.markerGap),
      content ?? this.content,
    );
  }

  @override
  String toString() => '$quote$indent${marker ?? ''}$markerGap$content';
}

final RegExp _linePattern = RegExp(
  r'^((?:> ?)*)([ \t]*)(?:(-|\d{1,9}\.)([ \t]+))?(.*)$',
);
final RegExp _quoteLevelPattern = RegExp(r'^> ?');

void _writeBlocks(List<String> lines, StringBuffer buffer) {
  var index = 0;
  while (index < lines.length) {
    final line = lines[index];
    if (_quoteLevelPattern.hasMatch(line)) {
      final inner = <String>[];
      while (index < lines.length &&
          _quoteLevelPattern.hasMatch(lines[index])) {
        inner.add(lines[index].replaceFirst(_quoteLevelPattern, ''));
        index++;
      }
      buffer.write('<blockquote>');
      _writeBlocks(inner, buffer);
      buffer.write('</blockquote>');
      continue;
    }
    if (MarkdownLiteLine.parse(line).isListItem) {
      final items = <MarkdownLiteLine>[];
      while (index < lines.length) {
        final parsed = MarkdownLiteLine.parse(lines[index]);
        if (parsed.quote.isNotEmpty || !parsed.isListItem) break;
        items.add(parsed);
        index++;
      }
      _writeList(items, buffer);
      continue;
    }
    if (line.isEmpty) {
      buffer.write('<br>');
    } else {
      buffer.write('<p>${_inline(_escapeHtml(line))}</p>');
    }
    index++;
  }
}

void _writeList(List<MarkdownLiteLine> items, StringBuffer buffer) {
  final open = <String>[];
  for (final item in items) {
    final tag = item.isNumbered ? 'ol' : 'ul';
    final level = item.indentLevel.clamp(0, open.length);
    while (open.length > level + 1) {
      buffer.write('</li></${open.removeLast()}>');
    }
    if (open.length == level + 1) {
      if (open.last == tag) {
        buffer.write('</li>');
      } else {
        buffer.write('</li></${open.removeLast()}>');
      }
    }
    if (open.length == level) {
      final number = item.isNumbered
          ? int.parse(item.marker!.substring(0, item.marker!.length - 1))
          : 1;
      buffer.write(number == 1 ? '<$tag>' : '<$tag start="$number">');
      open.add(tag);
    }
    buffer.write('<li>${_inline(_escapeHtml(item.content))}');
  }
  while (open.isNotEmpty) {
    buffer.write('</li></${open.removeLast()}>');
  }
}

final List<(RegExp, int)> markdownLiteInlineMarkers = [
  (_linkPattern, 1),
  (_boldPattern, 2),
  (_underlinePattern, 2),
  (_italicPattern, 1),
];

final RegExp _boldPattern = RegExp(r'\*\*(.+?)\*\*');
final RegExp _underlinePattern = RegExp(r'__(.+?)__');
// Bold is substituted first, so by the time this runs no `**` pairs remain
// — a leftover single `*...*` is unambiguously italic without needing a
// lookaround assertion.
final RegExp _italicPattern = RegExp(r'\*(.+?)\*');
final RegExp _linkPattern = RegExp(r'\[([^\]]*)\]\(([^)\s]+)\)');

String _inline(String line) {
  var result = line.replaceAllMapped(_linkPattern, (match) {
    final text = match.group(1) ?? '';
    final url = match.group(2) ?? '';
    return _isSafeUrl(url) ? '<a href="$url">$text</a>' : text;
  });
  result = result.replaceAllMapped(
    _boldPattern,
    (match) => '<b>${match.group(1)}</b>',
  );
  result = result.replaceAllMapped(
    _underlinePattern,
    (match) => '<u>${match.group(1)}</u>',
  );
  result = result.replaceAllMapped(
    _italicPattern,
    (match) => '<i>${match.group(1)}</i>',
  );
  return result;
}

bool _isSafeUrl(String url) {
  final lower = url.trim().toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('mailto:');
}

String _escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// True when [source] contains any markup this module understands —
/// bold/italic/underline/bullet/numbered/quote/link — used by compose to
/// decide whether a send/draft/schedule needs an HTML alternative at all, so
/// plain unformatted mail never carries a redundant one.
bool hasMarkdownLiteMarkup(String source) {
  if (source.isEmpty) return false;
  if (_boldPattern.hasMatch(source) ||
      _underlinePattern.hasMatch(source) ||
      _italicPattern.hasMatch(source) ||
      _linkPattern.hasMatch(source)) {
    return true;
  }
  return source.split('\n').any((line) {
    final parsed = MarkdownLiteLine.parse(line);
    return parsed.isListItem || parsed.quote.isNotEmpty;
  });
}
