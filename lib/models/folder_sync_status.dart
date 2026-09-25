class FolderSyncStatus {
  const FolderSyncStatus({
    required this.folderId,
    required this.folderName,
    required this.folderType,
    required this.backfillComplete,
    this.lastSuccessfulSyncAt,
    this.lastFailureAt,
    this.lastFailureCategory,
    required this.consecutiveFailures,
  });

  final String folderId;
  final String folderName;
  final String folderType;
  final bool backfillComplete;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? lastFailureAt;
  final String? lastFailureCategory;
  final int consecutiveFailures;

  static const _friendlyNames = {
    'Inbox': 'Gelen Kutusu',
    'Sent': 'Gönderilenler',
    'Drafts': 'Taslaklar',
    'Trash': 'Çöp Kutusu',
    'Junk': 'Spam',
    'Archive': 'Arşiv',
  };

  String get displayName => _friendlyNames[folderType] ?? folderName;
}
