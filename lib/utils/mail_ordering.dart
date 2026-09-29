import '../models/email.dart';

/// Moves pinned mail to the top of an already newest-first list, keeping the
/// newest-first order inside both the pinned and the unpinned group (stable).
///
/// Pinning is per mail and per account (at most three per account), so in the
/// unified mailbox the pinned block simply holds every account's pins.
List<Email> pinnedFirst(Iterable<Email> newestFirst) {
  final pinned = <Email>[];
  final rest = <Email>[];
  for (final email in newestFirst) {
    (email.isPinned ? pinned : rest).add(email);
  }
  return pinned.isEmpty ? rest : [...pinned, ...rest];
}
