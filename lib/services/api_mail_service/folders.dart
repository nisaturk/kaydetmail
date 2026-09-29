part of '../api_mail_service.dart';

mixin _FolderApi on _ApiMailServiceBase {
  Future<List<ApiMailFolder>> getFolders() async {
    final items = await _client.getList('/api/folders');
    return items
        .map((item) => ApiMailFolder.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ApiMailFolder> createFolder(String name, {String? parentId}) async =>
      ApiMailFolder.fromJson(
        await _client.postJson('/api/folders', {
          'name': name,
          'parentId': parentId,
        }),
      );

  Future<ApiMailFolder> renameFolder(String id, String name) async =>
      ApiMailFolder.fromJson(
        await _client.patchJson('/api/folders/${Uri.encodeComponent(id)}', {
          'name': name,
        }),
      );

  /// Null moves the folder to the personal namespace root.
  Future<ApiMailFolder> setFolderParent(String id, String? parentId) async =>
      ApiMailFolder.fromJson(
        await _client.putJson(
          '/api/folders/${Uri.encodeComponent(id)}/parent',
          {'parentId': parentId},
        ),
      );

  /// `PUT /api/folders/{id}/role`: [role] is `Sent`, `Drafts`, `Trash`,
  /// `Junk`, or null to restore server-side detection.
  Future<ApiMailFolder> setFolderRole(String id, String? role) async =>
      ApiMailFolder.fromJson(
        await _client.putJson('/api/folders/${Uri.encodeComponent(id)}/role', {
          'role': role,
        }),
      );

  Future<void> deleteFolder(String id) =>
      _client.delete('/api/folders/${Uri.encodeComponent(id)}');

  /// Re-discovers the server-side folder tree (`202 Accepted` +
  /// `{ folders: N }`). The result applies asynchronously — re-fetch with
  /// [getFolders] afterwards. Returns the reported folder count (`0` when
  /// the 202 carries no body).
  Future<int> refreshFolders() async {
    final body = await _client.postJson('/api/folders/refresh', {});
    return (body['folders'] as num?)?.toInt() ?? 0;
  }

  /// Queues a server sync and waits for its terminal result. A lost/expired
  /// job cannot be mistaken for success; the caller may retry explicitly.
  Future<void> syncFolderId(String folderId) async {
    final accepted = await _client.postWithHeaders(
      '/api/folders/${Uri.encodeComponent(folderId)}/sync',
      const {},
    );
    final jobId = accepted['jobId'];
    if (jobId is! String || jobId.isEmpty) {
      throw const FormatException('Missing folder sync job id');
    }
    final deadline = DateTime.now().add(syncTimeout);
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Folder sync did not finish', syncTimeout);
      }
      final job = await _client.get(
        '/api/folders/sync-jobs/${Uri.encodeComponent(jobId)}',
      );
      if (job['jobId'] != jobId) {
        throw const FormatException('Mismatched folder sync job id');
      }
      switch (job['status']) {
        case 'succeeded':
          return;
        case 'failed':
          final code = job['errorCode'];
          throw ApiException(
            status: 503,
            code: code is String && code.isNotEmpty ? code : 'sync_failed',
          );
        case 'queued':
        case 'running':
          await Future<void>.delayed(syncPollInterval);
        default:
          throw const FormatException('Unexpected folder sync status');
      }
    }
  }
}
