import 'package:flutter/foundation.dart';

/// Which provider a connected account belongs to.
///
/// Mock-first: inferred from the email domain (`gmail.com` → Google,
/// `outlook.com`/`hotmail.com`/`live.com` → Microsoft, anything else →
/// Other/IMAP). Real OAuth connections will set this explicitly later.
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

/// One connected mailbox account.
///
/// Identity comes from the backend. Mock mode explicitly derives an id when
/// it provisions its in-memory accounts. Whether an account is currently active
/// is NOT stored here — the repository owns the active account id.
@immutable
class MailAccount {
  const MailAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.provider = AccountProvider.other,
  });

  final String id;
  final String email;
  final String? displayName;
  final AccountProvider provider;

  String get label => displayName ?? email;
}
