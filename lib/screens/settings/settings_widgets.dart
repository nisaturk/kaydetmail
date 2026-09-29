import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../state/app_settings_controller.dart';
import '../../theme/app_theme.dart';

/// One row of the settings index. Either pushes [page] (section widgets shown
/// on a titled sub-page) or runs a custom [onTap].
class SettingsCategoryTile extends StatelessWidget {
  const SettingsCategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.page,
    this.grouped = true,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> Function(BuildContext)? page;
  final bool grouped;
  final void Function(BuildContext)? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        size: 22,
        color: AppTheme.colors(context).secondaryText,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
      onTap: () {
        if (onTap != null) return onTap!(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SettingsPage(
              title: title,
              icon: icon,
              sections: page!,
              grouped: grouped,
            ),
          ),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.icon,
    required this.sections,
    required this.grouped,
  });

  final String title;
  final IconData icon;
  final List<Widget> Function(BuildContext) sections;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          AppSettingsController.instance,
          AppConfig.mailRepository,
        ]),
        // Section widgets must NOT be const: fresh instances every build, or
        // the list keeps stale children (a changed toggle would not repaint).
        builder: (context, _) {
          final content = Column(children: sections(context));
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (grouped)
                SettingsGroup(title: title, icon: icon, child: content)
              else
                content,
            ],
          );
        },
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: colors.secondaryText),
                const SizedBox(width: 8),
                Text(title, style: AppTheme.titleText),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

/// Small caption above a group of settings rows.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.colors(context).secondaryText,
      ),
    ),
  );
}
