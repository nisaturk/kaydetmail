import '../models/mail_account.dart';

/// Result of a successful account-connection flow: who was connected and
/// through which provider. Carries no tokens — mock-only for now.
class ConnectedAccount {
  const ConnectedAccount({
    required this.email,
    this.displayName,
    required this.provider,
  });

  final String email;
  final String? displayName;
  final AccountProvider provider;
}

/// How KAYDET connects a new mailbox account.
///
/// Mock-first: [MockAccountConnection] simulates the flow with a short delay
/// and infers the provider from the email domain. Later this gets replaced by
/// [GoogleOAuthAccountConnection], [MicrosoftOAuthAccountConnection] and
/// [ImapAccountConnection] without touching the repository or the UI — they
/// only ever see [ConnectedAccount].
abstract class AccountConnection {
  Future<ConnectedAccount> connect({
    required String email,
    String? displayName,
    AccountProvider? provider,
  });
}

class MockAccountConnection implements AccountConnection {
  MockAccountConnection({this.latency = const Duration(milliseconds: 350)});

  final Duration latency;

  @override
  Future<ConnectedAccount> connect({
    required String email,
    String? displayName,
    AccountProvider? provider,
  }) async {
    final normalized = email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized)) {
      throw ArgumentError('Geçerli bir e-posta adresi girin.');
    }
    await Future<void>.delayed(latency);
    return ConnectedAccount(
      email: normalized,
      displayName: displayName?.trim().isEmpty ?? true ? null : displayName,
      provider: provider ?? AccountProvider.inferFromEmail(normalized),
    );
  }
}
