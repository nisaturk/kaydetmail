import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/mail_list_item.dart';
import 'mail_detail_screen.dart';

/// Paginated, read-only view of one non-standard IMAP folder's mail.
///
/// Pull-to-refresh requests a server sync of this exact folder (via the
/// same job-based contract as the standard-folder pull-to-refresh) and only
/// reloads the list once that sync actually finishes — a failed/timed-out
/// sync surfaces an error instead of silently re-showing the stale page.
class CustomFolderMailScreen extends StatefulWidget {
  const CustomFolderMailScreen({
    super.key,
    required this.accountId,
    required this.folderId,
    required this.name,
  });

  final String accountId;
  final String folderId;
  final String name;

  @override
  State<CustomFolderMailScreen> createState() => _CustomFolderMailScreenState();
}

class _CustomFolderMailScreenState extends State<CustomFolderMailScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  List<Email> _emails = const [];
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _loadMoreError;
  Object? _initialError;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final emails = await _repo.getCustomFolderMails(
        accountId: widget.accountId,
        folderId: widget.folderId,
      );
      if (mounted) {
        setState(() {
          _emails = emails;
          _initialLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _initialError = error;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        _initialLoading ||
        !_repo.hasMoreCustomFolderMails(widget.accountId, widget.folderId)) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final emails = await _repo.loadMoreCustomFolderMails(
        accountId: widget.accountId,
        folderId: widget.folderId,
      );
      if (mounted) setState(() => _emails = emails);
    } catch (error) {
      if (mounted) setState(() => _loadMoreError = error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    try {
      await _repo.syncCustomFolder(
        accountId: widget.accountId,
        folderId: widget.folderId,
      );
      final emails = await _repo.getCustomFolderMails(
        accountId: widget.accountId,
        folderId: widget.folderId,
      );
      if (mounted) setState(() => _emails = emails);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 400) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_initialError != null) {
      return _ErrorState(
        message: friendlyErrorMessage(_initialError!),
        onRetry: () {
          setState(() {
            _initialLoading = true;
            _initialError = null;
          });
          _init();
        },
      );
    }
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = AppTheme.colors(context);
    if (_emails.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.mail,
                        size: 40,
                        color: colors.tertiaryText,
                      ),
                      const SizedBox(height: 12),
                      const Text('Bu klasör boş'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final showFooter = _loadingMore || _loadMoreError != null;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _emails.length + (showFooter ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
        itemBuilder: (context, index) {
          if (index == _emails.length) {
            if (_loadMoreError != null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    label: const Text('Daha fazlasını tekrar yükle'),
                  ),
                ),
              );
            }
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
          final email = _emails[index];
          return MailListItem(
            key: ValueKey(email.id),
            email: email,
            onTap: () async {
              final moved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => MailDetailScreen(
                    emailId: email.id,
                    currentCustomFolderId: widget.folderId,
                  ),
                ),
              );
              if (moved == true && mounted) {
                setState(() {
                  _emails = _emails
                      .where((mail) => mail.id != email.id)
                      .toList();
                });
              }
            },
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 40, color: colors.warning),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}
