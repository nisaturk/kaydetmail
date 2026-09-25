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

  String get displayName => friendlyFolderName(folderType, folderName);
}

const _friendlyFolderNames = {
  'Inbox': 'Gelen Kutusu',
  'Sent': 'Gönderilenler',
  'Drafts': 'Taslaklar',
  'Trash': 'Çöp Kutusu',
  'Junk': 'Spam',
  'Archive': 'Arşiv',
};

String friendlyFolderName(String folderType, String folderName) =>
    _friendlyFolderNames[folderType] ?? folderName;
