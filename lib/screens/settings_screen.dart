import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_label.dart';
import '../state/app_settings_controller.dart';
import '../theme/app_theme.dart';

/// Settings screen: labels, server address, notifications, sync and gestures.
///
/// Labels are created, renamed, recolored and deleted through the repository
/// so they appear everywhere immediately. The server address is the future
/// HTTP API's base URL — validated, normalized and persisted. Notifications,
/// sync and swipe-to-delete live in [AppSettingsController] — simulated, no
/// backend involved.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<Color> labelColors = [
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          AppSettingsController.instance,
          AppConfig.mailRepository,
        ]),
        builder: (context, _) {
          // Section widgets must NOT be const: the list needs fresh widget
          // instances every build, otherwise SliverChildListDelegate.update()
          // sees identical const instances and keeps stale children (a changed
          // server address or swipe toggle would never repaint).
          return ListView(
            key: const Key('settings-list'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const _SectionHeader('Etiketler'),
              _LabelsSection(),
              const _SectionHeader('Sunucu'),
              _ServerSection(),
              const _SectionHeader('Bildirimler'),
              _NotificationsSection(),
              const _SectionHeader('Senkronizasyon'),
              _SyncSection(),
              const _SectionHeader('Kaydırma'),
              _SwipeSection(),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.secondaryText,
        ),
      ),
    );
  }
}

class _LabelsSection extends StatelessWidget {
  const _LabelsSection();

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    return Column(
      children: [
        for (final label in repo.getLabels())
          ListTile(
            dense: true,
            leading: CircleAvatar(backgroundColor: label.color, radius: 8),
            title: Text(label.name),
            trailing: IconButton(
              tooltip: 'Düzenle',
              icon: const Icon(LucideIcons.pencil, size: 18),
              onPressed: () => _showLabelEditor(context, label: label),
            ),
          ),
        TextButton.icon(
          onPressed: () => _showLabelEditor(context),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: const Text('Yeni Etiket'),
        ),
      ],
    );
  }

  Future<void> _showLabelEditor(BuildContext context, {MailLabel? label}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _LabelEditorDialog(label: label),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in SettingsScreen.labelColors)
          GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == selected ? Colors.black : Colors.transparent,
                  width: 2,
                ),
              ),
              child: c == selected
                  ? const Icon(LucideIcons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Compact label editor. With [label] set it renames/recolors/deletes an
/// existing label (id preserved); without it, it creates a new one.
class _LabelEditorDialog extends StatefulWidget {
  const _LabelEditorDialog({this.label});

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
    _color = widget.label?.color ?? SettingsScreen.labelColors.first;
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
      setState(() => _error = 'Etiket adı boş olamaz.');
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
        await repo.createLabel(name: name, color: _color);
      }
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_submitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Etiketi sil?'),
        content: Text(
          '“${widget.label!.name}” etiketi kaldırılacak. '
          'E-postalar silinmez, yalnızca bu etiket onlardan çıkarılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    await AppConfig.mailRepository.deleteLabel(widget.label!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Etiketi Düzenle' : 'Yeni Etiket'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Ad',
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
          child: const Text('Vazgeç'),
        ),
        if (_isEdit)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB3261E),
            ),
            child: const Text('Sil'),
          ),
        FilledButton(
          onPressed: _save,
          child: Text(_isEdit ? 'Kaydet' : 'Oluştur'),
        ),
      ],
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return ListTile(
      dense: true,
      leading: const Icon(
        LucideIcons.server,
        size: 20,
        color: AppTheme.secondaryText,
      ),
      title: const Text('Sunucu adresi'),
      subtitle: Text(
        settings.serverBaseUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _showServerDialog(context),
    );
  }

  Future<void> _showServerDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _ServerDialog(),
    );
  }
}

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: AppSettingsController.instance.serverBaseUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppSettingsController.instance.setServerAddress(_controller.text);
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sunucu adresi'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Adres',
          hintText: 'http://192.168.1.100:8080',
          errorText: _error,
          errorMaxLines: 2,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      dense: true,
      title: const Text('Bildirimler'),
      subtitle: const Text('Simülasyon — gerçek bildirim henüz yok.'),
      value: settings.notificationsEnabled,
      activeThumbColor: Colors.black,
      onChanged: (v) => settings.notificationsEnabled = v,
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      children: [
        for (final interval in SyncInterval.values)
          ListTile(
            dense: true,
            title: Text(interval.label),
            trailing: interval == settings.syncInterval
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.syncInterval = interval,
          ),
      ],
    );
  }
}

class _SwipeSection extends StatelessWidget {
  const _SwipeSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      dense: true,
      title: const Text('Kaydırarak sil'),
      subtitle: const Text(
        'Listede sola kaydırınca e-postayı çöp kutusuna taşır.',
      ),
      value: settings.swipeDeleteEnabled,
      activeThumbColor: Colors.black,
      onChanged: (v) => settings.swipeDeleteEnabled = v,
    );
  }
}
