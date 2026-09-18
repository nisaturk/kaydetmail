import '../models/email.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import 'api_client.dart';

class ApiMailService {
  ApiMailService(this._client);

  final ApiClient _client;

  Future<MailAccount> getAccount() async {
    final body = await _client.get('/api/account');
    return MailAccount(
      id: body['id'] as String,
      email: body['emailAddress'] as String,
      displayName: body['displayName'] as String?,
      provider: AccountProvider.fromBackend(body['provider'] as String),
    );
  }

  Future<List<ApiMailFolder>> getFolders() async {
    final items = await _client.getList('/api/folders');
    return items
        .map(
          (item) => ApiMailFolder(
            id: item['id'] as String,
            mailAccountId: item['mailAccountId'] as String,
            name: item['name'] as String,
            type: item['folderType'] as String,
          ),
        )
        .toList();
  }

  Future<MailListPage> getMails({
    required String folderId,
    required MailFolder Function(String folderId) resolveFolder,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = _buildQuery('/api/mails', {
      'folderId': folderId,
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

  Future<Email> getMail(
    String id, {
    required MailFolder Function(String folderId) resolveFolder,
  }) async {
    final body = await _client.get('/api/mails/$id');
    return _mapMailDetail(body, resolveFolder);
  }

  /// One of the nine fixed single-mail actions documented for
  /// `POST /api/mails/{id}/{action}` (read, unread, star, unstar, trash,
  /// restore, archive, spam, not-spam). No request/response body.
  Future<void> mailAction(String id, String action) =>
      _client.post('/api/mails/${Uri.encodeComponent(id)}/$action');

  /// Moves a single mail into an arbitrary target folder.
  Future<void> moveMail(String id, String folderId) =>
      _client.postJson('/api/mails/${Uri.encodeComponent(id)}/move', {
        'folderId': folderId,
      });

  /// Applies [action] (read, unread, archive, trash, or move) to every id in
  /// [mailIds] in one request. Each mail is processed independently server
  /// side — read the per-item [BulkActionResult.success] rather than
  /// assuming the whole batch succeeded or failed together.
  Future<List<BulkActionResult>> bulkAction(
    String action,
    List<String> mailIds, {
    String? folderId,
  }) async {
    final body = await _client.postJson('/api/mails/bulk/$action', {
      'mailIds': mailIds,
      'folderId': folderId,
    });
    final results = body['results'] as List;
    return results
        .map(
          (r) => BulkActionResult(
            mailId: r['mailId'] as String,
            success: r['success'] as bool,
            code: r['code'] as String?,
          ),
        )
        .toList();
  }

  Future<List<Email>> search({
    required String query,
    required MailFolder Function(String folderId) resolveFolder,
    String? folderId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final path = _buildQuery('/api/search', {
      'q': query,
      'page': '$page',
      'pageSize': '$pageSize',
      'folderId': ?folderId,
    });
    final body = await _client.get(path);
    final items = body['items'] as List;
    return items
        .map((item) => _mapMail(item as Map<String, dynamic>, resolveFolder))
        .toList();
  }

  String _buildQuery(String path, Map<String, String> params) {
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$path?$query';
  }

  Email _mapMail(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) => Email(
    id: item['id'] as String,
    senderName: item['fromDisplayName'] as String? ?? '',
    senderEmail: item['fromAddress'] as String,
    recipients: (item['toAddress'] as String?) != null
        ? [item['toAddress'] as String]
        : const [],
    subject: item['subject'] as String,
    bodyText: item['bodyText'] as String? ?? '',
    timestamp:
        DateTime.tryParse(item['receivedAt'] as String) ?? DateTime.now(),
    isRead: item['isRead'] as bool? ?? false,
    isStarred: item['flagged'] as bool? ?? false,
    accountId: item['accountId'] as String? ?? '',
    folder: resolveFolder(item['folderId'] as String),
  );

  Email _mapMailDetail(
    Map<String, dynamic> item,
    MailFolder Function(String folderId) resolveFolder,
  ) {
    final fromList =
        (item['from'] as List?)?.cast<Map<String, dynamic>>().toList() ?? [];
    final toList =
        (item['to'] as List?)?.cast<Map<String, dynamic>>().toList() ?? [];
    return Email(
      id: item['id'] as String,
      senderName: fromList.isNotEmpty
          ? fromList.first['displayName'] as String? ?? ''
          : '',
      senderEmail: fromList.isNotEmpty
          ? fromList.first['address'] as String
          : '',
      recipients: toList.map((e) => e['address'] as String).toList(),
      subject: item['subject'] as String,
      bodyText: item['bodyText'] as String? ?? '',
      timestamp:
          DateTime.tryParse(item['receivedAt'] as String) ?? DateTime.now(),
      isRead: item['isRead'] as bool? ?? false,
      isStarred: item['flagged'] as bool? ?? false,
      accountId: item['accountId'] as String? ?? '',
      folder: resolveFolder(item['folderId'] as String),
    );
  }
}

class ApiMailFolder {
  const ApiMailFolder({
    required this.id,
    required this.mailAccountId,
    required this.name,
    required this.type,
  });

  final String id;
  final String mailAccountId;
  final String name;
  final String type;
}

/// Per-item outcome from `POST /api/mails/bulk/{action}`.
class BulkActionResult {
  const BulkActionResult({
    required this.mailId,
    required this.success,
    this.code,
  });

  final String mailId;
  final bool success;

  /// Failure error code (see the mail action error table), null on success.
  final String? code;
}

class MailListPage {
  MailListPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<Email> items;
  final int page;
  final int pageSize;
  final int total;
}
