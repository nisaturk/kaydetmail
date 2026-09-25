import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/email.dart';
import '../repositories/mail_repository.dart';

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

/// Contact list powering the recipient-field autocomplete in compose.
///
/// Two sources feed it: [fromEmails] derives contacts on the fly from
/// whatever mail a [MailRepository] currently holds in memory, and
/// [loadPersisted]/[ingest] accumulate a small deduplicated address book in
/// [SharedPreferences] (a JSON blob, not SQLite — this is a capped list of
/// a few hundred `{name, email, lastSeen}` entries, cheap enough that the
/// extra ceremony a table would need buys nothing) that survives app
/// restarts and keeps growing as mail syncs in the background via
/// [startListening], not just once when compose happens to be open. See
/// [merge] for how compose combines both.
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
      nameSightings
          .putIfAbsent(key, () => [])
          .add(_NameSighting(trimmedName, seenAt));
    }

    for (final email in emails) {
      see(email.senderEmail, email.timestamp);
      seeName(email.senderEmail, email.senderName, email.timestamp);
      for (final address in [...email.recipients, ...email.cc, ...email.bcc]) {
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
      contacts.add(
        Contact(email: address, displayName: name, lastSeen: entry.value),
      );
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

  /// Merges two contact lists, deduping by email (case-insensitive) and
  /// keeping whichever sighting is more recent — used to combine the
  /// persisted address book with whatever mail is currently in memory.
  static List<Contact> merge(List<Contact> a, List<Contact> b) {
    final byEmail = <String, Contact>{};
    for (final contact in [...a, ...b]) {
      final key = contact.email.toLowerCase();
      final current = byEmail[key];
      if (current == null || contact.lastSeen.isAfter(current.lastSeen)) {
        byEmail[key] = contact;
      }
    }
    final merged = byEmail.values.toList()
      ..sort((x, y) => y.lastSeen.compareTo(x.lastSeen));
    return merged;
  }

  /// Most contacts ever kept at once — old, rarely-seen addresses are
  /// dropped first (see [ingest]) once the store grows past this.
  static const int _maxStored = 300;

  static const String _prefsKey = 'contacts_store_v1';

  /// In-memory mirror of the persisted store, warmed by [loadPersisted] and
  /// kept current by [ingest] — synchronous access for UI code that can't
  /// await mid-keystroke (see [cachedPersisted]).
  static List<Contact>? _cache;

  /// Whatever [loadPersisted]/[ingest] have resolved so far, or an empty
  /// list before the first load completes. Safe to call from a synchronous
  /// UI path (e.g. compose's per-keystroke suggestion search) — pair with
  /// [merge] against [fromEmails] of whatever's already in memory so a
  /// cold-not-yet-loaded persisted store never hides contacts that are
  /// visibly available right now.
  static List<Contact> get cachedPersisted => _cache ?? const [];

  /// Loads the persisted address book, caching it in memory afterward —
  /// cheap enough to call repeatedly. Concurrent callers (e.g. the
  /// warm-up call in [startListening] racing an [ingest] triggered by the
  /// very same notification) share one in-flight read via [_pendingLoad]
  /// instead of each independently hitting [SharedPreferences] and
  /// potentially resolving out of order — the last call to finish would
  /// otherwise silently stomp a freshly-ingested [_cache] with a stale
  /// read.
  static Future<List<Contact>> loadPersisted() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _pendingLoad ??= _loadFromPrefs();
  }

  static Future<List<Contact>>? _pendingLoad;

  static Future<List<Contact>> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        _cache = [];
      } else {
        final decoded = jsonDecode(raw) as List;
        _cache = [
          for (final item in decoded.cast<Map<String, dynamic>>())
            Contact(
              email: item['email'] as String,
              displayName: item['name'] as String,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(
                item['seen'] as int,
              ),
            ),
        ];
      }
    } catch (_) {
      _cache = [];
    } finally {
      _pendingLoad = null;
    }
    return _cache!;
  }

  static Future<void> _persist() async {
    final cache = _cache;
    if (cache == null) return;
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode([
      for (final c in cache)
        {
          'email': c.email,
          'name': c.displayName,
          'seen': c.lastSeen.millisecondsSinceEpoch,
        },
    ]);
    await prefs.setString(_prefsKey, json);
  }

  /// Accumulates every From/To/Cc/Bcc address in [emails] into the
  /// persisted address book, deduped by email and capped at [_maxStored]
  /// most-recently-seen entries. Safe to call repeatedly/incrementally —
  /// an already-known contact is only touched when a newer sighting
  /// improves it (see [merge]).
  static Future<void> ingest(Iterable<Email> emails) async {
    final fresh = fromEmails(emails);
    if (fresh.isEmpty) return;
    final current = await loadPersisted();
    final merged = merge(current, fresh);
    _cache = merged.length > _maxStored
        ? merged.sublist(0, _maxStored)
        : merged;
    await _persist();
  }

  static MailRepository? _listenedRepo;
  static VoidCallback? _repoListener;
  static final Set<String> _ingestedMailIds = {};

  /// Starts listening to [repo] so the persisted address book keeps growing
  /// as mail syncs in the background, not just once at compose open —
  /// idempotent, safe to call from every compose screen open. Only mail
  /// with an id not seen before is re-scanned, so a `notifyListeners()`
  /// fired by an unrelated change (e.g. marking mail read) costs a cheap
  /// set lookup, not a full re-ingest.
  static void startListening(MailRepository repo) {
    if (identical(_listenedRepo, repo)) return;
    final previousRepo = _listenedRepo;
    final previousListener = _repoListener;
    if (previousRepo != null && previousListener != null) {
      previousRepo.removeListener(previousListener);
    }
    unawaited(loadPersisted());
    void listener() {
      final newOnes = [
        for (final email in repo.getAllEmails())
          if (_ingestedMailIds.add(email.id)) email,
      ];
      if (newOnes.isEmpty) return;
      unawaited(ingest(newOnes));
    }

    _listenedRepo = repo;
    _repoListener = listener;
    repo.addListener(listener);
    listener();
  }

  /// Test-only reset — clears every static cache/listener between tests
  /// that use different [SharedPreferences] mocks or repositories.
  @visibleForTesting
  static void resetForTest() {
    final repo = _listenedRepo;
    final listener = _repoListener;
    if (repo != null && listener != null) repo.removeListener(listener);
    _cache = null;
    _pendingLoad = null;
    _ingestedMailIds.clear();
    _listenedRepo = null;
    _repoListener = null;
  }
}
