import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../models/mail_label.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../l10n/l10n.dart';

/// Preset label colours (the picker adds custom ones on top).
const List<Color> kLabelColors = [
  Color(0xFF3E7CB1),
  Color(0xFF8E7CC3),
  Color(0xFF2E8B6E),
  Color(0xFFC77D2E),
  Color(0xFFB02A2A),
  Color(0xFFD7263D),
  Color(0xFF1B998B),
  Color(0xFF7B2CBF),
  Color(0xFFE4572E),
  Color(0xFF2D3142),
];

final List<String> kLabelColorNames = [
  l10nNow.blue,
  'Mor',
  l10nNow.green,
  l10nNow.orange,
  l10nNow.darkRed,
  l10nNow.red,
  l10nNow.turquoise,
  l10nNow.purple,
  l10nNow.redOrange,
  l10nNow.darkGray,
];

class LabelsSection extends StatefulWidget {
  const LabelsSection({super.key, required this.accountId});

  final String accountId;

  @override
  State<LabelsSection> createState() => _LabelsSectionState();
}

class _LabelsSectionState extends State<LabelsSection> {
  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    final accountId = widget.accountId;
    return Column(
      children: [
        for (final label in repo.getLabelsForAccount(accountId))
          ListTile(
            dense: true,
            leading: CircleAvatar(backgroundColor: label.color, radius: 8),
            title: Text(label.name),
            trailing: IconButton(
              tooltip: l10nNow.edit,
              icon: const Icon(LucideIcons.pencil, size: 18),
              onPressed: () =>
                  _showLabelEditor(context, accountId: accountId, label: label),
            ),
          ),
        TextButton.icon(
          onPressed: () => _showLabelEditor(context, accountId: accountId),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: Text(l10nNow.newLabel),
        ),
      ],
    );
  }

  Future<void> _showLabelEditor(
    BuildContext context, {
    required String accountId,
    MailLabel? label,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _LabelEditorDialog(accountId: accountId, label: label),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final presets = kLabelColors;
    // A colour picked earlier through the custom picker is not one of the
    // presets; keep showing (and selecting) it as its own swatch.
    final customSelected = presets.contains(selected) ? null : selected;

    Widget swatch({
      Key? key,
      required String label,
      required Color? color,
      required bool isSelected,
      required VoidCallback onTap,
      Widget? child,
      Gradient? gradient,
    }) => Semantics(
      button: true,
      label: label,
      selected: isSelected,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          key: key,
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: AppTheme.minTouchTarget,
            height: AppTheme.minTouchTarget,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  gradient: gradient,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: isSelected && child == null
                    ? const Icon(
                        LucideIcons.check,
                        size: 18,
                        color: Colors.white,
                      )
                    : child,
              ),
            ),
          ),
        ),
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, c) in presets.indexed)
          swatch(
            label: kLabelColorNames[i],
            color: c,
            isSelected: c == selected,
            onTap: () => onSelected(c),
          ),
        if (customSelected != null)
          swatch(
            key: const Key('custom-color-current'),
            label: l10nNow.customColor(colorToHex(customSelected)),
            color: customSelected,
            isSelected: true,
            onTap: () => onSelected(customSelected),
          ),
        swatch(
          key: const Key('custom-color-swatch'),
          label: l10nNow.chooseCustomColor,
          color: null,
          isSelected: false,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
          ),
          child: const Icon(LucideIcons.pipette, size: 16, color: Colors.white),
          onTap: () async {
            final picked = await showColorPickerDialog(
              context,
              initial: selected,
            );
            if (picked != null) onSelected(picked);
          },
        ),
      ],
    );
  }
}

/// Compact label editor. With [label] set it renames/recolors/deletes an
/// existing label (id preserved); without it, it creates a new one.
class _LabelEditorDialog extends StatefulWidget {
  const _LabelEditorDialog({required this.accountId, this.label});

  final String accountId;
  final MailLabel? label;

  @override
  State<_LabelEditorDialog> createState() => _LabelEditorDialogState();
}

class _LabelEditorDialogState extends State<_LabelEditorDialog> {
  late final TextEditingController _controller;
  late Color _color;
  String? _error;
  bool _submitting = false;

  bool get _isEdit => widget.label != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label?.name ?? '');
    _color = widget.label?.color ?? kLabelColors.first;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10nNow.labelNameCantBeEmpty);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = AppConfig.mailRepository;
    try {
      if (_isEdit) {
        await repo.updateLabel(id: widget.label!.id, name: name, color: _color);
      } else {
        await repo.createLabel(
          name: name,
          color: _color,
          accountId: widget.accountId,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message?.toString();
        });
      }
    } catch (error) {
      // Network/server failures must re-enable the form, not leave it stuck.
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10nNow.deleteLabel),
        content: Text(l10nNow.theLabelWillBeRemoved(widget.label!.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10nNow.cancel2),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10nNow.yesDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    try {
      await AppConfig.mailRepository.deleteLabel(widget.label!.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(_isEdit ? l10nNow.editLabel : l10nNow.newLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10nNow.name,
              errorText: _error,
              errorMaxLines: 2,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          _ColorPalette(
            selected: _color,
            onSelected: (c) => setState(() => _color = c),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10nNow.cancel2),
        ),
        if (_isEdit)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.colors(context).destructive,
            ),
            child: Text(l10nNow.delete),
          ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? l10nNow.save : l10nNow.create),
        ),
      ],
    );
  }
}
