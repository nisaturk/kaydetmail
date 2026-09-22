import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_label.dart';
import '../repositories/mail_repository.dart';

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
          final labels = repo.getLabels();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Etiketler',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (labels.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Henüz etiket yok. Ayarlar’dan ekleyebilirsiniz.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                for (final label in labels)
                  _LabelRow(repo: repo, labelId: label.id, emailIds: emailIds),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

class _LabelRow extends StatefulWidget {
  const _LabelRow({
    required this.repo,
    required this.labelId,
    required this.emailIds,
  });

  final MailRepository repo;
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
    for (final label in widget.repo.getLabels()) {
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
