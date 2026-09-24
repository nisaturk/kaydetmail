import 'dart:async';

import 'home_widget_service.dart';

/// Turns the home-screen widget's compose-shortcut signal
/// (`HomeWidgetService.widgetClicked` / `HomeWidgetService.initiallyLaunchedUri`)
/// into a single [onComposeRequested] call, gated on the app's auth-gate
/// login state (`_AuthGateState` in app.dart).
///
/// A signal that arrives before this launch's login state is known — the
/// common cold-start case, where session restore is still in flight — is
/// held and replayed once [resolveAuth] reports the outcome: `true` (a
/// session restored, or the user just signed in) fires
/// [onComposeRequested] exactly once; `false` drops it, so a widget tap
/// that lands on a logged-out app just opens normally instead of pushing a
/// broken route on top of the login screen. A signal that arrives while
/// already logged in fires immediately.
class HomeWidgetComposeRouter {
  HomeWidgetComposeRouter({required this.onComposeRequested});

  final void Function() onComposeRequested;

  bool? _authenticated;
  bool _pending = false;
  StreamSubscription<Uri?>? _sub;

  /// Starts listening for warm-start widget taps and checks whether this
  /// launch was a cold start from the widget. Call once, typically from
  /// `initState`.
  void start() {
    _sub = HomeWidgetService.widgetClicked.listen(_handleUri);
    unawaited(HomeWidgetService.initiallyLaunchedUri().then(_handleUri));
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Feeds the auth gate's resolved login state for this launch. Safe to
  /// call more than once (e.g. logout then a fresh login) — only acts while
  /// a compose signal is pending.
  void resolveAuth(bool authenticated) {
    _authenticated = authenticated;
    if (!_pending) return;
    _pending = false;
    if (authenticated) onComposeRequested();
  }

  void _handleUri(Uri? uri) {
    if (!HomeWidgetService.isComposeUri(uri)) return;
    if (_authenticated == true) {
      onComposeRequested();
    } else if (_authenticated == null) {
      _pending = true;
    }
    // _authenticated == false: login state already resolved to logged-out
    // for this launch — drop it, matching the "fall back to just opening
    // the app normally" contract.
  }
}
