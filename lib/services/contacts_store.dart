import 'package:flutter/foundation.dart';

import '../models/email.dart';

/// One known recipient, derived from mail already loaded on-device.
@immutable
class Contact {
  const Contact({
    required this.email,
    required this.displayName,
    required this.lastSeen,
  });

  final String email;

  /// The best-known name for [email] — the most recent sender-name sighting
  /// for that address, or [email] itself when none was ever seen (To/Cc/Bcc
  /// entries never carry a display name in [Email], only senders do).
  final String displayName;

  /// Timestamp of the most recent mail this address appeared on, in any of
  /// From/To/Cc/Bcc — powers the most-recently-seen-first ordering.
  final DateTime lastSeen;
}

class _NameSighting {
  _NameSighting(this.name, this.seenAt);

  final String name;
  final DateTime seenAt;
}

/// Deduplicated contact list derived from every mail the repository holds —
/// no separate storage of its own (unlike [SignatureStore]/
/// `LocalMailFlagsStore`), since it is always cheap to recompute from
/// `MailRepository.getAllEmails()`. Powers the recipient-field autocomplete
/// in compose.
class ContactsStore {
  ContactsStore._();

  /// Derives contacts from [emails]: every From/To/Cc/Bcc address across
  /// every mail, sorted most-recently-seen first. Pure function so it is
  /// trivially testable without a repository.
  static List<Contact> fromEmails(Iterable<Email> emails) {
    final lastSeen = <String, DateTime>{};
    final addressCasing = <String, String>{};
    final nameSightings = <String, List<_NameSighting>>{};

    void see(String rawAddress, DateTime seenAt) {
      final address = rawAddress.trim();
      if (address.isEmpty) return;
      final key = address.toLowerCase();
      addressCasing.putIfAbsent(key, () => address);
      final current = lastSeen[key];
      if (current == null || seenAt.isAfter(current)) {
        lastSeen[key] = seenAt;
      }
    }

    void seeName(String rawAddress, String name, DateTime seenAt) {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return;
      final key = rawAddress.trim().toLowerCase();
      if (key.isEmpty) return;
      nameSightings.putIfAbsent(key, () => []).add(
        _NameSighting(trimmedName, seenAt),
      );
    }

    for (final email in emails) {
      see(email.senderEmail, email.timestamp);
      seeName(email.senderEmail, email.senderName, email.timestamp);
      for (final address in [
        ...email.recipients,
        ...email.cc,
        ...email.bcc,
      ]) {
        see(address, email.timestamp);
      }
    }

    final contacts = <Contact>[];
    for (final entry in lastSeen.entries) {
      final key = entry.key;
      final address = addressCasing[key]!;
      final sightings = nameSightings[key];
      var name = address;
      if (sightings != null && sightings.isNotEmpty) {
        sightings.sort((a, b) => b.seenAt.compareTo(a.seenAt));
        name = sightings.first.name;
      }
      contacts.add(Contact(email: address, displayName: name, lastSeen: entry.value));
    }
    contacts.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return contacts;
  }

  /// Contacts in [contacts] whose email or display name contains [query]
  /// (case-insensitive). Empty [query] matches nothing — the autocomplete
  /// only opens once the user has actually typed something.
  static List<Contact> search(List<Contact> contacts, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final contact in contacts)
        if (contact.email.toLowerCase().contains(q) ||
            contact.displayName.toLowerCase().contains(q))
          contact,
    ];
  }
}
