import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../models/remote_search_result.dart';
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
  Future<List<Email>> searchOnServer({
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
    int page = 1,
    int pageSize = 20,
  }) async {
    final all = <Email>[];
    for (final (session, folderId) in _targets(
      accountId: accountId,
      folder: folder,
      customFolderId: customFolderId,
    )) {
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
          pageSize: pageSize,
        );
        all.addAll(results.map(session.stampLocalFlags));
      } catch (error) {
        if (!_ctx.isOfflineFailure(error)) rethrow;
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
        final effectivePage = page < 1 ? 1 : page;
        final effectiveSize = pageSize < 1 ? 50 : pageSize;
        all.addAll(
          matches.skip((effectivePage - 1) * effectiveSize).take(effectiveSize),
        );
        _ctx.notify();
      }
    }
    return all;
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
