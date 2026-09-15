import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/mail_list_item.dart';
import 'mail_detail_screen.dart';

/// Client-side search over every mail currently loaded in the repository.
///
/// No API is involved — results are the mails the mock repository already
/// holds, filtered as the user types. The future backend can replace this
/// screen's internals without touching the rest of the app.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Email> _collectAll() {
    final seen = <String>{};
    final out = <Email>[];
    for (final folder in MailFolder.values) {
      for (final email in _repo.getEmailsInFolder(folder)) {
        if (seen.add(email.id)) out.add(email);
      }
    }
    out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
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
                _controller.clear();
                setState(() => _query = '');
              },
              icon: const Icon(LucideIcons.x),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _repo,
        builder: (context, _) {
          if (_query.trim().isEmpty) {
            return const _Hint(message: 'Aramak için yazmaya başlayın.');
          }

          final results = _collectAll()
              .where((e) => e.matchesQuery(_query))
              .toList();

          if (results.isEmpty) {
            return _Hint(message: '“${_query.trim()}” için sonuç yok.');
          }

          return ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) =>
                const Divider(indent: 64, endIndent: 16),
            itemBuilder: (context, index) {
              final email = results[index];
              return MailListItem(
                key: ValueKey(email.id),
                email: email,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MailDetailScreen(emailId: email.id),
                    ),
                  );
                },
              );
            },
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