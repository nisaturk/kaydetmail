import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/mail_list_item.dart';
import 'compose_screen.dart';
import 'mail_detail_screen.dart';

/// Debounced server-side search across every connected account.
///
/// Text queries use the backend corpus, including mail not yet paginated into
/// the inbox. Label-only filtering remains local because labels are client
/// state and do not exist on the server.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _labelId;
  List<Email> _results = const [];
  bool _loading = false;
  Object? _error;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value;
      _error = null;
      if (query.isEmpty) {
        _loading = false;
        _results = _labelId == null
            ? const []
            : _repo.searchEmails(labelId: _labelId);
      } else {
        _loading = true;
        _results = const [];
      }
    });
    if (query.isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(query, generation),
    );
  }

  Future<void> _search(String query, int generation) async {
    try {
      final results = await _repo.searchEmailsOnServer(query: query);
      if (!mounted || generation != _searchGeneration) return;
      final byId = {for (final email in results) email.id: email};
      final sorted = byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _results = List.unmodifiable(sorted);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _selectLabel(String? id) {
    setState(() {
      _labelId = id;
      if (_query.trim().isEmpty) {
        _results = id == null ? const [] : _repo.searchEmails(labelId: id);
      }
    });
  }

  List<Email> get _visibleResults => _labelId == null
      ? _results
      : _results
            .where((email) => email.labelIds.contains(_labelId))
            .toList(growable: false);

  void _retry() {
    final query = _query.trim();
    if (query.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    _search(query, generation);
  }

  @override
  Widget build(BuildContext context) {
    final results = _visibleResults;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _queryChanged,
          decoration: const InputDecoration(
            hintText: 'E-posta ara',
            border: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(color: AppTheme.tertiaryText, fontSize: 16),
          ),
          style: const TextStyle(fontSize: 16, color: Colors.black),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              onPressed: () {
                _controller.clear();
                _queryChanged('');
              },
              icon: const Icon(LucideIcons.x),
            ),
        ],
      ),
      body: Column(
        children: [
          _LabelFilter(selected: _labelId, onSelected: _selectLabel),
          _SearchScopeStatus(
            serverSearch: _query.trim().isNotEmpty,
            loading: _loading,
          ),
          Expanded(child: _buildResults(results)),
        ],
      ),
    );
  }

  void _onMailTap(Email email) {
    if (email.folder == MailFolder.drafts) {
      // Drafts open in the editor with every field populated; ordinary
      // messages keep opening the read-only detail view.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComposeScreen(
            composeTitle: 'Taslağı Düzenle',
            editingDraftId: email.id,
            initialFrom: _repo.getAccount(email.accountId)?.email,
            initialTo: email.recipients.join(', '),
            initialCc: email.cc.join(', '),
            initialBcc: email.bcc.join(', '),
            initialSubject: email.subject,
            initialBody: email.bodyText,
            initialAttachments: email.attachments,
            initialThreadId: email.threadId.isEmpty ? null : email.threadId,
            inReplyToId: email.inReplyToId,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: email.id)),
      );
    }
  }

  Widget _buildResults(List<Email> results) {
    if (_loading && results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && results.isEmpty) {
      return _SearchError(error: _error!, onRetry: _retry);
    }
    if (_query.trim().isEmpty && _labelId == null) {
      return const _Hint(message: 'Aramak için yazmaya başlayın.');
    }
    if (results.isEmpty) {
      return _Hint(message: '“${_query.trim()}” için sonuç yok.');
    }
    final showAccount = _repo.accounts.length > 1;
    final accountEmail = showAccount
        ? {for (final account in _repo.accounts) account.id: account.email}
        : const <String, String>{};
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
      itemBuilder: (context, index) {
        final email = results[index];
        final labelsById = {
          for (final label in _repo.getLabelsForAccount(email.accountId))
            label.id: label,
        };
        return MailListItem(
          key: ValueKey(email.id),
          email: email,
          accountLabel: showAccount ? accountEmail[email.accountId] : null,
          folderLabel: email.folder.label,
          labels: [
            for (final id in email.labelIds)
              if (labelsById[id] != null) labelsById[id]!,
          ],
          onTap: () => _onMailTap(email),
        );
      },
    );
  }
}

class _SearchScopeStatus extends StatelessWidget {
  const _SearchScopeStatus({required this.serverSearch, required this.loading});

  final bool serverSearch;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              serverSearch
                  ? 'Tüm hesaplarda sunucuda aranıyor'
                  : 'Etiketler bu cihazdaki e-postalarda filtrelenir',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            friendlyErrorMessage(error),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 8),
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

/// Compact, horizontally scrollable label filter: `Tümü` (no filter) plus one
/// chip per repository label. Always visible so the active filter is obvious.
class _LabelFilter extends StatelessWidget {
  const _LabelFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    return SizedBox(
      height: 48,
      child: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ChoiceChip(
                  label: const Text('Tümü'),
                  selected: selected == null,
                  onSelected: (_) => onSelected(null),
                ),
              ),
              for (final label in repo.getLabels())
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text(label.name),
                    selected: selected == label.id,
                    selectedColor: label.color,
                    labelStyle: selected == label.id
                        ? const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                    onSelected: (_) => onSelected(label.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: const TextStyle(fontSize: 14, color: AppTheme.secondaryText),
      ),
    );
  }
}
