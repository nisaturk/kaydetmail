import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

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
    AccountProvider.other => l10nNow.other,
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

/// Mailbox storage usage reported by the IMAP server's QUOTA extension.
/// Absent (`null` on [MailAccount.quota]) when the server has no quota.
@immutable
class AccountQuota {
  const AccountQuota({required this.usedBytes, required this.limitBytes});

  final int usedBytes;
  final int limitBytes;

  /// Share of the limit in use, clamped to 0..1 (servers may over-report).
  double get usedFraction =>
      limitBytes <= 0 ? 0 : (usedBytes / limitBytes).clamp(0.0, 1.0);

  /// Whole-number percentage shown next to the usage bar.
  int get usedPercent =>
      limitBytes <= 0 ? 0 : (usedBytes * 100 / limitBytes).round();
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
    this.signature,
    this.quota,
  });

  final String id;
  final String email;
  final String? displayName;
  final AccountProvider provider;
  final MailAccountStatus status;

  /// Text appended to outgoing mail sent from this account. Synced to the
  /// backend — every device signed into this account sees the same value.
  final String? signature;
  final AccountQuota? quota;

  String get label => displayName ?? email;

  /// `signature: null` clears it — unlike most copyWith patterns, omitting
  /// the parameter (not passing it at all) keeps the current value.
  MailAccount copyWith({
    String? displayName,
    Object? signature = _unset,
    Object? quota = _unset,
  }) => MailAccount(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    provider: provider,
    status: status,
    signature: identical(signature, _unset)
        ? this.signature
        : signature as String?,
    quota: identical(quota, _unset) ? this.quota : quota as AccountQuota?,
  );
}

const _unset = Object();
