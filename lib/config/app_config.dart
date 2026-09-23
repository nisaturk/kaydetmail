import 'package:flutter/foundation.dart';

import '../repositories/api_mail_repository.dart';
import '../repositories/mail_repository.dart';
import '../services/mail_cache.dart';
import '../services/session_store.dart';

/// Central place that decides where the app gets its data.
///
/// The rest of the app only ever talks to [MailRepository].
class AppConfig {
  const AppConfig._();

  /// Push (FCM) is on by default — Firebase is configured for Android (see
  /// `docs/push-notifications.md`) and the backend already sends pushes.
  /// Disable with `--dart-define=PUSH_ENABLED=false`. Platforms without
  /// Firebase messaging (web, desktop) skip it regardless, see
  /// `PushService.isSupportedPlatform`.
  static const bool pushEnabled = bool.fromEnvironment(
    'PUSH_ENABLED',
    defaultValue: true,
  );

  static MailRepository? _mailRepository;

  /// The single repository instance shared by the whole app.
  static MailRepository get mailRepository => _mailRepository ??=
      ApiMailRepository(openCache: MailCache.open);

  /// Lets widget tests start from a fresh repository instance.
  @visibleForTesting
  static void resetForTest() {
    _mailRepository = null;
    SessionStore.resetForTest();
  }

  /// Lets widget tests drive screens with a stubbed repository.
  @visibleForTesting
  static set mailRepositoryForTest(MailRepository repository) {
    _mailRepository = repository;
  }
}
