import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/device_contacts.dart';
import '../../state/app_settings_controller.dart';
import '../../l10n/l10n.dart';

/// Manually-added contacts — people the user wants suggested in compose
/// before ever exchanging mail with them. Synced through the backend (see
/// `MailRepository.addManualContact`); distinct from the automatic
/// mail-participant suggestions in `ContactsStore`.
class DeviceContactsSection extends StatefulWidget {
  const DeviceContactsSection({super.key});

  @override
  State<DeviceContactsSection> createState() => _DeviceContactsSectionState();
}

class _DeviceContactsSectionState extends State<DeviceContactsSection> {
  bool _busy = false;

  Future<void> _toggle(bool enable) async {
    final settings = AppSettingsController.instance;
    if (!enable) {
      settings.deviceContactsEnabled = false;
      DeviceContacts.clear();
      return;
    }
    setState(() => _busy = true);
    final granted = await const PlatformDeviceContacts().requestAccess();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10nNow.contactsPermissionWasntGrantedSuggestions),
        ),
      );
      return;
    }
    settings.deviceContactsEnabled = true;
    unawaited(DeviceContacts.refresh(enabled: true));
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const Key('device-contacts-toggle'),
    dense: true,
    title: Text(l10nNow.suggestDeviceContacts),
    subtitle: Text(l10nNow.alsoSuggestsEmailAddressesFrom),
    value: AppSettingsController.instance.deviceContactsEnabled,
    onChanged: _busy ? null : _toggle,
  );
}

class NotificationsSection extends StatelessWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: Text(l10nNow.notifications),
          subtitle: Text(l10nNow.showNewEmailNotificationsOn),
          value: settings.notificationsEnabled,
          onChanged: (v) => settings.notificationsEnabled = v,
        ),
      ],
    );
  }
}

/// System/light/dark theme picker. The palette itself never changes
/// (grayscale by design per the client's brand guidelines) — only which end
/// of it is the background.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  static final _options = [
    (ThemeMode.system, 'Sistem', l10nNow.followsTheDeviceTheme),
    (ThemeMode.light, l10nNow.light, null),
    (ThemeMode.dark, l10nNow.dark, null),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      children: [
        for (final (mode, label, subtitle) in _options)
          ListTile(
            dense: true,
            title: Text(label),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: mode == settings.themeMode
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.themeMode = mode,
          ),
      ],
    );
  }
}

/// Turkish/English picker; Turkish stays the default.
class LanguageSection extends StatelessWidget {
  const LanguageSection({super.key});

  static const _options = [(Locale('tr'), 'Türkçe'), (Locale('en'), 'English')];

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      children: [
        for (final (locale, label) in _options)
          ListTile(
            key: Key('language-${locale.languageCode}'),
            dense: true,
            title: Text(label),
            trailing: locale == settings.locale
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () {
              settings.locale = locale;
              // The page's own title was built in the previous language, so
              // go back to the list, which is rebuilt in the new one.
              Navigator.of(context).maybePop();
            },
          ),
      ],
    );
  }
}

class SwipeSection extends StatelessWidget {
  const SwipeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          dense: true,
          title: Text(l10nNow.swipeGestures),
          subtitle: Text(l10nNow.swipeAnEmailRightOr),
          value: settings.swipeDeleteEnabled,
          onChanged: (v) => settings.swipeDeleteEnabled = v,
        ),
        if (settings.swipeDeleteEnabled) ...[
          _SwipeGestureTile(
            key: const Key('swipe-right-setting'),
            title: l10nNow.onSwipeRight,
            value: settings.swipeRight,
            onChanged: (v) => settings.swipeRight = v,
            values: SwipeGesture.values,
            label: (v) => v.label,
          ),
          _SwipeGestureTile(
            key: const Key('swipe-left-setting'),
            title: l10nNow.onSwipeLeft,
            value: settings.swipeLeft,
            onChanged: (v) => settings.swipeLeft = v,
            values: SwipeGesture.values,
            label: (v) => v.label,
          ),
          _SwipeGestureTile<SwipeSensitivity>(
            key: const Key('swipe-sensitivity-setting'),
            title: l10nNow.swipeSensitivity,
            value: settings.swipeSensitivity,
            values: SwipeSensitivity.values,
            label: (v) => v.label,
            onChanged: (v) => settings.swipeSensitivity = v,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(l10nNow.swipeSensitivityHelp),
          ),
        ],
      ],
    );
  }
}

class _SwipeGestureTile<T> extends StatelessWidget {
  const _SwipeGestureTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.values,
    required this.label,
  });

  final String title;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButton<T>(
      value: value,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      items: [
        for (final gesture in values)
          DropdownMenuItem(
            value: gesture,
            child: Text(
              label(gesture),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 380 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        return ListTile(
          dense: true,
          title: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    SizedBox(width: double.infinity, child: dropdown),
                  ],
                )
              : Text(title),
          trailing: stacked ? null : SizedBox(width: 180, child: dropdown),
        );
      },
    );
  }
}

class UndoSendSection extends StatelessWidget {
  const UndoSendSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l10nNow.undoSendPeriod,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        for (final delay in UndoSendDelay.values)
          ListTile(
            dense: true,
            title: Text(delay.label),
            trailing: delay == settings.undoSendDelay
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.undoSendDelay = delay,
          ),
      ],
    );
  }
}
