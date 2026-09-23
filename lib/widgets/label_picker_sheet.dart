import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';

/// Bottom-sheet label picker shared by the detail screen and the bulk action
/// bar, so assigning labels never forks into two implementations.
///
/// Shows every repository label with a color dot and a checkbox; toggling
/// applies or removes the label on [emailIds] immediately. The sheet listens
/// to the repository, so a label created in Settings while it is open shows up
/// here too.
Future<void> showLabelPicker(
  BuildContext context, {
  required List<String> emailIds,
}) {
  final repo = AppConfig.mailRepository;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return ListenableBuilder(
        listenable: repo,
        builder: (sheetContext, _) {
          final selectedEmails = repo.getAllEmails().where(
            (email) => emailIds.contains(email.id),
          );
          final byAccount = <String, List<String>>{};
          for (final email in selectedEmails) {
            byAccount.putIfAbsent(email.accountId, () => []).add(email.id);
          }
          final multipleAccounts = byAccount.length > 1;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      multipleAccounts
                          ? 'Etiketler hesap bazında uygulanır'
                          : 'Etiketler',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                for (final entry in byAccount.entries) ...[
                  if (multipleAccounts)
                    ListTile(
                      dense: true,
                      title: Text(
                        repo.getAccount(entry.key)?.email ?? 'Posta hesabı',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (repo.getLabelsForAccount(entry.key).isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Bu hesapta etiket yok.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.colors(sheetContext).secondaryText,
                          ),
                        ),
                      ),
                    ),
                  for (final label in repo.getLabelsForAccount(entry.key))
                    _LabelRow(
                      repo: repo,
                      accountId: entry.key,
                      labelId: label.id,
                      emailIds: entry.value,
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Whether any mail in [emailIds] carries at least one label — drives the
/// "Etiketle" / "Etiketi kaldır" overflow toggle.
bool anyLabeled(MailRepository repo, List<String> emailIds) {
  final ids = emailIds.toSet();
  return repo.getAllEmails().any(
    (email) => ids.contains(email.id) && email.labelIds.isNotEmpty,
  );
}

/// Strips every label from [emailIds]; the mails themselves are untouched.
Future<void> removeAllLabels(MailRepository repo, List<String> emailIds) {
  final ids = emailIds.toSet();
  final labelIds = {
    for (final email in repo.getAllEmails())
      if (ids.contains(email.id)) ...email.labelIds,
  };
  if (labelIds.isEmpty) return Future.value();
  return repo.removeLabelsFromEmails(emailIds, labelIds.toList());
}

class _LabelRow extends StatefulWidget {
  const _LabelRow({
    required this.repo,
    required this.labelId,
    required this.accountId,
    required this.emailIds,
  });

  final MailRepository repo;
  final String accountId;
  final String labelId;
  final List<String> emailIds;

  @override
  State<_LabelRow> createState() => _LabelRowState();
}

class _LabelRowState extends State<_LabelRow> {
  // true: every selected mail has the label. false: none do. null: mixed
  // (some do, some don't) — shown as the checkbox's indeterminate dash.
  bool? _applied = false;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_syncApplied);
    _applied = _isApplied();
  }

  @override
  void dispose() {
    widget.repo.removeListener(_syncApplied);
    super.dispose();
  }

  bool? _stateAcross(List<Email> emails) {
    if (emails.isEmpty) return false;
    final hasLabel = emails.map((e) => e.labelIds.contains(widget.labelId));
    if (hasLabel.every((applied) => applied)) return true;
    if (hasLabel.every((applied) => !applied)) return false;
    return null;
  }

  bool? _isApplied() {
    final emails = widget.repo.getAllEmails().where(
      (e) => widget.emailIds.contains(e.id),
    );
    return _stateAcross(emails.toList());
  }

  void _syncApplied() {
    if (!mounted) return;
    final applied = _isApplied();
    if (applied != _applied) setState(() => _applied = applied);
  }

  // Ignores the tapped-toward value Flutter's own tristate cycle would
  // suggest (false → true → null) — a mixed selection should resolve to
  // "apply to everyone", not "clear everyone", on the very next tap.
  void _toggle() async {
    final next = _applied != true;
    setState(() => _applied = next);
    if (next) {
      await widget.repo.addLabelsToEmails(widget.emailIds, [widget.labelId]);
    } else {
      await widget.repo.removeLabelsFromEmails(widget.emailIds, [
        widget.labelId,
      ]);
    }
  }

  MailLabel? _labelById() {
    for (final label in widget.repo.getLabelsForAccount(widget.accountId)) {
      if (label.id == widget.labelId) return label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final label = _labelById();
    if (label == null) return const SizedBox.shrink();
    return CheckboxListTile(
      dense: true,
      tristate: true,
      value: _applied,
      onChanged: (_) => _toggle(),
      secondary: CircleAvatar(backgroundColor: label.color, radius: 8),
      title: Text(label.name),
    );
  }
}
