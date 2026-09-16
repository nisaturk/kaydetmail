import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_list_item.dart';
import 'mail_detail_screen.dart';

/// Mail list for a single folder with infinite scrolling.
///
/// Loading, empty, error and retry states are handled explicitly, even though
/// the mock data source succeeds almost always — the same code will drive the
/// real API later. Selection mode is entered by tapping a mail avatar.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.folder, required this.selection});

  final MailFolder folder;
  final MailSelectionController selection;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final ScrollController _scrollController = ScrollController();
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      if (_repo.getEmailsInFolder(widget.folder).isEmpty) {
        await _repo.loadMoreEmails(widget.folder);
      }
      if (mounted) setState(() => _initialLoading = false);
      _fillIfShort();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _initialLoading) return;
    setState(() => _loadingMore = true);
    try {
      await _repo.loadMoreEmails(widget.folder);
    } catch (_) {
      // Keep the current list; the next scroll will retry.
    }
    if (mounted) setState(() => _loadingMore = false);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      _loadMore();
    }
  }

  /// Fills very short lists (e.g. when the viewport is taller than the
  /// content) so infinite scroll still kicks in.
  void _fillIfShort() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.maxScrollExtent == 0) {
        _loadMore();
      }
    });
  }

  void _onMailTap(Email email) {
    if (widget.selection.isActive) {
      widget.selection.toggle(email.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: email.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final emails = _repo.getEmailsInFolder(widget.folder);
        widget.selection.syncVisibleIds(emails.map((e) => e.id).toList());

        if (_error != null) {
          return _ErrorState(onRetry: _init);
        }
        if (_initialLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (emails.isEmpty) {
          return _EmptyState(folder: widget.folder);
        }

        // In the unified mailbox each row names its originating account;
        // account-specific lists stay clean.
        final showAccount =
            _repo.activeAccountId == null && _repo.accounts.length > 1;
        final accountEmail = showAccount
            ? {for (final a in _repo.accounts) a.id: a.email}
            : const <String, String>{};

        final itemCount = emails.length + (_loadingMore ? 1 : 0);
        return ListView.separated(
          key: PageStorageKey(widget.folder),
          controller: _scrollController,
          itemCount: itemCount,
          separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
          itemBuilder: (context, index) {
            if (index == emails.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              );
            }
            final email = emails[index];
            return MailListItem(
              key: ValueKey(email.id),
              email: email,
              selected:
                  widget.selection.isActive &&
                  widget.selection.selectedIds.contains(email.id),
              accountLabel: showAccount ? accountEmail[email.accountId] : null,
              onTap: () => _onMailTap(email),
              onAvatarTap: () => widget.selection.toggle(email.id),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.folder});

  final MailFolder folder;

  String get _subtitle => switch (folder) {
    MailFolder.inbox => 'Yeni e-postalar geldiğinde burada görünür.',
    MailFolder.sent => 'Gönderdiğiniz e-postalar burada görünür.',
    MailFolder.pinned => 'Yıldızladığınız e-postalar burada görünür.',
    MailFolder.drafts => 'Kaydettiğiniz taslaklar burada durur.',
    MailFolder.trash => 'Sildiğiniz e-postalar burada durur.',
    MailFolder.spam => 'İstenmeyen e-postalar buraya düşer.',
    MailFolder.archive => 'Arşivlediğiniz e-postalar burada durur.',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(folder.icon, size: 40, color: AppTheme.tertiaryText),
          const SizedBox(height: 12),
          Text(
            '${folder.label} boş',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.alertOctagon,
            size: 40,
            color: AppTheme.secondaryText,
          ),
          const SizedBox(height: 12),
          const Text(
            'E-postalarınız yüklenemedi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}
