import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// One-click unsubscribe support for the RFC 2369 `List-Unsubscribe` header
/// (and its RFC 8058 `List-Unsubscribe-Post` one-click extension).
///
/// The header value is a comma-separated list of angle-bracketed URLs, e.g.
/// `<https://example.com/unsub?id=1>, <mailto:unsub@example.com>` — an
/// `https`/`http` URL is preferred over a `mailto:` one when both exist.
@immutable
class UnsubscribeInfo {
  const UnsubscribeInfo({this.webUrl, this.mailtoUrl, this.oneClick = false});

  /// `https`/`http` unsubscribe URL, when the header carries one.
  final Uri? webUrl;

  /// `mailto:` unsubscribe URL, when the header carries one.
  final Uri? mailtoUrl;

  /// True when RFC 8058 one-click is available: [webUrl] is present *and*
  /// `List-Unsubscribe-Post: List-Unsubscribe=One-Click` was sent alongside
  /// it. Only then can unsubscribing fire as a direct POST instead of
  /// opening a browser/mail app.
  final bool oneClick;

  /// Whether any actionable URL was found at all.
  bool get hasAction => webUrl != null || mailtoUrl != null;
}

final _angleBracketUrl = RegExp(r'<([^>]+)>');

/// Parses `headers['list-unsubscribe']` (and `list-unsubscribe-post`).
/// Returns null when the mail carries no `list-unsubscribe` header at all —
/// the single source of truth for whether the unsubscribe action should be
/// offered, regardless of whether the value could be parsed into a usable
/// URL.
UnsubscribeInfo? parseUnsubscribeHeaders(Map<String, String> headers) {
  final raw = headers['list-unsubscribe'];
  if (raw == null || raw.trim().isEmpty) return null;

  Uri? web;
  Uri? mailto;
  for (final match in _angleBracketUrl.allMatches(raw)) {
    final candidate = match.group(1)?.trim();
    if (candidate == null || candidate.isEmpty) continue;
    final uri = Uri.tryParse(candidate);
    if (uri == null) continue;
    if (web == null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      web = uri;
    } else if (mailto == null && uri.scheme == 'mailto') {
      mailto = uri;
    }
  }

  final post = headers['list-unsubscribe-post']?.trim().toLowerCase();
  final oneClick = web != null && post == 'list-unsubscribe=one-click';

  return UnsubscribeInfo(webUrl: web, mailtoUrl: mailto, oneClick: oneClick);
}

/// Fires the unsubscribe action described by [info]:
///
/// - RFC 8058 one-click ([UnsubscribeInfo.oneClick]): `POST`s directly to
///   [UnsubscribeInfo.webUrl] with `List-Unsubscribe=One-Click` and reports
///   whether the server accepted it (2xx).
/// - A plain web URL: handed to the OS via [launch] (the external browser)
///   — success here means "opened", the server-side effect is out of reach.
/// - A `mailto:` URL: also handed to [launch] (opens the user's mail app
///   pre-filled).
/// - Neither present: returns false without doing anything.
///
/// [client] and [launch] are injectable so this stays unit-testable without
/// a live network or platform channel.
Future<bool> performUnsubscribe(
  UnsubscribeInfo info, {
  http.Client? client,
  Future<bool> Function(Uri url)? launch,
}) async {
  final doLaunch =
      launch ?? (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  if (info.oneClick) {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.post(
        info.webUrl!,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'List-Unsubscribe=One-Click',
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  final url = info.webUrl ?? info.mailtoUrl;
  if (url == null) return false;
  return doLaunch(url);
}
