enum LinkVerdict { safe, suspicious, blocked }

enum LinkBlockReason { unsupportedScheme, invalidAddress }

enum LinkWarning {
  displayMismatch,
  punycodeHost,
  mixedScripts,
  confusableCharacters,
  embeddedCredentials,
}

class LinkAssessment {
  const LinkAssessment._({
    required this.verdict,
    this.uri,
    this.scheme = '',
    this.blockReason,
    this.warnings = const {},
    this.asciiHost,
    this.unicodeHost,
    this.displayedDomain,
  });

  final LinkVerdict verdict;
  final Uri? uri;
  final String scheme;
  final LinkBlockReason? blockReason;
  final Set<LinkWarning> warnings;
  final String? asciiHost;
  final String? unicodeHost;
  final String? displayedDomain;

  bool get isSafe => verdict == LinkVerdict.safe;
  bool get isSuspicious => verdict == LinkVerdict.suspicious;
  bool get isBlocked => verdict == LinkVerdict.blocked;
}

const _allowedSchemes = {'http', 'https', 'mailto', 'tel'};

LinkAssessment assessMailLink(String href, {String displayText = ''}) {
  final trimmed = href.trim();
  final uri = trimmed.isEmpty ? null : Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return const LinkAssessment._(
      verdict: LinkVerdict.blocked,
      blockReason: LinkBlockReason.invalidAddress,
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if (!_allowedSchemes.contains(scheme)) {
    return LinkAssessment._(
      verdict: LinkVerdict.blocked,
      scheme: scheme,
      blockReason: LinkBlockReason.unsupportedScheme,
    );
  }
  if (scheme == 'tel') {
    return LinkAssessment._(
      verdict: LinkVerdict.safe,
      uri: uri,
      scheme: scheme,
    );
  }
  if (scheme == 'mailto') return _assessMailto(uri, displayText);
  return _assessWeb(uri, scheme, displayText);
}

LinkAssessment _assessWeb(Uri uri, String scheme, String displayText) {
  final host = uri.host.isEmpty
      ? null
      : _HostForms.parse(_decodeHost(uri.host));
  if (host == null) {
    return LinkAssessment._(
      verdict: LinkVerdict.blocked,
      scheme: scheme,
      blockReason: LinkBlockReason.invalidAddress,
    );
  }
  final warnings = <LinkWarning>{...host.warnings};
  if (uri.userInfo.isNotEmpty) warnings.add(LinkWarning.embeddedCredentials);
  final displayed = _displayedDomain(displayText);
  if (displayed != null && !_sameSite(displayed.ascii, host.ascii)) {
    warnings.add(LinkWarning.displayMismatch);
  }
  final target = host.isIpLiteral ? uri : uri.replace(host: host.ascii);
  return LinkAssessment._(
    verdict: warnings.isEmpty ? LinkVerdict.safe : LinkVerdict.suspicious,
    uri: target,
    scheme: scheme,
    warnings: warnings,
    asciiHost: host.ascii,
    unicodeHost: host.unicode,
    displayedDomain: displayed?.unicode,
  );
}

LinkAssessment _assessMailto(Uri uri, String displayText) {
  final String decoded;
  try {
    decoded = Uri.decodeComponent(uri.path);
  } on ArgumentError {
    return const LinkAssessment._(
      verdict: LinkVerdict.blocked,
      scheme: 'mailto',
      blockReason: LinkBlockReason.invalidAddress,
    );
  }
  final domains = <_HostForms>[];
  for (final address in decoded.split(',')) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) continue;
    final at = trimmed.lastIndexOf('@');
    final host = at < 0 ? null : _HostForms.parse(trimmed.substring(at + 1));
    if (host == null) {
      return const LinkAssessment._(
        verdict: LinkVerdict.blocked,
        scheme: 'mailto',
        blockReason: LinkBlockReason.invalidAddress,
      );
    }
    domains.add(host);
  }
  final warnings = <LinkWarning>{for (final d in domains) ...d.warnings};
  final displayed = _displayedDomain(displayText);
  if (displayed != null &&
      domains.any((d) => !_sameSite(displayed.ascii, d.ascii))) {
    warnings.add(LinkWarning.displayMismatch);
  }
  final shown = domains.firstOrNull;
  return LinkAssessment._(
    verdict: warnings.isEmpty ? LinkVerdict.safe : LinkVerdict.suspicious,
    uri: uri,
    scheme: 'mailto',
    warnings: warnings,
    asciiHost: shown?.ascii,
    unicodeHost: shown?.unicode,
    displayedDomain: displayed?.unicode,
  );
}

