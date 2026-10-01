part of '../api_mail_service.dart';

mixin _SearchApi on _ApiMailServiceBase {
  /// Literal term-substring + filtered search over cached server mail. All filters are
  /// optional and AND-ed. Note the singular `hasAttachment` — `/mails` uses
  /// the plural `hasAttachments`.
  Future<MailListPage> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
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
    final path = _buildQuery('/api/search', {
      ..._searchParams(
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
      ),
      'page': '$page',
      'pageSize': '$pageSize',
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return MailListPage(
      items: items
          .map((item) => _mapMail(item as Map<String, dynamic>, resolveFolder))
          .toList(),
      page: body['page'] as int,
      pageSize: body['pageSize'] as int,
      total: body['total'] as int,
    );
  }

  Future<RemoteSearchResult> searchRemote({
    required String query,
    String? folderId,
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
    final body = await _client.get(
      _buildQuery(
        '/api/search/remote',
        _searchParams(
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
        ),
      ),
    );
    return RemoteSearchResult(
      matched: body['matched'] as int,
      imported: body['imported'] as int,
      remaining: body['remaining'] as int,
      complete: body['complete'] as bool,
    );
  }
}
