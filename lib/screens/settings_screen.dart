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
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge(
          [AppSettingsController.instance, AppConfig.mailRepository],
        ),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: const [
              _SectionHeader('Labels'),
              _LabelsSection(),
              _SectionHeader('Notifications'),
              _NotificationsSection(),
              _SectionHeader('Synchronization'),
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
          label: const Text('New label'),
        ),
      ],
    );
  }

  Future<void> _showNewLabelDialog(BuildContext context) async {
    final controller = TextEditingController();
    var color = SettingsScreen.labelColors.first;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Name'),
                onSubmitted: (_) {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  _createAndClose(ctx, name, color);
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in SettingsScreen.labelColors)
                    GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == color ? Colors.black : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: c == color
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                _createAndClose(ctx, name, color);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
  }

  Future<void> _createAndClose(
      BuildContext ctx, String name, Color color) async {
    await AppConfig.mailRepository.createLabel(name: name, color: color);
    if (ctx.mounted) Navigator.of(ctx).pop();
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      dense: true,
      title: const Text('Notifications'),
      subtitle: const Text('Simulated — no real notifications yet.'),
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