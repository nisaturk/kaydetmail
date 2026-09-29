import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/device_contacts.dart';
import '../../state/app_settings_controller.dart';

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
        const SnackBar(
          content: Text(
            'Kişilere erişim izni verilmedi. Öneriler mail geçmişinden '
            've eklediğiniz kişilerden gelmeye devam eder.',
          ),
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
    title: const Text('Cihaz kişilerini öner'),
    subtitle: const Text(
      'Alıcı yazarken telefon rehberindeki e-posta adreslerini de önerir. '
      'Rehber yalnızca bu cihazda okunur, sunucuya gönderilmez.',
    ),
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
          title: const Text('Bildirimler'),
          subtitle: const Text(
            'Bu cihazda yeni e-posta bildirimlerini göster. Klasör kapsamı ve kilit '
            'ekranı gizliliği her hesabın kendi ayarlarındadır.',
          ),
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

  static const _options = [
    (ThemeMode.system, 'Sistem', 'Cihazın temasını izler'),
    (ThemeMode.light, 'Açık', null),
    (ThemeMode.dark, 'Koyu', null),
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
          title: const Text('Kaydırma hareketleri'),
          subtitle: const Text(
            'Listede e-postayı sağa veya sola kaydırarak aşağıdaki '
            'işlemleri yapın. Çöp, Spam ve Arşiv klasörleri kendi '
            'işlemlerini kullanır.',
          ),
          value: settings.swipeDeleteEnabled,
          onChanged: (v) => settings.swipeDeleteEnabled = v,
        ),
        if (settings.swipeDeleteEnabled) ...[
          _SwipeGestureTile(
            key: const Key('swipe-right-setting'),
            title: 'Sağa kaydırınca',
            value: settings.swipeRight,
            onChanged: (v) => settings.swipeRight = v,
          ),
          _SwipeGestureTile(
            key: const Key('swipe-left-setting'),
            title: 'Sola kaydırınca',
            value: settings.swipeLeft,
            onChanged: (v) => settings.swipeLeft = v,
          ),
        ],
      ],
    );
  }
}

class _SwipeGestureTile extends StatelessWidget {
  const _SwipeGestureTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final SwipeGesture value;
  final ValueChanged<SwipeGesture> onChanged;

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButton<SwipeGesture>(
      value: value,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      items: [
        for (final gesture in SwipeGesture.values)
          DropdownMenuItem(
            value: gesture,
            child: Text(
              gesture.label,
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Göndermeyi geri alma süresi',
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
