import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

final _quoteHeader = RegExp(
  r'^(?:on .+ wrote:|.+ tarihinde .+ yazdı:?|-{2,}\s*original message\s*-{2,}|-{2,}\s*(?:iletilen mesaj|forwarded message)\s*-{2,})$',
  caseSensitive: false,
);
final _mailHeader = RegExp(
  r'^(?:from|sent|date|to|subject|kimden|gönderen|gönderildi|tarih|kime|konu):',
  caseSensitive: false,
);

enum _Section { body, quote, signature, quotedSignature }

/// Keeps content in source order; signatures and replies are independent.
/// Only explicit client markers / mail headers are interpreted as metadata.
class ConversationBody {
  ConversationBody.text(String text) : _html = null, _parts = _textParts(text);

  ConversationBody.html(String html)
    : _html = html_parser.parse(html),
      _parts = null {
    _markHtml(_html!.body!);
  }

  final dom.Document? _html;
  final List<({_Section section, String text})>? _parts;
  String? _unquotedText;
  String? _wholeText;
  final Map<int, Set<String>> _gramCache = {};

  bool get hasQuotes =>
      _hasSection(_Section.quote) || _hasSection(_Section.quotedSignature);
  bool get hasSignatures =>
      _hasSection(_Section.signature) || _hasSection(_Section.quotedSignature);

  bool _hasSection(_Section section) => _parts != null
      ? _parts.any((part) => part.section == section)
      : _html!.querySelector('[data-mail-${section.name}]') != null;

  /// [earlier] are the thread messages older than this one: a quote that only
  /// repeats them is dropped, since the conversation already shows them.
  String render({
    required bool showQuotes,
    required bool showSignatures,
    Iterable<String> representedBodies = const [],
    Iterable<ConversationBody> earlier = const [],
  }) {
    final history = earlier.toList();
    final represented = representedBodies
        .map(_normalizeQuote)
        .where((body) => body.isNotEmpty)
        .toSet();
    bool representedQuote(String text) =>
        represented.contains(_normalizeQuote(text)) ||
        _repeatsThread(text, history);
    if (_parts case final parts?) {
      return parts
          .where(
            (part) => switch (part.section) {
              _Section.body => true,
              _Section.signature => showSignatures,
              _Section.quote => showQuotes && !representedQuote(part.text),
              _Section.quotedSignature => showQuotes && showSignatures,
            },
          )
          .map((part) => part.text)
          .join('\n')
          .trimRight();
    }
    final document = _html!.clone(true);
    for (final element in document.querySelectorAll('[data-mail-quote]')) {
      if (!showQuotes ||
          (!_hasMedia(element) && representedQuote(_htmlText(element)))) {
        element.remove();
      }
    }
    if (!showSignatures) {
      for (final element in document.querySelectorAll(
        '[data-mail-signature]',
      )) {
        element.remove();
      }
    }
    return document.body!.innerHtml;
  }

  /// Whole message text, quotes and signatures included.
  String get _fullText => _wholeText ??= _parts != null
      ? _parts.map((part) => part.text).join('\n')
      : _htmlText(_html!.body!);

  Set<String> _gramsOfSize(int size) => _gramCache.putIfAbsent(
    size,
    () => _grams(_contentWords(_fullText), size),
  );

  /// Text used for conservative de-duplication. Images, attachments and
  /// unrecognized quote fragments are never discarded by text matching.
  String get unquotedText => _unquotedText ??= _parts != null
      ? render(showQuotes: false, showSignatures: false)
      : _htmlText(
          html_parser.parseFragment(
            render(showQuotes: false, showSignatures: false),
          ),
        );
}

