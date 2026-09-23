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

  static bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    final sender = email.senderName.isNotEmpty ? email.senderName : email.senderEmail;
    final subject = email.subject.trim().isEmpty ? '(Konu yok)' : email.subject.trim();
    final line = '$sender — $subject';
    return line.length > 60 ? '${line.substring(0, 60).trimRight()}…' : line;
  }
}
