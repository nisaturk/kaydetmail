import 'dart:async';

import 'compose_models.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../../models/email.dart';
import '../../models/mail_template.dart';
import '../../repositories/mail_repository.dart';
import '../../services/contacts_store.dart';
import '../../state/pending_send_queue.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/mail_avatar.dart';
import '../../l10n/l10n.dart';

class TemplatePicker extends StatefulWidget {
  const TemplatePicker({
    super.key,
    required this.accountId,
    required this.repository,
  });

  final String accountId;
  final MailRepository repository;

  @override
  State<TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<TemplatePicker> {
  List<MailTemplate>? _templates;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _templates = null;
      _error = null;
    });
    try {
      final templates = await widget.repository.listTemplates(widget.accountId);
      if (mounted) setState(() => _templates = templates);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10nNow.chooseASavedTextOr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10nNow.close,
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: _error != null
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
                          child: Text(l10nNow.tryAgain),
                        ),
                      ],
                    ),
                  )
                : _templates == null
                ? const Center(child: CircularProgressIndicator())
                : _templates!.isEmpty
                ? Center(
                    child: Text(
                      l10nNow.noSavedTextsForThis,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: _templates!.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final template = _templates![index];
                      return ListTile(
                        key: ValueKey('pick-template-${template.id}'),
                        title: Text(template.name),
                        subtitle: template.subject.isEmpty
                            ? null
                            : Text(template.subject, maxLines: 1),
                        onTap: () => Navigator.pop(context, template),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

/// A single recipient chip. [recipient.valid] false renders it in the
/// destructive palette instead of silently dropping or silently sending a
/// broken address — the user has to see and fix it.

class RecipientChip extends StatelessWidget {
  const RecipientChip({
    super.key,
    required this.recipient,
    required this.onDeleted,
    this.enabled = true,
  });

  final Recipient recipient;
  final VoidCallback onDeleted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final destructive = !recipient.valid;
    return Chip(
      label: Text(recipient.address, style: const TextStyle(fontSize: 13)),
      backgroundColor: destructive
          ? colors.destructive.withValues(alpha: 0.12)
          : colors.surfaceAlt,
      labelStyle: TextStyle(
        color: destructive ? colors.destructive : colors.bodyText,
      ),
      deleteIcon: Icon(
        LucideIcons.x,
        size: 14,
        color: destructive ? colors.destructive : colors.secondaryText,
      ),
      onDeleted: enabled ? onDeleted : null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      side: BorderSide(color: destructive ? colors.destructive : colors.border),
    );
  }
}

class AttachmentRow extends StatelessWidget {
  const AttachmentRow({
    super.key,
    required this.attachment,
    required this.onRemove,
    this.onRetry,
    this.enabled = true,
    this.issue,
    this.error,
  });

  final Attachment attachment;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;
  final bool enabled;

  /// Null means ready (bytes in hand); non-null gates Send/save-draft/
  /// schedule until it's resolved — see `_ComposeScreenState._attachmentIssues`.
  final AttachmentIssue? issue;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final downloading = issue == AttachmentIssue.downloading;
    final failed = issue == AttachmentIssue.failed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(
              failed ? LucideIcons.fileWarning : LucideIcons.paperclip,
              size: 16,
              color: failed ? colors.destructive : colors.secondaryText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.bodyText),
                  ),
                  if (failed)
                    Text(
                      error ?? l10nNow.theAttachmentCouldntBeDownloaded2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: colors.destructive),
                    )
                  else if (downloading)
                    Text(
                      l10nNow.downloading,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!failed)
              Text(
                attachment.sizeLabel,
                style: TextStyle(fontSize: 12, color: colors.secondaryText),
              ),
            if (failed)
              IconButton(
                onPressed: enabled ? onRetry : null,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                tooltip: l10nNow.downloadAgain,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            IconButton(
              onPressed: enabled ? onRemove : null,
              icon: const Icon(LucideIcons.x, size: 16),
              tooltip: l10nNow.remove,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live "N sn içinde gönderilecek" countdown shown inside the undo-send
/// SnackBar. Purely cosmetic — the actual send fires from
/// [PendingSendQueue]'s own timer, and the SnackBar itself is dismissed by
/// the controller `_ComposeScreenState._send` captured from `showSnackBar`,
/// both on [PendingSendQueue.undoWindow]; this only mirrors it visually.
class UndoSendSnackContent extends StatefulWidget {
  const UndoSendSnackContent({super.key, required this.duration});

  final Duration duration;

  @override
  State<UndoSendSnackContent> createState() => _UndoSendSnackContentState();
}

class _UndoSendSnackContentState extends State<UndoSendSnackContent> {
  late int _secondsLeft = widget.duration.inSeconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        _ticker?.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(l10nNow.theEmailWillBeSent(_secondsLeft));
  }
}

/// Tappable contact suggestion dropdown, anchored under a recipient field
/// via [CompositedTransformFollower]/[CompositedTransformTarget] (see
/// `_ComposeScreenState._updateSuggestions`).
class ContactSuggestionList extends StatelessWidget {
  const ContactSuggestionList({
    super.key,
    required this.contacts,
    required this.onSelected,
  });

  final List<Contact> contacts;
  final void Function(Contact) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          children: [
            for (final contact in contacts)
              ListTile(
                key: ValueKey('contact-suggestion-${contact.email}'),
                dense: true,
                title: Text(
                  contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: contact.displayName == contact.email
                    ? null
                    : Text(
                        contact.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.secondaryText),
                      ),
                onTap: () => onSelected(contact),
              ),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a URL to insert as a link. A [StatefulWidget] (not a bare
/// controller disposed right after the dialog closes) so the framework
/// disposes [_controller] only once the widget is truly unmounted — the
/// dialog's own exit transition keeps it mounted for a few more frames
/// after `Navigator.pop`, and disposing any earlier crashes that
/// animation (same convention as `_LabelEditorDialogState`).
class LinkUrlDialog extends StatefulWidget {
  const LinkUrlDialog({super.key});

  @override
  State<LinkUrlDialog> createState() => _LinkUrlDialogState();
}

class _LinkUrlDialogState extends State<LinkUrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10nNow.insertLink),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'https://ornek.com'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10nNow.cancel2),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10nNow.add),
        ),
      ],
    );
  }
}