List<({_Section section, String text})> _textParts(String text) {
  final lines = text.split(RegExp(r'\r?\n'));
  final parts = <({_Section section, String text})>[];
  var section = _Section.body;
  var headerQuote = false;
  var start = 0;
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    final unprefixed = trimmed.replaceFirst(RegExp(r'^(?:>\s*)+'), '');
    final quoteHeader =
        _quoteHeader.hasMatch(unprefixed) ||
        (_mailHeader.hasMatch(unprefixed) &&
            lines
                    .skip(i)
                    .take(6)
                    .where((l) => _mailHeader.hasMatch(l.trim()))
                    .length >=
                3);
    if (quoteHeader && !headerQuote) {
      final nextContent = lines
          .skip(i + 1)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !_mailHeader.hasMatch(line))
          .firstOrNull;
      headerQuote = nextContent?.startsWith('>') != true;
    }
    final quoted =
        quoteHeader ||
        headerQuote ||
        trimmed.startsWith('>') ||
        (trimmed.isEmpty &&
            (section == _Section.quote || section == _Section.quotedSignature));
    final delimiter =
        (lines[i] == '-- ' ||
            lines[i] == '--' ||
            (quoted && unprefixed == '--')) &&
        lines.skip(i + 1).any((line) => line.trim().isNotEmpty);
    final signed =
        !quoteHeader &&
        (delimiter ||
            (section == _Section.signature && !quoted) ||
            (section == _Section.quotedSignature && quoted));
    final next = quoted
        ? signed
              ? _Section.quotedSignature
              : _Section.quote
        : signed
        ? _Section.signature
        : _Section.body;
    if (next != section) {
      if (i > start) {
        parts.add((section: section, text: lines.sublist(start, i).join('\n')));
      }
      start = i;
      section = next;
    }
  }
  parts.add((section: section, text: lines.sublist(start).join('\n')));
  return parts;
}

const _quoteClasses = {'gmail_quote', 'yahoo_quoted'};
const _signatureClasses = {'gmail_signature', 'moz-signature'};

void _markHtml(dom.Element parent) {
  // Reply separators in Outlook precede the quoted body as *siblings*.
  // Mozilla's cite prefix belongs only to its following citation, not to a
  // later inline answer.
  var outlookTail = false;
  var mozillaCitation = false;
  for (final node in parent.nodes.toList()) {
    if (node is! dom.Element) continue;
    final classes = node.classes.map((c) => c.toLowerCase()).toSet();
    final id = node.id.toLowerCase();
    final signature =
        classes.any(_signatureClasses.contains) ||
        id == 'signature' ||
        id == 'appendonsend' ||
        node.attributes['data-smartmail'] == 'gmail_signature';
    final mozillaPrefix = classes.contains('moz-cite-prefix');
    if (id == 'divrplyfwdmsg') outlookTail = true;
    final quote =
        outlookTail ||
        mozillaPrefix ||
        classes.any(_quoteClasses.contains) ||
        (node.localName == 'blockquote' &&
            (node.attributes['type']?.toLowerCase() == 'cite' ||
                mozillaCitation));
    if (quote) node.attributes['data-mail-quote'] = '';
    if (signature) node.attributes['data-mail-signature'] = '';
    if (mozillaPrefix) {
      mozillaCitation = true;
    } else if (node.localName != 'br') {
      mozillaCitation = false;
    }
    _markHtml(node);
  }
  for (final marker in parent.children.toList()) {
    final outlook = marker.id.toLowerCase() == 'divrplyfwdmsg';
    final mozilla = marker.classes.contains('moz-cite-prefix');
    if (!outlook && !mozilla) continue;
    final start = parent.nodes.indexOf(marker);
    final tail = parent.nodes.skip(start).toList();
    final group = <dom.Node>[];
    for (final node in tail) {
      if (outlook) {
        group.add(node);
      } else if (node == marker ||
          node is dom.Text && node.data.trim().isEmpty ||
          node is dom.Element && node.localName == 'br') {
        group.add(node);
      } else {
        if (node is dom.Element && node.localName == 'blockquote') {
          group.add(node);
        }
        break;
      }
    }
    if (!outlook &&
        !group.any(
          (node) => node is dom.Element && node.localName == 'blockquote',
        )) {
      continue;
    }
    final wrapper = dom.Element.tag('div')..attributes['data-mail-quote'] = '';
    parent.nodes.insert(start, wrapper);
    for (final node in group) {
      node.remove();
      wrapper.nodes.add(node);
    }
    if (outlook) break;
  }
  _markLeadIn(parent);
}

String _htmlText(dom.Node node) {
  final buffer = StringBuffer();
  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.data);
      return;
    }
    for (final child in node.nodes) {
      visit(child);
    }
    if (node is dom.Element &&
        const {
          'div',
          'p',
          'br',
          'blockquote',
          'tr',
          'li',
        }.contains(node.localName)) {
      buffer.writeln();
    }
  }

  visit(node);
  return buffer.toString();
}

