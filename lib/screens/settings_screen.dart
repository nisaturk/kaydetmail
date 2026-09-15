import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../state/app_settings_controller.dart';
import '../theme/app_theme.dart';

/// Settings screen: label management, notifications and synchronization.
///
/// Labels are created through the repository so they appear everywhere
/// immediately. Notifications and sync values live in
/// [AppSettingsController] — simulated, no backend involved.
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
        listenable: Listenable.merge(
          [AppSettingsController.instance, AppConfig.mailRepository],
        ),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const _SectionHeader('Etiketler'),
              _LabelsSection(),
              const _SectionHeader('Bildirimler'),
              _NotificationsSection(),
              const _SectionHeader('Senkronizasyon'),
              _SyncSection(),
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
          ),
        TextButton.icon(
          onPressed: () => _showNewLabelDialog(context),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: const Text('Yeni Etiket'),
        ),
      ],
    );
  }

  Future<void> _showNewLabelDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _NewLabelDialog(),
    );
  }
}

class _NewLabelDialog extends StatefulWidget {
  const _NewLabelDialog();

  @override
  State<_NewLabelDialog> createState() => _NewLabelDialogState();
}

class _NewLabelDialogState extends State<_NewLabelDialog> {
  final _controller = TextEditingController();
  var _color = SettingsScreen.labelColors.first;
  var _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_submitting) return;
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _submitting = true);
    await AppConfig.mailRepository.createLabel(name: name, color: _color);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Etiket'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Ad'),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in SettingsScreen.labelColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == _color ? Colors.black : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: c == _color
                        ? const Icon(LucideIcons.check,
                            size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _create,
          child: const Text('Oluştur'),
        ),
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