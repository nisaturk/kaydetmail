import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/reply_reminder.dart';
import '../repositories/mail_repository.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';

class ReplyRemindersScreen extends StatefulWidget {
  const ReplyRemindersScreen({super.key});

  @override
  State<ReplyRemindersScreen> createState() => _ReplyRemindersScreenState();
}

class _ReplyRemindersScreenState extends State<ReplyRemindersScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _repo.addListener(_onRepo);
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepo);
    super.dispose();
  }

  void _onRepo() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.refreshReplyReminders();
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = friendlyErrorMessage(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _cancel(ReplyReminder reminder) async {
    try {
      await _repo.cancelReplyReminder(reminder.mailId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = _repo.getReplyReminders();
    return Scaffold(
      appBar: AppBar(title: const Text('Yanıt Takibi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            )
          : reminders.isEmpty
          ? const Center(
              child: Text(
                'Takip edilen e-posta yok.\nGönderilen bir e-postanın menüsünden takip kurun.',
                textAlign: TextAlign.center,
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: reminders.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final reminder = reminders[index];
                  final overdue = reminder.dueAtUtc.isBefore(DateTime.now());
                  return ListTile(
                    key: ValueKey('reminder-${reminder.id}'),
                    leading: Icon(
                      overdue ? LucideIcons.bellRing : LucideIcons.bell,
                    ),
                    title: Text(
                      reminder.subject.isEmpty
                          ? '(Konu yok)'
                          : reminder.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${reminder.recipient} • ${formatMailDateFull(reminder.dueAtUtc.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Takibi kaldır',
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => _cancel(reminder),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
