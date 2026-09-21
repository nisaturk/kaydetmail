import 'package:flutter/foundation.dart';

import '../repositories/api_mail_repository.dart';
import '../repositories/mail_repository.dart';
import '../repositories/mock_mail_repository.dart';
import '../services/mail_cache.dart';
import '../services/session_store.dart';

/// Central place that decides where the app gets its data.
///
/// Defaults to the mock repository (so `flutter test`/a plain `flutter run`
/// never need the real backend). Run with `--dart-define=USE_MOCK_API=false`
/// to use [ApiMailRepository] instead — see the "Kaydetmail (Real API)" run
/// configuration. The rest of the app only ever talks to [MailRepository]
/// and never checks this flag.
class AppConfig {
  const AppConfig._();

  static const bool useMockApi = bool.fromEnvironment(
    'USE_MOCK_API',
    defaultValue: false,
  );

  /// Push (FCM) stays off until Firebase is configured — see
  /// `docs/push-notifications.md`. Enable with `--dart-define=PUSH_ENABLED=true`.
  static const bool pushEnabled = bool.fromEnvironment('PUSH_ENABLED');

  static MailRepository? _mailRepository;

  /// The single repository instance shared by the whole app.
  static MailRepository get mailRepository => _mailRepository ??= (useMockApi
      ? MockMailRepository()
      : ApiMailRepository(openCache: MailCache.open));

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