String? _decodeHost(String host) {
  try {
    return Uri.decodeComponent(host);
  } on ArgumentError {
    return null;
  }
}

class _HostForms {
  const _HostForms({
    required this.ascii,
    required this.unicode,
    required this.warnings,
    this.isIpLiteral = false,
  });

  final String ascii;
  final String unicode;
  final Set<LinkWarning> warnings;
  final bool isIpLiteral;

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final _asciiLabel = RegExp(r'^[a-z0-9_-]+$');

  static _HostForms? parse(String? raw) {
    if (raw == null) return null;
    var host = raw.trim().toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) return null;
    if (host.contains(':') || _ipv4.hasMatch(host)) {
      if (!RegExp(r'^[0-9a-f:.]+$').hasMatch(host)) return null;
      return _HostForms(
        ascii: host,
        unicode: host,
        warnings: const {},
        isIpLiteral: true,
      );
    }
    final warnings = <LinkWarning>{};
    final asciiLabels = <String>[];
    final unicodeLabels = <String>[];
    for (final label in host.split('.')) {
      if (label.isEmpty) return null;
      String asciiLabel;
      String unicodeLabel;
      if (label.runes.every((r) => r < 0x80)) {
        if (!_asciiLabel.hasMatch(label)) return null;
        asciiLabel = label;
        if (label.startsWith('xn--')) {
          warnings.add(LinkWarning.punycodeHost);
          final decoded = punycodeDecode(label.substring(4));
          unicodeLabel = decoded ?? label;
        } else {
          unicodeLabel = label;
        }
      } else {
        if (label.runes.any(_isForbiddenInHost)) return null;
        warnings.add(LinkWarning.punycodeHost);
        unicodeLabel = label;
        asciiLabel = 'xn--${punycodeEncode(label)}';
      }
      if (unicodeLabel != asciiLabel || label.startsWith('xn--')) {
        warnings.addAll(_labelHomographWarnings(unicodeLabel));
      }
      asciiLabels.add(asciiLabel);
      unicodeLabels.add(unicodeLabel);
    }
    return _HostForms(
      ascii: asciiLabels.join('.'),
      unicode: unicodeLabels.join('.'),
      warnings: warnings,
    );
  }
}

bool _isForbiddenInHost(int rune) =>
    rune <= 0x20 ||
    rune == 0x7F ||
    (rune >= 0x80 && rune <= 0x9F) ||
    ' /\\?#@%:[]<>"\'`^{}|'.runes.contains(rune);

enum _Script {
  latin,
  greek,
  cyrillic,
  armenian,
  hebrew,
  arabic,
  devanagari,
  thai,
  georgian,
  hangul,
  hiragana,
  katakana,
  han,
  other,
}

