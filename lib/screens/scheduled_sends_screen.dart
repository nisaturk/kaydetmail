import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/scheduled_send.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

/// Lists every mail queued via Compose's "Zamanla" (send later): pending
/// ones can be cancelled here, past ones show their outcome. The backend
/// owns the actual send — this screen only reads/cancels
/// `GET`/`DELETE /api/scheduled-sends`.
class ScheduledSendsScreen extends StatefulWidget {
  const ScheduledSendsScreen({super.key});

  @override
  State<ScheduledSendsScreen> createState() => _ScheduledSendsScreenState();
}

class _ScheduledSendsScreenState extends State<ScheduledSendsScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.refreshScheduledSends();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(ScheduledSend item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zamanlanmış gönderimi iptal et'),
        content: Text(
          '"${item.subject.isEmpty ? '(konu yok)' : item.subject}" gönderimi '
          'iptal edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.cancelScheduledSend(item.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gönderim iptal edildi.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zamanlanmış Gönderimler')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListenableBuilder(
          listenable: _repo,
          builder: (context, _) {
            if (_loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return _ErrorState(error: _error!, onRetry: _load);
            }
            final items = _repo.getScheduledSends();
            if (items.isEmpty) {
              return _EmptyState(onRetry: _load);
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _ScheduledRow(
                item: items[i],
                onCancel: items[i].status == ScheduledSendStatus.pending
                    ? () => _cancel(items[i])
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScheduledRow extends StatelessWidget {
  const _ScheduledRow({required this.item, required this.onCancel});

  final ScheduledSend item;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final status = switch (item.status) {
      ScheduledSendStatus.pending => (
        label: 'Zamanlandı',
        color: Theme.of(context).colorScheme.primary,
        icon: LucideIcons.clock,
      ),
      ScheduledSendStatus.sent => (
        label: 'Gönderildi',
        color: colors.secondaryText,
        icon: LucideIcons.check,
      ),
      ScheduledSendStatus.cancelled => (
        label: 'İptal edildi',
        color: colors.secondaryText,
        icon: LucideIcons.x,
      ),
      ScheduledSendStatus.failed => (
        label: item.failureReason ?? 'Gönderilemedi',
        color: colors.destructive,
        icon: LucideIcons.triangleAlert,
      ),
    };
    return ListTile(
      leading: Icon(status.icon, color: status.color, size: 22),
      title: Text(
        item.subject.isEmpty ? '(konu yok)' : item.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${item.to.join(', ')}\n${status.label} · ${_formatDateTime(item.sendAt)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: onCancel == null
          ? null
          : IconButton(
              tooltip: 'İptal Et',
              icon: const Icon(LucideIcons.x, size: 20),
              onPressed: onCancel,
            ),
    );
  }
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}.${two(dt.month)}.${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.calendarClock,
                      size: 48,
                      color: colors.secondaryText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Zamanlanmış gönderim yok',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yazarken "Gönder" yanındaki oktan bir gönderim '
                      'zamanlayınca burada görünür.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      friendlyErrorMessage(error),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.secondaryText),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(LucideIcons.refreshCw, size: 18),
                      label: const Text('Yenile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
