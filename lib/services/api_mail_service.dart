import '../models/email.dart';
import '../models/mail_account.dart';
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
    int page = 1,
    int pageSize = 20,
  }) async {
    final path =
        '/api/mails?folderId=${Uri.encodeQueryComponent(folderId)}'
        '&page=$page&pageSize=$pageSize';
    final body = await _client.get(path);
    final items = body['items'] as List;
    return MailListPage(
      items: items.map((item) => _mapMail(item)).toList(),
      page: body['page'] as int,
      pageSize: body['pageSize'] as int,
      total: body['total'] as int,
    );
  }

  Future<Email> getMail(String id) async {
    final body = await _client.get('/api/mails/$id');
    return _mapMailDetail(body);
  }

  Future<List<Email>> search({
    required String query,
    String? folderId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final queryParams = <String, String>{
      'q': query,
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (folderId != null) queryParams['folderId'] = folderId;
    final uriPath =
        '/api/search?${queryParams.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final body = await _client.get(uriPath);
    final items = body['items'] as List;
    return MailListPage(
      items: items.map((item) => _mapMail(item)).toList(),
      page: body['page'] as int,
      pageSize: body['pageSize'] as int,
      total: body['total'] as int,
    ).items;
  }

  Email _mapMail(Map<String, dynamic> item) => Email(
    id: item['id'] as String,
    senderName: item['fromDisplayName'] as String? ?? '',
    senderEmail: item['fromAddress'] as String,
    recipients: (item['toAddress'] as String?) != null
        ? [item['toAddress'] as String]
        : const [],
    subject: item['subject'] as String,
    bodyText: item.containsKey('bodyText') ? item['bodyText'] as String : '',
    timestamp:
        DateTime.tryParse(item['receivedAt'] as String) ?? DateTime.now(),
    isRead: item['isRead'] as bool? ?? false,
    isStarred: item['flagged'] as bool? ?? false,
    accountId: item['accountId'] as String? ?? '',
  );

  Email _mapMailDetail(Map<String, dynamic> item) {
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
