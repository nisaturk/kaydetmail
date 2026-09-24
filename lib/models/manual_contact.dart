import 'package:flutter/foundation.dart';

/// A contact the user explicitly added, independent of any mail ever
/// exchanged with them — for people they want suggested in compose before
/// the first message. Distinct from the mail-participant-derived
/// suggestions in `ContactsStore`: this list is small, manually curated,
/// and synced through the backend so every device signed into the account
/// sees the same entries.
@immutable
class ManualContact {
  const ManualContact({
    required this.id,
    required this.accountId,
    required this.email,
    this.displayName,
  });

  final String id;
  final String accountId;
  final String email;
  final String? displayName;

  /// Best label to show in a list/autocomplete — the display name when set,
  /// otherwise the email itself.
  String get label => (displayName == null || displayName!.isEmpty)
      ? email
      : displayName!;
}
