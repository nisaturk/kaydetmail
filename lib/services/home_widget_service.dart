import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';

/// Pushes inbox data to the native Android home-screen widget
/// (`MailWidgetProvider`, `android/app/src/main/kotlin/.../MailWidgetProvider.kt`).
///
/// Only Android ships a widget provider today, so calls elsewhere
/// (iOS/web/desktop, and the plugin-less test environment) are a no-op —
/// mirrors the swallow-everything pattern `PushService` uses for
/// platform-optional plugins.
class HomeWidgetService {
  HomeWidgetService._();

  /// Must match `MailWidgetProvider`'s class name so
  /// `HomeWidget.updateWidget(androidName: ...)` can resolve the receiver.
  static const _androidProviderName = 'MailWidgetProvider';

  /// Storage keys read by `MailWidgetProvider.onUpdate` — keep in sync with
  /// the Kotlin-side `companion object` constants.
  static const _unreadCountKey = 'kaydet_widget_unread_count';
  static const _mailLineKeys = [
    'kaydet_widget_mail_1',
    'kaydet_widget_mail_2',
    'kaydet_widget_mail_3',
  ];

  /// Maximum number of recent inbox lines shown on the widget.
  static const _maxLines = 3;

  /// Host of the widget compose button's launch URI (`kaydetmail://compose`)
  /// — must match `MailWidgetProvider.COMPOSE_URI` on the Kotlin side.
  static const composeUriHost = 'compose';

  static bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static HomeWidgetLaunchSource _launchSource =
      const _PluginHomeWidgetLaunchSource();

  /// Test seam for [initiallyLaunchedUri]/[widgetClicked]: swap in a fake
  /// [HomeWidgetLaunchSource] so app.dart's compose-shortcut routing
  /// (`HomeWidgetComposeRouter`) is testable without a real platform
  /// channel. Pass `null` to restore the real plugin-backed source.
  @visibleForTesting
  static void launchSourceForTest(HomeWidgetLaunchSource? source) {
    _launchSource = source ?? const _PluginHomeWidgetLaunchSource();
  }

  /// True when [uri] is the widget's compose-shortcut launch Uri.
  static bool isComposeUri(Uri? uri) => uri?.host == composeUriHost;

  /// Resolves the Uri the app was cold-started from via the widget, if any.
  /// Never throws — mirrors [refreshFromInbox]'s swallow-everything contract
  /// (unsupported platform, plugin not registered in tests, no widget
  /// launch this run all resolve to `null`).
  static Future<Uri?> initiallyLaunchedUri() async {
    if (!_isSupportedPlatform) return null;
    try {
      return await _launchSource.initiallyLaunchedUri();
    } catch (_) {
      return null;
    }
  }

  /// Emits the launch Uri whenever a warm app receives a widget tap.
  /// Unsupported platforms (and tests that never inject a fake source)
  /// simply never emit, exactly like [PushService.onMailTapped] would for a
  /// platform without push.
  static Stream<Uri?> get widgetClicked =>
      _isSupportedPlatform ? _launchSource.clicked : const Stream<Uri?>.empty();

  /// Reads the currently loaded Inbox off [repository], writes the widget's
  /// display data (unread count + up to [_maxLines] recent subject/sender
  /// lines) and triggers a repaint. Never throws — a missing platform
  /// implementation (iOS, web, desktop, tests) is swallowed just like every
  /// other optional-plugin call in this app.
  static Future<void> refreshFromInbox(MailRepository repository) async {
    if (!_isSupportedPlatform) return;
    try {
      final inbox = repository.getEmailsInFolder(MailFolder.inbox);
      final unreadCount = repository.unreadCount(MailFolder.inbox);

      await HomeWidget.saveWidgetData<int>(_unreadCountKey, unreadCount);
      for (var i = 0; i < _maxLines; i++) {
        final line = i < inbox.length ? _summarize(inbox[i]) : null;
        await HomeWidget.saveWidgetData<String>(_mailLineKeys[i], line);
      }
      await HomeWidget.updateWidget(androidName: _androidProviderName);
    } catch (_) {
      // Widget storage unavailable (unsupported platform, plugin not
      // registered in tests, no widget instance placed yet) — never crash
      // the caller (a foreground push handler) over a home-screen widget.
    }
  }

  /// One "Sender — Subject" line, truncated to keep the widget's single-line
  /// `TextView` from needing to reflow.
  static String _summarize(Email email) {
    final sender = email.senderName.isNotEmpty
        ? email.senderName
        : email.senderEmail;
    final subject = email.subject.trim().isEmpty
        ? '(Konu yok)'
        : email.subject.trim();
    final line = '$sender — $subject';
    return line.length > 60 ? '${line.substring(0, 60).trimRight()}…' : line;
  }
}

/// Abstraction over the two `home_widget` static launch APIs
/// ([HomeWidget.initiallyLaunchedFromHomeWidget], [HomeWidget.widgetClicked])
/// that [HomeWidgetService] reads to detect a widget tap. Exists purely so
/// tests can substitute a fake via [HomeWidgetService.launchSourceForTest]
/// instead of needing a real platform channel.
@visibleForTesting
abstract class HomeWidgetLaunchSource {
  Future<Uri?> initiallyLaunchedUri();
  Stream<Uri?> get clicked;
}

class _PluginHomeWidgetLaunchSource implements HomeWidgetLaunchSource {
  const _PluginHomeWidgetLaunchSource();

  @override
  Future<Uri?> initiallyLaunchedUri() =>
      HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri?> get clicked => HomeWidget.widgetClicked;
}
