import 'package:flutter/foundation.dart';

import '../repositories/api_mail_repository.dart';
import '../repositories/mail_repository.dart';
import '../repositories/mock_mail_repository.dart';

/// Central place that decides where the app gets its data.
///
/// Flip [useMockApi] to `false` once the real backend is ready. The rest of
/// the app only ever talks to [MailRepository] and never checks this flag.
class AppConfig {
  const AppConfig._();

  /// Set to `false` to use [ApiMailRepository] instead of [MockMailRepository].
  static const bool useMockApi = true;

  static MailRepository? _mailRepository;

  /// The single repository instance shared by the whole app.
  static MailRepository get mailRepository =>
      _mailRepository ??=
          (useMockApi ? MockMailRepository() : ApiMailRepository());

  /// Lets widget tests start from a fresh repository instance.
  @visibleForTesting
  static void resetForTest() {
    _mailRepository = null;
  }
}