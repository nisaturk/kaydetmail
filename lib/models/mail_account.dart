import 'package:flutter/foundation.dart';

/// Which provider a connected account belongs to.
///
/// Set from the backend when known ([fromBackend]); otherwise inferred from
/// the email domain ([inferFromEmail]): `gmail.com` → Google,
/// `outlook.com`/`hotmail.com`/`live.com` → Microsoft, anything else →
/// Other/IMAP.
enum AccountProvider {
  google,
  microsoft,
  other;

  /// Turkish label shown in the Accounts screen.
  String get label => switch (this) {
    AccountProvider.google => 'Google',
    AccountProvider.microsoft => 'Microsoft',
    AccountProvider.other => 'Diğer',
  };

  /// Infers the provider from an email address. Pure function so tests and
  /// future connection flows share one rule.
  static AccountProvider fromBackend(String value) => switch (value) {
    'Google' => AccountProvider.google,
    'Microsoft' => AccountProvider.microsoft,
    _ => AccountProvider.other,
  };

  /// Infers the provider from an email address. Pure function so tests and
  /// future connection flows share one rule.
  static AccountProvider inferFromEmail(String email) {
    final domain = email.trim().toLowerCase().split('@').lastOrNull ?? '';
    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      return AccountProvider.google;
    }
    if (domain == 'outlook.com' ||
        domain == 'hotmail.com' ||
        domain == 'live.com') {
      return AccountProvider.microsoft;
    }
    return AccountProvider.other;
  }
}

/// Backend account state (`GET /api/account` → `status`).
///
/// `needsReauthentication` means the stored credentials no longer work —
/// route the user to the reconnect flow (`POST /api/account/reconnect`).
/// `disabled` locks everything out until the account is removed server-side.
enum MailAccountStatus {
  active,
  needsReauthentication,
  connectionError,
  disabled;

  static MailAccountStatus fromBackend(String? value) => switch (value) {
    'NeedsReauthentication' => MailAccountStatus.needsReauthentication,
    'ConnectionError' => MailAccountStatus.connectionError,
    'Disabled' => MailAccountStatus.disabled,
    _ => MailAccountStatus.active,
  };
}

/// One connected mailbox account.
///
/// Identity (`id`) comes from the backend. Whether an account is currently
/// active is NOT stored here — the repository owns the active account id.
@immutable
class MailAccount {
  const MailAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.provider = AccountProvider.other,
    this.status = MailAccountStatus.active,
  });

  final String id;
  final String email;
  final String? displayName;
  final AccountProvider provider;
  final MailAccountStatus status;

  String get label => displayName ?? email;
}
