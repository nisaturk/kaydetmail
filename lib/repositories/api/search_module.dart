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

  /// Full-text + filtered search over server-cached mail; reaches mail not
  /// yet loaded into the local buckets.
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