_Script? _scriptOf(int r) {
  if (r < 0x80) {
    final isLetter = (r >= 0x61 && r <= 0x7A) || (r >= 0x41 && r <= 0x5A);
    return isLetter ? _Script.latin : null;
  }
  if ((r >= 0x00C0 && r <= 0x024F && r != 0x00D7 && r != 0x00F7) ||
      (r >= 0x1E00 && r <= 0x1EFF) ||
      (r >= 0x2C60 && r <= 0x2C7F) ||
      (r >= 0xA720 && r <= 0xA7FF)) {
    return _Script.latin;
  }
  if ((r >= 0x0370 && r <= 0x03FF) || (r >= 0x1F00 && r <= 0x1FFF)) {
    return _Script.greek;
  }
  if ((r >= 0x0400 && r <= 0x052F) ||
      (r >= 0x1C80 && r <= 0x1C8F) ||
      (r >= 0x2DE0 && r <= 0x2DFF) ||
      (r >= 0xA640 && r <= 0xA69F)) {
    return _Script.cyrillic;
  }
  if (r >= 0x0530 && r <= 0x058F) return _Script.armenian;
  if (r >= 0x0590 && r <= 0x05FF) return _Script.hebrew;
  if ((r >= 0x0600 && r <= 0x06FF) || (r >= 0x0750 && r <= 0x077F)) {
    return _Script.arabic;
  }
  if (r >= 0x0900 && r <= 0x097F) return _Script.devanagari;
  if (r >= 0x0E00 && r <= 0x0E7F) return _Script.thai;
  if (r >= 0x10A0 && r <= 0x10FF) return _Script.georgian;
  if ((r >= 0xAC00 && r <= 0xD7AF) ||
      (r >= 0x1100 && r <= 0x11FF) ||
      (r >= 0x3130 && r <= 0x318F)) {
    return _Script.hangul;
  }
  if (r >= 0x3040 && r <= 0x309F) return _Script.hiragana;
  if (r >= 0x30A0 && r <= 0x30FF) return _Script.katakana;
  if ((r >= 0x4E00 && r <= 0x9FFF) || (r >= 0x3400 && r <= 0x4DBF)) {
    return _Script.han;
  }
  return _Script.other;
}

const _japaneseScripts = {
  _Script.latin,
  _Script.han,
  _Script.hiragana,
  _Script.katakana,
};
const _koreanScripts = {_Script.latin, _Script.han, _Script.hangul};

const _latinLookalikes = {
  0x0430,
  0x0435,
  0x043E,
  0x0440,
  0x0441,
  0x0443,
  0x0445,
  0x0455,
  0x0456,
  0x0458,
  0x04BB,
  0x04CF,
  0x0501,
  0x051B,
  0x051D,
  0x04AF,
  0x0432,
  0x043A,
  0x043C,
  0x043D,
  0x0442,
  0x0433,
  0x0410,
  0x0412,
  0x0415,
  0x041A,
  0x041C,
  0x041D,
  0x041E,
  0x0420,
  0x0421,
  0x0422,
  0x0425,
  0x03BF,
  0x03B1,
  0x03BD,
  0x03C1,
  0x03B9,
  0x03BA,
  0x03C5,
  0x03C4,
  0x03B5,
  0x0391,
  0x0392,
  0x0395,
  0x0396,
  0x0397,
  0x0399,
  0x039A,
  0x039C,
  0x039D,
  0x039F,
  0x03A1,
  0x03A4,
  0x03A5,
  0x03A7,
  0x0578,
  0x057D,
  0x0585,
  0x0566,
  0x0570,
};

bool _isInvisibleOrFullwidth(int r) =>
    r == 0x00AD ||
    r == 0x034F ||
    (r >= 0x200B && r <= 0x200F) ||
    (r >= 0x2060 && r <= 0x2064) ||
    r == 0xFEFF ||
    (r >= 0xFF01 && r <= 0xFF5E);

Set<LinkWarning> _labelHomographWarnings(String label) {
  final warnings = <LinkWarning>{};
  final scripts = <_Script>{};
  var letters = 0;
  var lookalikes = 0;
  for (final r in label.runes) {
    if (_isInvisibleOrFullwidth(r)) {
      warnings.add(LinkWarning.confusableCharacters);
    }
    final script = _scriptOf(r);
    if (script == null) continue;
    scripts.add(script);
    letters++;
    if (_latinLookalikes.contains(r)) lookalikes++;
  }
  if (scripts.length > 1 &&
      (scripts.contains(_Script.other) ||
          (!_japaneseScripts.containsAll(scripts) &&
              !_koreanScripts.containsAll(scripts)))) {
    warnings.add(LinkWarning.mixedScripts);
  }
  if (lookalikes > 0 && (scripts.length > 1 || lookalikes == letters)) {
    warnings.add(LinkWarning.confusableCharacters);
  }
  return warnings;
}

class _DisplayedDomain {
  const _DisplayedDomain(this.ascii, this.unicode);

  final String ascii;
  final String unicode;
}

