/// Converts compose's lightweight markdown-lite markup — `**bold**`,
/// `*italic*`, `__underline__`, `- ` bullet lines and `[text](url)` links —
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
  final lines = _escapeHtml(source).split('\n');
  final buffer = StringBuffer();
  var inList = false;

  void closeList() {
    if (inList) {
      buffer.write('</ul>');
      inList = false;
    }
  }

  for (final line in lines) {
    final bulletMatch = _bulletPattern.firstMatch(line);
    if (bulletMatch != null) {
      if (!inList) {
        buffer.write('<ul>');
        inList = true;
      }
      buffer.write('<li>${_inline(bulletMatch.group(1) ?? '')}</li>');
      continue;
    }
    closeList();
    if (line.isEmpty) {
      buffer.write('<br>');
    } else {
      buffer.write('<p>${_inline(line)}</p>');
    }
  }
  closeList();
  return buffer.toString();
}

final RegExp _bulletPattern = RegExp(r'^-\s+(.*)$');
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
/// bold/italic/underline/bullet/link — used by compose to decide whether a
/// send/draft/schedule needs an HTML alternative at all, so plain
/// unformatted mail never carries a redundant one.
bool hasMarkdownLiteMarkup(String source) {
  if (source.isEmpty) return false;
  if (_boldPattern.hasMatch(source) ||
      _underlinePattern.hasMatch(source) ||
      _italicPattern.hasMatch(source) ||
      _linkPattern.hasMatch(source)) {
    return true;
  }
  return source.split('\n').any((line) => _bulletPattern.hasMatch(line));
}
