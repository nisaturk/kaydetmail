import 'package:flutter/foundation.dart';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../models/remote_search_result.dart';
import '../../models/search_page.dart';
import 'account_session.dart';
import 'repository_context.dart';

/// Server-side search (`GET /api/search`, and the user-started IMAP search),
/// fanned out over every connected account or narrowed to one. The in-screen
/// search over already-loaded mail stays client-side in `MailRepository`.
class SearchModule {
  SearchModule(this._ctx);

  final RepositoryContext _ctx;

  /// The sessions to query, each with the server folder id the requested
  /// (logical or custom) folder resolves to there. A session that lacks the
  /// folder is skipped entirely rather than searched unfiltered.
  Iterable<(AccountSession, String?)> _targets({
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
  }) sync* {
    final sessions = accountId == null
        ? _ctx.registry.sessions.values
        : [?_ctx.registry.sessions[accountId]];
    for (final session in sessions) {
      final folderId =
          customFolderId ?? (folder == null ? null : session.folderIds[folder]);
      if (customFolderId != null &&
          !session.customFolders.any((item) => item.id == customFolderId)) {
        continue;
      }
      if (folder != null && folderId == null) continue;
      yield (session, folderId);
    }
  }

  /// Literal term-substring + filtered search over server-cached mail, with
  /// a device-cache fallback only when the server cannot be reached.
  Future<SearchPage> searchOnServer({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
    SearchContinuation? continuation,
    int pageSize = 20,
  }) async {
    final targets = _targets(
      accountId: accountId,
      folder: folder,
      customFolderId: customFolderId,
    ).toList();
    final size = pageSize < 1 ? 20 : pageSize;
    final scope = <Object?>[
      query,
      accountId,
      folder,
      customFolderId,
      conversationId,
      from,
      to,
      fromDate,
      toDate,
      isRead,
      flagged,
      hasAttachment,
      labelId,
      size,
      for (final (session, folderId) in targets) ...[
        session,
        session.account.id,
        folderId,
      ],
    ];
    if (continuation != null && !listEquals(scope, continuation.scope)) {
      throw ArgumentError('Search continuation belongs to a different scope');
    }
    final states = <String, SearchAccountCursor>{...?continuation?.accounts};

    Future<SearchAccountCursor> fetch(
      AccountSession session,
      String? folderId,
      SearchAccountCursor? previous,
    ) async {
      final page = previous?.nextPage ?? 1;
      try {
        final results = await session.mailService.search(
          query: query,
          resolveFolder: session.resolveFolder,
          folderId: folderId,
          conversationId: conversationId,
          from: from,
          to: to,
          fromDate: fromDate,
          toDate: toDate,
          isRead: isRead,
          flagged: flagged,
          hasAttachment: hasAttachment,
          labelId: labelId,
          page: page,
          pageSize: size,
        );
        return SearchAccountCursor(
          buffered: results.items.map(session.stampLocalFlags).toList(),
          nextPage: results.page + 1,
          total: results.total,
          consumed: previous?.consumed ?? 0,
          remoteHasMore: results.page * results.pageSize < results.total,
          offline: false,
        );
      } catch (error) {
        if (!_ctx.isOfflineFailure(error)) rethrow;
        // A running server search must not silently swap to a smaller local
        // corpus. Keep its checkpoint so the user can retry this exact page.
        if (previous != null) rethrow;
        _ctx.markOffline(session);
        final buckets = customFolderId != null
            ? [session.customFolderEmails[customFolderId] ?? const <Email>[]]
            : folder != null
            ? [session.emails[folder] ?? const <Email>[]]
            : [...session.emails.values, ...session.customFolderEmails.values];
        final unique = {
          for (final bucket in buckets)
            for (final email in bucket)
              email.id: session.stampLocalFlags(email),
        };
        final fromTerm = from?.trim().toLowerCase() ?? '';
        final toTerm = to?.trim().toLowerCase() ?? '';
        final matches =
            unique.values.where((email) {
              return email.matchesQuery(query) &&
                  (conversationId == null ||
                      email.threadId == conversationId) &&
                  (labelId == null || email.labelIds.contains(labelId)) &&
                  (isRead == null || email.isRead == isRead) &&
                  (flagged == null || email.isStarred == flagged) &&
                  (hasAttachment == null ||
                      (email.hasAttachments || email.attachments.isNotEmpty) ==
                          hasAttachment) &&
                  (fromDate == null || !email.timestamp.isBefore(fromDate)) &&
                  (toDate == null || email.timestamp.isBefore(toDate)) &&
                  (fromTerm.isEmpty ||
                      email.senderEmail.toLowerCase().contains(fromTerm) ||
                      email.senderName.toLowerCase().contains(fromTerm)) &&
                  (toTerm.isEmpty ||
                      [
                        ...email.recipients,
                        ...email.cc,
                        ...email.bcc,
                      ].any((value) => value.toLowerCase().contains(toTerm)));
            }).toList()..sort((a, b) {
              final date = b.timestamp.compareTo(a.timestamp);
              return date != 0 ? date : b.id.compareTo(a.id);
            });
        _ctx.notify();
        return SearchAccountCursor(
          buffered: matches,
          nextPage: 1,
          total: matches.length,
          consumed: 0,
          remoteHasMore: false,
          offline: true,
        );
      }
    }

    for (final (session, folderId) in targets) {
      final id = session.account.id;
      if (!states.containsKey(id)) {
        states[id] = await fetch(session, folderId, null);
      }
    }
    final items = <Email>[];
    while (items.length < size) {
      // Refill exhausted heads before choosing the globally newest result.
      // Other accounts retain their unconsumed rows, rather than skipping
      // them when a global page is dominated by one account.
      for (final (session, folderId) in targets) {
        final id = session.account.id;
        final state = states[id]!;
        if (!state.hasBuffered && state.remoteHasMore) {
          final next = await fetch(session, folderId, state);
          if (!next.hasBuffered && next.remoteHasMore) {
            throw StateError('Search returned an empty page with more results');
          }
          states[id] = next;
        }
      }
      String? selected;
      for (final entry in states.entries) {
        if (!entry.value.hasBuffered) continue;
        if (selected == null ||
            entry.value.head.timestamp.isAfter(
              states[selected]!.head.timestamp,
            ) ||
            (entry.value.head.timestamp == states[selected]!.head.timestamp &&
                entry.key.compareTo(selected) < 0)) {
          selected = entry.key;
        }
      }
      if (selected == null) break;
      final state = states[selected]!;
      items.add(state.head);
      states[selected] = state.advance();
    }
    return SearchPage(
      items: items,
      continuation: SearchContinuation(scope: scope, accounts: states),
    );
  }

  /// User-started IMAP search that imports matches missing from the server
  /// index; the counters are summed across accounts.
  Future<RemoteSearchResult> searchRemote({
    required String query,
    String? accountId,
    MailFolder? folder,
    String? customFolderId,
    String? conversationId,
    String? from,
    String? to,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isRead,
    bool? flagged,
    bool? hasAttachment,
    String? labelId,
  }) async {
    var matched = 0;
    var imported = 0;
    var remaining = 0;
    var complete = true;
    for (final (session, folderId) in _targets(
      accountId: accountId,
      folder: folder,
      customFolderId: customFolderId,
    )) {
      final result = await session.mailService.searchRemote(
        query: query,
        folderId: folderId,
        conversationId: conversationId,
        from: from,
        to: to,
        fromDate: fromDate,
        toDate: toDate,
        isRead: isRead,
        flagged: flagged,
        hasAttachment: hasAttachment,
        labelId: labelId,
      );
      matched += result.matched;
      imported += result.imported;
      remaining += result.remaining;
      complete = complete && result.complete;
    }
    return RemoteSearchResult(
      matched: matched,
      imported: imported,
      remaining: remaining,
      complete: complete,
    );
  }
}
