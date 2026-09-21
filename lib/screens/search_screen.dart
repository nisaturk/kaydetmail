import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_list_item.dart';
import 'mail_detail_screen.dart';

/// Client-side search over every mail currently loaded in the repository.
///
/// Always spans ALL connected accounts (the unified set), regardless of which
/// mailbox is active — a search must find the mail wherever it lives. A
/// compact label filter row sits directly under the search field, so results
/// can be scoped to one label without leaving the screen. This stays over
/// loaded mail; the full server corpus (including unloaded mail and the
/// isRead/flagged/hasAttachment filters) is reachable via
/// `ApiMailRepository.searchServer`.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _labelId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
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
                // Clearing the text keeps the selected label filter.
                _controller.clear();
                setState(() => _query = '');
              },
              icon: const Icon(LucideIcons.x),
            ),
        ],
      ),
      body: Column(
        children: [
          _LabelFilter(
            selected: _labelId,
            onSelected: (id) => setState(() => _labelId = id),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _repo,
              builder: (context, _) {
                if (_query.trim().isEmpty && _labelId == null) {
                  return const _Hint(message: 'Aramak için yazmaya başlayın.');
                }

                final results = _repo.searchEmails(
                  query: _query,
                  labelId: _labelId,
                );

                if (results.isEmpty) {
                  return _Hint(message: '“${_query.trim()}” için sonuç yok.');
                }

                final showAccount = _repo.accounts.length > 1;
                final accountEmail = showAccount
                    ? {for (final a in _repo.accounts) a.id: a.email}
                    : const <String, String>{};

                return ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: 64, endIndent: 16),
                  itemBuilder: (context, index) {
                    final email = results[index];
                    return MailListItem(
                      key: ValueKey(email.id),
                      email: email,
                      accountLabel: showAccount
                          ? accountEmail[email.accountId]
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MailDetailScreen(emailId: email.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
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
