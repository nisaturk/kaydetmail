import 'package:flutter/services.dart';

/// Native "privacy screen" switch.
///
/// On Android it sets `FLAG_SECURE` on the activity window: screenshots and
/// screen recordings are blocked and the recent-apps thumbnail is blanked.
/// iOS cannot block screenshots, so there the app covers its window while it
/// is inactive (app switcher preview). Platforms without the native side
/// (web, desktop, tests) ignore the call.
///
/// The Android/iOS code also reads [preferenceKey] straight from the platform
/// preference store at launch so the very first frame is already protected —
/// keep that key in sync with `AppPreferencesStore`.
class ScreenProtectionService {
  ScreenProtectionService._();

  static const MethodChannel _channel = MethodChannel(
    'kaydetmail/screen_protection',
  );

  /// `shared_preferences` prefixes keys with `flutter.` natively.
  static const String preferenceKey = 'kaydet.security.screenProtectionEnabled';

  /// Returns whether the native side accepted the request.
  static Future<bool> apply(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
