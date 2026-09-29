part of '../api_mail_service.dart';

mixin _AccountApi on _ApiMailServiceBase {
  Future<MailAccount> getAccount() async {
    final body = await _client.get('/api/account');
    return _mapAccount(body);
  }

  /// Current account's mailbox storage usage, or `null` when the IMAP server
  /// does not expose QUOTA (or refused the request).
  Future<AccountQuota?> getQuota() async {
    final body = await _client.get('/api/account/quota');
    final used = body['usedBytes'];
    final limit = body['limitBytes'];
    if (body['available'] != true || used is! num || limit is! num) {
      return null;
    }
    if (limit <= 0) return null;
    return AccountQuota(usedBytes: used.toInt(), limitBytes: limit.toInt());
  }

  /// Sets or clears (blank/null) the signature appended to outgoing mail
  /// from this account — synced, so every device signed into it sees it.
  Future<void> updateSignature(String? signature) =>
      _client.putJson('/api/account/signature', {'signature': signature});

  /// Re-authenticates the signed-in account after its stored credentials
  /// stopped working (`mail_account_needs_reauthentication`). `imap`/`smtp`
  /// are optional — omitted servers keep their current settings, only the
  /// credentials are replaced. Answers with the same `AccountResponse` shape
  /// as [getAccount]. Reconnect is Bearer-authenticated; a brand-new device
  /// without a token uses `POST /api/accounts/login` instead — never this.
  Future<MailAccount> reconnect({
    required String password,
    ManualMailServer? imap,
    ManualMailServer? smtp,
  }) async {
    final body = await _client.postJson('/api/account/reconnect', {
      'authentication': {'type': 'Password', 'password': password},
      if (imap != null) 'imap': imap.toJson(),
      if (smtp != null) 'smtp': smtp.toJson(),
    });
    return _mapAccount(body);
  }

  /// Permanently deletes the connected account and all its cached mail.
  Future<void> deleteAccount() => _client.delete('/api/account');

  Future<List<MailSession>> getSessions() async {
    final items = await _client.getList('/api/account/sessions');
    return items
        .map(
          (item) => MailSession(
            id: item['id'] as String,
            deviceIdentifier: (item['deviceIdentifier'] as String?) ?? '—',
            createdAt: _date(item['createdAt']),
            lastUsedAt: _date(item['lastUsedAt'] ?? item['createdAt']),
            expiresAt: _date(item['expiresAt']),
          ),
        )
        .toList();
  }

  Future<void> deleteSession(String sessionId) =>
      _client.delete('/api/account/sessions/${Uri.encodeComponent(sessionId)}');

  Future<List<FolderSyncStatus>> getSyncStatus() async {
    final items = await _client.getList('/api/account/sync-status');
    return items
        .map(
          (item) => FolderSyncStatus(
            folderId: item['folderId'] as String,
            folderName: item['folderName'] as String,
            folderType: item['folderType'] as String,
            backfillComplete: item['backfillComplete'] as bool,
            lastSuccessfulSyncAt: _optionalDate(item['lastSuccessfulSyncAt']),
            lastFailureAt: _optionalDate(item['lastFailureAt']),
            lastFailureCategory: item['lastFailureCategory'] as String?,
            consecutiveFailures: item['consecutiveFailures'] as int,
          ),
        )
        .toList();
  }

  Future<({String scope, Set<String> syncedFolderIds})> getSyncScope() async =>
      _mapSyncScope(await _client.get('/api/account/sync-scope'));

  Future<({String scope, Set<String> syncedFolderIds})> updateSyncScope(
    String scope, {
    List<String>? folderIds,
  }) async => _mapSyncScope(
    await _client.putJson('/api/account/sync-scope', {
      'scope': scope,
      'folderIds': ?folderIds,
    }),
  );

  Future<AccountNotificationSettings> getNotificationSettings() async =>
      AccountNotificationSettings.fromJson(
        await _client.get('/api/account/notification-settings'),
      );

  Future<AccountNotificationSettings> updateNotificationSettings(
    AccountNotificationSettings settings,
  ) async => AccountNotificationSettings.fromJson(
    await _client.putJson(
      '/api/account/notification-settings',
      settings.toJson(),
    ),
  );

  /// Registers (or upserts — same token twice just updates) this device for
  /// FCM pushes (`POST /api/devices`, `201`). Safe to call on every launch.
  Future<DeviceRegistration> registerDevice({
    required String token,
    required String platform,
    required String appVersion,
    required String locale,
  }) async {
    final body = await _client.postJson('/api/devices', {
      'token': token,
      'platform': platform,
      'appVersion': appVersion,
      'locale': locale,
    });
    return DeviceRegistration(
      id: body['id'] as String,
      platform: body['platform'] as String? ?? platform,
      appVersion: body['appVersion'] as String? ?? appVersion,
      locale: body['locale'] as String? ?? locale,
      registeredAt: _optionalDate(body['registeredAt']),
      lastSeenAt: _optionalDate(body['lastSeenAt']),
    );
  }

  /// Removes this device's push registration (`DELETE /api/devices/{id}`,
  /// `204`) — called on logout and when notifications are disabled.
  Future<void> unregisterDevice(String id) =>
      _client.delete('/api/devices/${Uri.encodeComponent(id)}');
}