final _schemePrefix = RegExp(r'^[a-z][a-z0-9+.-]*:(//)?', caseSensitive: false);
final _emailLike = RegExp(r'^[^@\s/]+@([^@\s/?#]+)$');
final _hostLike = RegExp(
  r'^(?:[^@/?#\s]*@)?([^/?#:\s]+)(?::\d+)?(?:[/?#].*)?$',
);
const _fileExtensions = {
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'txt',
  'rtf',
  'csv',
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'svg',
  'heic',
  'html',
  'htm',
  'php',
  'asp',
  'aspx',
  'jsp',
  'json',
  'xml',
  'mp3',
  'mp4',
  'wav',
  'ics',
  'vcf',
};

_DisplayedDomain? _displayedDomain(String text) {
  var t = text.trim();
  while (t.length >= 2 &&
      ((t.startsWith('<') && t.endsWith('>')) ||
          (t.startsWith('(') && t.endsWith(')')) ||
          (t.startsWith('[') && t.endsWith(']')) ||
          (t.startsWith('"') && t.endsWith('"')))) {
    t = t.substring(1, t.length - 1).trim();
  }
  while (t.isNotEmpty && '.,;:!?'.contains(t[t.length - 1])) {
    t = t.substring(0, t.length - 1);
  }
  if (t.isEmpty || t.contains(RegExp(r'\s'))) return null;
  final schemeMatch = _schemePrefix.firstMatch(t);
  final hasScheme = schemeMatch != null && schemeMatch.group(1) != null;
  final isMailto = t.toLowerCase().startsWith('mailto:');
  if (hasScheme || isMailto) t = t.substring(schemeMatch!.end);
  String? candidate;
  final email = _emailLike.firstMatch(t);
  if (email != null) {
    candidate = email.group(1);
  } else if (!isMailto) {
    candidate = _hostLike.firstMatch(t)?.group(1);
  }
  if (candidate == null) return null;
  final host = _HostForms.parse(_decodeHost(candidate));
  if (host == null) return null;
  if (host.isIpLiteral) return _DisplayedDomain(host.ascii, host.unicode);
  final labels = host.unicode.split('.');
  if (labels.length < 2) return null;
  final tld = labels.last;
  if (tld.length < 2 || !tld.runes.every((r) => _scriptOf(r) != null)) {
    return null;
  }
  final explicit = hasScheme || email != null || labels.first == 'www';
  if (!explicit && _fileExtensions.contains(tld)) return null;
  return _DisplayedDomain(host.ascii, host.unicode);
}

const _genericSecondLevel = {
  'ac',
  'av',
  'bbs',
  'bel',
  'biz',
  'co',
  'com',
  'dr',
  'ed',
  'edu',
  'eng',
  'gen',
  'go',
  'gob',
  'gouv',
  'gov',
  'gr',
  'info',
  'int',
  'k12',
  'kg',
  'law',
  'lg',
  'ltd',
  'med',
  'mil',
  'name',
  'ne',
  'net',
  'nhs',
  'nom',
  'or',
  'org',
  'plc',
  'pol',
  'police',
  'res',
  'sch',
  'tel',
  'tv',
  'web',
};

const _sharedHostingSuffixes = {
  '000webhostapp.com',
  'appspot.com',
  'azurewebsites.net',
  'blogspot.com',
  'cloudfront.net',
  'firebaseapp.com',
  'fly.dev',
  'framer.app',
  'github.io',
  'gitlab.io',
  'glitch.me',
  'godaddysites.com',
  'herokuapp.com',
  'myshopify.com',
  'netlify.app',
  'ngrok-free.app',
  'ngrok.io',
  'now.sh',
  'onrender.com',
  'pages.dev',
  'repl.co',
  'sharepoint.com',
  'square.site',
  'surge.sh',
  'vercel.app',
  'web.app',
  'webflow.io',
  'weebly.com',
  'wixsite.com',
  'wordpress.com',
  'workers.dev',
};

String registrableDomain(String asciiHost) {
  final labels = asciiHost.split('.');
  if (labels.length <= 2 || _HostForms._ipv4.hasMatch(asciiHost)) {
    return asciiHost;
  }
  final lastTwo = labels.sublist(labels.length - 2).join('.');
  final tld = labels.last;
  final suffixLength =
      _sharedHostingSuffixes.contains(lastTwo) ||
          (tld.length == 2 &&
              _genericSecondLevel.contains(labels[labels.length - 2]))
      ? 2
      : 1;
  if (labels.length <= suffixLength + 1) return asciiHost;
  return labels.sublist(labels.length - suffixLength - 1).join('.');
}

