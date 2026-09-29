import '../l10n/l10n.dart';

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

final _friendlyFolderNames = {
  'Inbox': l10nNow.inbox,
  'Sent': l10nNow.sent,
  'Drafts': 'Taslaklar',
  'Trash': l10nNow.trash,
  'Junk': 'Spam',
  'Archive': l10nNow.archive,
};

String friendlyFolderName(String folderType, String folderName) =>
    _friendlyFolderNames[folderType] ?? folderName;