/// Quoted images stay in the document (and in the sent HTML) but are shown
/// as a chip: rendering them would fetch remote content the reader blocks
/// by default, and the editor has no image editing anyway.
class EmbedPlaceholder extends quill.EmbedBuilder {
  const EmbedPlaceholder();

  @override
  String get key => 'unknown';

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final colors = AppTheme.colors(context);
    final isImage = embedContext.node.value.type == quill.BlockEmbed.imageType;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isImage ? LucideIcons.image : LucideIcons.package,
            size: 16,
            color: colors.secondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            isImage ? l10nNow.image : l10nNow.embeddedContent,
            style: TextStyle(fontSize: 13, color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

/// Address book picker behind "Kişilerden ekle": searchable multi-select
/// over [contacts] with the target field (Kime/Cc/Bcc) chosen up top.
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet({super.key, required this.contacts});

  final List<Contact> contacts;

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  final _query = TextEditingController();
  var _field = RecipientField.to;

  /// Picked contacts keyed by lowercased address, in pick order.
  final _picked = <String, Contact>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Contact> get _visible => _query.text.trim().isEmpty
      ? widget.contacts
      : ContactsStore.search(widget.contacts, _query.text);

  void _toggle(Contact contact) {
    final key = contact.email.toLowerCase();
    setState(() {
      if (_picked.remove(key) == null) _picked[key] = contact;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final media = MediaQuery.of(context);
    final visible = _visible;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space5,
                AppTheme.space4,
                AppTheme.space5,
                AppTheme.space2,
              ),
              child: Text(l10nNow.addFromContacts, style: AppTheme.titleText),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
              child: SegmentedButton<RecipientField>(
                key: const Key('contact-picker-field'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: RecipientField.to,
                    label: Text(l10nNow.to),
                  ),
                  ButtonSegment(value: RecipientField.cc, label: Text('Cc')),
                  ButtonSegment(value: RecipientField.bcc, label: Text('Bcc')),
                ],
                selected: {_field},
                onSelectionChanged: (value) =>
                    setState(() => _field = value.single),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space5,
                AppTheme.space3,
                AppTheme.space5,
                AppTheme.space2,
              ),
              child: TextField(
                key: const Key('contact-picker-search'),
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10nNow.searchNameOrEmail,
                  prefixIcon: Icon(LucideIcons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppTheme.space6),
                      child: Text(
                        widget.contacts.isEmpty
                            ? l10nNow.noSavedContactsYet
                            : l10nNow.noMatchingContactsFound,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.secondaryText),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final contact = visible[index];
                        final selected = _picked.containsKey(
                          contact.email.toLowerCase(),
                        );
                        final hasName = contact.displayName != contact.email;
                        return ListTile(
                          key: ValueKey('contact-pick-${contact.email}'),
                          leading: MailAvatar(
                            identity: contact.email,
                            displayName: contact.displayName,
                            size: 36,
                            selected: selected,
                          ),
                          title: Text(
                            contact.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: hasName
                              ? Text(
                                  contact.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: colors.secondaryText),
                                )
                              : null,
                          trailing: Checkbox(
                            value: selected,
                            onChanged: (_) => _toggle(contact),
                          ),
                          onTap: () => _toggle(contact),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space5,
                  AppTheme.space2,
                  AppTheme.space5,
                  AppTheme.space4,
                ),
                child: FilledButton(
                  key: const Key('contact-picker-add'),
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.of(context).pop<ContactPick>((
                          field: _field,
                          contacts: _picked.values.toList(),
                        )),
                  child: Text(
                    _picked.isEmpty
                        ? l10nNow.add
                        : l10nNow.add2(_picked.length),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
