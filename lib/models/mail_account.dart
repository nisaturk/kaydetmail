import 'package:flutter/foundation.dart';

/// Minimal local representation of a sending account.
///
/// Mock-only for now: just enough for the Compose "Kimden" picker.
/// No credentials, no sync state, no backend contract.
@immutable
class MailAccount {
  const MailAccount({required this.email, this.displayName});

  final String email;
  final String? displayName;

  String get label => displayName ?? email;
}
