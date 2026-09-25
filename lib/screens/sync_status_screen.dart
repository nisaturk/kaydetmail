import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _AccountSyncState {
  _AccountSyncState.loading()
    : folders = null,
      queuedMutations = null,
      error = null;

  _AccountSyncState.loaded(this.folders, this.queuedMutations) : error = null;

  _AccountSyncState.failed(this.error) : folders = null, queuedMutations = null;

  final List<FolderSyncStatus>? folders;
  final int? queuedMutations;
  final Object? error;
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  final Map<String, _AccountSyncState> _states = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final accounts = AppConfig.mailRepository.accounts;
    await Future.wait(accounts.map((account) => _loadAccount(account.id)));
  }

  Future<void> _loadAccount(String accountId) async {
    if (mounted) {
      setState(() => _states[accountId] = _AccountSyncState.loading());
    }
    try {
      final folders = await AppConfig.mailRepository.getSyncStatus(accountId);
      final queued = await AppConfig.mailRepository.queuedOfflineMutationCount(
        accountId,
      );
      if (!mounted) return;
      setState(
        () => _states[accountId] = _AccountSyncState.loaded(folders, queued),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _states[accountId] = _AccountSyncState.failed(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = AppConfig.mailRepository.accounts;
    return Scaffold(
      appBar: AppBar(title: const Text('Senkronizasyon Durumu')),
      body: accounts.isEmpty
          ? const Center(child: Text('Bağlı hesap yok.'))
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: accounts.length,
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return _AccountSyncCard(
                    key: ValueKey(account.id),
                    account: account,
                    state: _states[account.id],
                    onRetry: () => _loadAccount(account.id),
                  );
                },
              ),
            ),
    );
  }
}

class _AccountSyncCard extends StatelessWidget {
  const _AccountSyncCard({
    super.key,
    required this.account,
    required this.state,
    required this.onRetry,
  });

  final MailAccount account;
  final _AccountSyncState? state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.email, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildBody(context, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppColors colors) {
    final s = state;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (s.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            friendlyErrorMessage(s.error!),
            style: TextStyle(color: colors.destructive),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Tekrar dene'),
          ),
        ],
      );
    }
    final folders = s.folders ?? const [];
    final queued = s.queuedMutations ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (folders.isEmpty)
          Text(
            'Henüz senkronizasyon denemesi yok.',
            style: TextStyle(color: colors.secondaryText),
          )
        else
          for (final folder in folders) _FolderRow(folder: folder),
        const SizedBox(height: 8),
        Text(
          queued > 0 ? '$queued işlem bağlantı bekliyor' : 'Hepsi senkronize',
          style: TextStyle(
            color: queued > 0 ? colors.warning : colors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({required this.folder});

  final FolderSyncStatus folder;

  String _failureCategoryLabel(String? category) => switch (category) {
    'Transient' => 'Geçici sorun',
    'Authentication' => 'Kimlik doğrulama sorunu',
    'Configuration' => 'Yapılandırma sorunu',
    'Permanent' => 'Kalıcı sorun',
    _ => 'Bilinmeyen sorun',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final lastFailureAt = folder.lastFailureAt;
    final lastSuccessfulSyncAt = folder.lastSuccessfulSyncAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                folder.backfillComplete
                    ? LucideIcons.checkCircle2
                    : LucideIcons.clock,
                size: 16,
                color: folder.backfillComplete
                    ? colors.success
                    : colors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                folder.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (!folder.backfillComplete)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(
                'Geçmiş mailler hâlâ içeri aktarılıyor',
                style: TextStyle(fontSize: 12.5, color: colors.warning),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: Text(
              lastSuccessfulSyncAt != null
                  ? 'Son senkronizasyon: ${formatMailDateFull(lastSuccessfulSyncAt)}'
                  : 'Henüz başarılı senkronizasyon yok',
              style: TextStyle(fontSize: 12.5, color: colors.secondaryText),
            ),
          ),
          if (lastFailureAt != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 13,
                    color: colors.destructive,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_failureCategoryLabel(folder.lastFailureCategory)}: '
                      '${formatMailDateFull(lastFailureAt)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