bool _sameSite(String a, String b) =>
    registrableDomain(a) == registrableDomain(b);

const _punyBase = 36;
const _punyTMin = 1;
const _punyTMax = 26;
const _punySkew = 38;
const _punyDamp = 700;
const _punyInitialBias = 72;
const _punyInitialN = 128;
const _punyLimit = 0x7FFFFFFF;

int _punyAdapt(int delta, int numPoints, bool firstTime) {
  var d = firstTime ? delta ~/ _punyDamp : delta ~/ 2;
  d += d ~/ numPoints;
  var k = 0;
  while (d > ((_punyBase - _punyTMin) * _punyTMax) ~/ 2) {
    d ~/= _punyBase - _punyTMin;
    k += _punyBase;
  }
  return k + ((_punyBase - _punyTMin + 1) * d) ~/ (d + _punySkew);
}

int _punyThreshold(int k, int bias) {
  if (k <= bias) return _punyTMin;
  if (k >= bias + _punyTMax) return _punyTMax;
  return k - bias;
}

int _punyDigitValue(int c) {
  if (c >= 0x61 && c <= 0x7A) return c - 0x61;
  if (c >= 0x41 && c <= 0x5A) return c - 0x41;
  if (c >= 0x30 && c <= 0x39) return c - 0x30 + 26;
  return -1;
}

int _punyDigitChar(int d) => d < 26 ? 0x61 + d : 0x30 + d - 26;

String? punycodeDecode(String input) {
  final output = <int>[];
  final delimiter = input.lastIndexOf('-');
  if (delimiter > 0) {
    for (final c in input.substring(0, delimiter).codeUnits) {
      if (c >= 0x80) return null;
      output.add(c);
    }
  }
  var n = _punyInitialN;
  var i = 0;
  var bias = _punyInitialBias;
  var pos = delimiter > 0 ? delimiter + 1 : 0;
  while (pos < input.length) {
    final oldI = i;
    var w = 1;
    for (var k = _punyBase; ; k += _punyBase) {
      if (pos >= input.length) return null;
      final digit = _punyDigitValue(input.codeUnitAt(pos++));
      if (digit < 0) return null;
      i += digit * w;
      if (i > _punyLimit) return null;
      final t = _punyThreshold(k, bias);
      if (digit < t) break;
      w *= _punyBase - t;
      if (w > _punyLimit) return null;
    }
    bias = _punyAdapt(i - oldI, output.length + 1, oldI == 0);
    n += i ~/ (output.length + 1);
    if (n > 0x10FFFF) return null;
    i %= output.length + 1;
    output.insert(i, n);
    i++;
  }
  if (output.isEmpty) return null;
  return String.fromCharCodes(output);
}

String punycodeEncode(String input) {
  final codePoints = input.runes.toList();
  final out = StringBuffer();
  for (final c in codePoints) {
    if (c < 0x80) out.writeCharCode(c);
  }
  final basicCount = out.length;
  var handled = basicCount;
  if (basicCount > 0) out.write('-');
  var n = _punyInitialN;
  var delta = 0;
  var bias = _punyInitialBias;
  while (handled < codePoints.length) {
    var m = 0x10FFFF + 1;
    for (final c in codePoints) {
      if (c >= n && c < m) m = c;
    }
    delta += (m - n) * (handled + 1);
    n = m;
    for (final c in codePoints) {
      if (c < n) delta++;
      if (c == n) {
        var q = delta;
        for (var k = _punyBase; ; k += _punyBase) {
          final t = _punyThreshold(k, bias);
          if (q < t) break;
          out.writeCharCode(_punyDigitChar(t + (q - t) % (_punyBase - t)));
          q = (q - t) ~/ (_punyBase - t);
        }
        out.writeCharCode(_punyDigitChar(q));
        bias = _punyAdapt(delta, handled + 1, handled == basicCount);
        delta = 0;
        handled++;
      }
    }
    delta++;
    n++;
  }
  return out.toString();
}
