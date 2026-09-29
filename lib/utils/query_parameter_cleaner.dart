/// Removes known marketing attribution parameters without changing the target.
Uri cleanTrackingQueryParameters(Uri uri) {
  if (!uri.hasQuery) return uri;

  final parts = uri.query.split('&');
  final kept = parts
      .where((part) => !_isTrackingParameter(_decodedName(part)))
      .toList();
  if (kept.length == parts.length) return uri;
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.hasAuthority ? uri.host : null,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    query: kept.isEmpty ? null : kept.join('&'),
    fragment: uri.hasFragment ? uri.fragment : null,
  );
}

String _decodedName(String part) {
  final separator = part.indexOf('=');
  final raw = separator < 0 ? part : part.substring(0, separator);
  try {
    return Uri.decodeQueryComponent(raw);
  } on ArgumentError {
    return raw;
  }
}

bool _isTrackingParameter(String name) {
  final normalized = name.toLowerCase();
  return normalized == 'fbclid' ||
      normalized == 'gclid' ||
      normalized == 'msclkid' ||
      normalized.startsWith('utm_') ||
      normalized.startsWith('mc_') ||
      normalized.startsWith('mtm_');
}