String _normalizeQuote(String text) {
  final lines = text
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\s*(?:>\s*)+'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  var start = 0;
  if (lines.isNotEmpty && _quoteHeader.hasMatch(lines.first)) start++;
  final headerCount = lines.skip(start).takeWhile(_mailHeader.hasMatch).length;
  if (headerCount >= 3) start += headerCount;
  return lines.skip(start).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _gramSize = 4;
const _coveredRatio = 0.9;
const _blockTags = {
  'div',
  'p',
  'blockquote',
  'table',
  'ul',
  'ol',
  'pre',
  'section',
  'article',
  'center',
};
final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final _quotePrefix = RegExp(r'^\s*(?:>\s*)+');

bool _hasMedia(dom.Element element) =>
    element.querySelector('img, video, audio, object') != null;

/// Lower-cased words of [text] minus quote/mail header lines, whose wording
/// differs from client to client.
List<String> _contentWords(String text) => [
  for (final raw in text.split('\n'))
    if (_isContentLine(raw.replaceFirst(_quotePrefix, '').trim()))
      for (final match in _wordPattern.allMatches(
        raw.replaceFirst(_quotePrefix, '').toLowerCase(),
      ))
        match.group(0)!,
];

bool _isContentLine(String line) =>
    line.isNotEmpty &&
    !_quoteHeader.hasMatch(line) &&
    !_mailHeader.hasMatch(line);

/// Overlapping [size]-word runs of [words]; independent of line wrapping and
/// of the attribution lines a client inserts between nested quotes.
Set<String> _grams(List<String> words, int size) => {
  for (var i = 0; i + size <= words.length; i++)
    words.sublist(i, i + size).join(' '),
};

/// True when nearly every word run of [text] occurs in an earlier thread
/// message, i.e. the text only repeats what the conversation already shows.
/// Short quotes are compared with proportionally short runs, so a one-word
/// reply history is recognised too; text without content words never is.
bool _repeatsThread(String text, List<ConversationBody> earlier) {
  final words = _contentWords(text);
  if (words.isEmpty || earlier.isEmpty) return false;
  final size = words.length < _gramSize ? words.length : _gramSize;
  final grams = _grams(words, size);
  final hits = grams
      .where(
        (gram) => earlier.any((body) => body._gramsOfSize(size).contains(gram)),
      )
      .length;
  return hits >= grams.length * _coveredRatio;
}

/// A sender's client can flatten its own quoted history into plain lines with
/// no `>`, `<blockquote type=cite>` or class to mark it. The attribution line
/// ("On … wrote:", "… tarihinde … yazdı:") still introduces it, exactly like
/// the plain-text parser treats it, so everything from that line on is marked
/// as quote. An attribution that already precedes a marked citation only
/// takes that citation with it, leaving an inline answer after it visible.
void _markLeadIn(dom.Element parent) {
  if (_insideMarked(parent, 'data-mail-quote')) return;
  final nodes = parent.nodes.toList();
  final line = StringBuffer();
  var lineStart = 0;
  for (var i = 0; i <= nodes.length; i++) {
    final node = i < nodes.length ? nodes[i] : null;
    final element = node is dom.Element ? node : null;
    final marked = element?.attributes.containsKey('data-mail-quote') ?? false;
    final block = element != null && _blockTags.contains(element.localName);
    final boundary =
        node == null || marked || block || element?.localName == 'br';
    if (!boundary) {
      line.write(node is dom.Text ? node.data : element!.text);
      continue;
    }
    var text = line.toString();
    var start = lineStart;
    var end = i;
    if (block && !marked && text.trim().isEmpty) {
      // A block that is itself the attribution line.
      text = element.text;
      start = i;
      end = i + 1;
    }
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_quoteHeader.hasMatch(normalized)) {
      _wrapLeadIn(parent, nodes, start, end);
      return;
    }
    line.clear();
    lineStart = i + 1;
  }
}

bool _insideMarked(dom.Element element, String attribute) {
  for (dom.Element? e = element; e != null; e = e.parent) {
    if (e.attributes.containsKey(attribute)) return true;
  }
  return false;
}

void _wrapLeadIn(
  dom.Element parent,
  List<dom.Node> nodes,
  int start,
  int leadInEnd,
) {
  var end = nodes.length;
  final next = nodes
      .skip(leadInEnd)
      .where(
        (node) =>
            !(node is dom.Text && node.data.trim().isEmpty) &&
            !(node is dom.Element && node.localName == 'br'),
      )
      .firstOrNull;
  if (next is dom.Element && next.attributes.containsKey('data-mail-quote')) {
    end = nodes.indexOf(next) + 1;
  }
  final wrapper = dom.Element.tag(parent.localName == 'p' ? 'span' : 'div')
    ..attributes['data-mail-quote'] = '';
  parent.nodes.insert(parent.nodes.indexOf(nodes[start]), wrapper);
  for (final node in nodes.sublist(start, end)) {
    node.remove();
    wrapper.nodes.add(node);
  }
}
