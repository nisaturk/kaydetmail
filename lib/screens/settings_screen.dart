import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_label.dart';
import '../models/mail_session.dart';
import '../services/api_health_service.dart';
import '../services/session_store.dart';
import '../state/app_settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/error_messages.dart';
import '../widgets/server_address_dialog.dart';
import 'accounts_screen.dart';
import 'rules_settings_screen.dart';
import 'signature_settings_screen.dart';

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

  /// Accessible names for [labelColors], same order — read by
  /// [_ColorPalette]'s swatch semantics so a screen reader announces which
  /// color is selected instead of just "button".
  static const List<String> labelColorNames = [
    'Mavi',
    'Mor',
    'Yeşil',
    'Turuncu',
    'Koyu kırmızı',
    'Kırmızı',
    'Turkuaz',
    'Menekşe',
    'Kırmızı-turuncu',
    'Koyu gri',
  ];

  @override
  Widget build(BuildContext context) {
    // Index of categories (Gmail/Thunderbird style); each opens its own page.
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        key: const Key('settings-list'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _CategoryTile(
            icon: LucideIcons.users,
            title: 'Hesaplar',
            subtitle: 'Bağlı posta hesapları',
            onTap: (ctx) => Navigator.of(
              ctx,
            ).push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
          ),
          _CategoryTile(
            icon: LucideIcons.palette,
            title: 'Görünüm',
            subtitle: 'Açık, koyu veya sistem teması',
            page: (_) => [_AppearanceSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.bell,
            title: 'Bildirimler',
            subtitle: 'Yeni e-posta bildirimleri',
            page: (_) => [_NotificationsSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.refreshCw,
            title: 'Senkronizasyon',
            subtitle: 'Posta kutusunu güncelleme sıklığı',
            page: (_) => [_SyncSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.tag,
            title: 'Etiketler',
            subtitle: 'Etiket oluştur, düzenle, sil',
            page: (_) => [_LabelsSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.filter,
            title: 'Kurallar',
            subtitle: 'Gelen postayı otomatik taşı/etiketle',
            onTap: (ctx) => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => const RulesSettingsScreen()),
            ),
          ),
          _CategoryTile(
            icon: LucideIcons.slidersHorizontal,
            title: 'Genel',
            subtitle: 'Kaydırma hareketleri',
            page: (_) => [_SwipeSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.penLine,
            title: 'İmza',
            subtitle: 'Gönderdiğiniz e-postalara eklenir',
            onTap: (ctx) => Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => const SignatureSettingsScreen(),
              ),
            ),
          ),
          _CategoryTile(
            icon: LucideIcons.shieldCheck,
            title: 'Güvenlik',
            subtitle: 'Uygulama kilidi, bağlı cihazlar ve oturumlar',
            page: (_) => [_BiometricLockSection(), _SessionsSection()],
          ),
          _CategoryTile(
            icon: LucideIcons.server,
            title: 'Sunucu',
            subtitle: 'API sunucu adresi',
            page: (_) => [_ServerSection()],
          ),
        ],
      ),
    );
  }
}

/// One row of the settings index. Either pushes [page] (section widgets shown
/// on a titled sub-page) or runs a custom [onTap].
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.page,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> Function(BuildContext)? page;
  final void Function(BuildContext)? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 22, color: AppTheme.colors(context).secondaryText),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(LucideIcons.chevronRight, size: 18),
      onTap: () {
        if (onTap != null) return onTap!(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _SettingsPage(title: title, sections: page!),
          ),
        );
      },
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.title, required this.sections});

  final String title;
  final List<Widget> Function(BuildContext) sections;

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
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: sections(context),
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
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (i, c) in SettingsScreen.labelColors.indexed)
          Semantics(
            button: true,
            label: SettingsScreen.labelColorNames[i],
            selected: c == selected,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () => onSelected(c),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: AppTheme.minTouchTarget,
                  height: AppTheme.minTouchTarget,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == selected ? onSurface : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: c == selected
                          ? const Icon(
                              LucideIcons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
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
              foregroundColor: AppTheme.colors(context).destructive,
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

enum _ApiHealthStatus { checking, healthy, unhealthy }

class _ServerSection extends StatefulWidget {
  const _ServerSection();

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  final ApiHealthService _healthService = ApiHealthService();
  _ApiHealthStatus _status = _ApiHealthStatus.checking;
  var _checkGeneration = 0;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  @override
  void dispose() {
    _healthService.close();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    final generation = ++_checkGeneration;
    if (_status != _ApiHealthStatus.checking) {
      setState(() => _status = _ApiHealthStatus.checking);
    }

    var isHealthy = false;
    try {
      isHealthy = await _healthService.isReady(
        AppSettingsController.instance.serverBaseUrl,
      );
    } catch (_) {
      // Network, timeout and malformed-address failures share one UI state.
    }
    if (!mounted || generation != _checkGeneration) return;
    setState(
      () => _status = isHealthy
          ? _ApiHealthStatus.healthy
          : _ApiHealthStatus.unhealthy,
    );
  }

  Future<void> _editServerAddress() async {
    await ServerAddressDialog.show(context);
    if (mounted) await _checkHealth();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    final checking = _status == _ApiHealthStatus.checking;
    final healthy = _status == _ApiHealthStatus.healthy;

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            LucideIcons.server,
            size: 20,
            color: AppTheme.colors(context).secondaryText,
          ),
          title: const Text('Sunucu adresi'),
          subtitle: Text(
            settings.serverBaseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: _editServerAddress,
        ),
        const Divider(indent: 56),
        ListTile(
          key: const Key('api-health-row'),
          dense: true,
          leading: checking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  healthy ? LucideIcons.circleCheckBig : LucideIcons.circleX,
                  size: 20,
                  color: healthy
                      ? AppTheme.colors(context).success
                      : Theme.of(context).colorScheme.error,
                ),
          title: const Text('API bağlantısı'),
          subtitle: Text(
            checking
                ? 'Bağlantı kontrol ediliyor…'
                : healthy
                ? 'Sunucu ve servisler hazır'
                : 'Bağlantı kurulamadı',
          ),
          trailing: checking
              ? null
              : IconButton(
                  tooltip: 'Bağlantıyı yeniden kontrol et',
                  onPressed: _checkHealth,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                ),
          onTap: checking ? null : _checkHealth,
        ),
      ],
    );
  }
}

/// Local biometric/device-credential app lock toggle — see
/// `BiometricLockGate` for the actual enforcement.
class _BiometricLockSection extends StatelessWidget {
  const _BiometricLockSection();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return SwitchListTile(
      dense: true,
      title: const Text('Uygulama Kilidi'),
      subtitle: const Text(
        'Uygulamayı her açtığınızda ya da arka plandan döndüğünde parmak '
        'izi/Face ID veya cihaz şifresi ister.',
      ),
      value: settings.biometricLockEnabled,
      onChanged: (v) => settings.biometricLockEnabled = v,
    );
  }
}

/// Lists every device signed into the account and lets the user close any
/// of them remotely. Fetched on demand (not part of the repository's
/// change-notifier state), so it keeps its own loading/error state.
class _SessionsSection extends StatefulWidget {
  const _SessionsSection();

  @override
  State<_SessionsSection> createState() => _SessionsSectionState();
}

class _SessionsSectionState extends State<_SessionsSection> {
  List<MailSession>? _sessions;
  String? _error;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final sessions = await AppConfig.mailRepository.getSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = 'Cihazlar yüklenemedi: ${friendlyErrorMessage(e)}',
      );
    }
  }

  Future<void> _revoke(MailSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oturumu kapat?'),
        content: Text(
          session.isCurrentDevice
              ? 'Bu cihazdaki oturum kapatılacak ve çıkış yapılacak.'
              : 'Bu cihaz artık bu hesaba erişemeyecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revokingId = session.id);
    try {
      await AppConfig.mailRepository.revokeSession(session.id);
      if (session.isCurrentDevice) {
        if (!mounted) return;
        await _signOutAfterRevoke();
        return;
      }
      if (!mounted) return;
      setState(() {
        _sessions = _sessions?.where((s) => s.id != session.id).toList();
        _revokingId = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _revokingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum kapatılamadı. Tekrar deneyin.')),
      );
    }
  }

  Future<void> _signOutAfterRevoke() async {
    await AppConfig.mailRepository.logout();
    await SessionStore.clear();
    // The root auth coordinator observes the repository logout and clears
    // every authenticated route before showing Login.
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    if (_error != null) {
      return ListTile(
        dense: true,
        leading: Icon(
          LucideIcons.triangleAlert,
          size: 20,
          color: AppTheme.colors(context).secondaryText,
        ),
        title: Text(_error!),
        trailing: TextButton(
          onPressed: _load,
          child: const Text('Tekrar dene'),
        ),
      );
    }
    if (sessions == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Bağlı cihaz yok.',
          style: TextStyle(fontSize: 14, color: AppTheme.colors(context).secondaryText),
        ),
      );
    }
    return Column(
      children: [
        for (final session in sessions)
          ListTile(
            dense: true,
            leading: Icon(
              LucideIcons.smartphone,
              size: 20,
              color: AppTheme.colors(context).secondaryText,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    session.deviceIdentifier,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session.isCurrentDevice) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.colors(context).unreadBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.colors(context).border),
                    ),
                    child: Text(
                      'Bu cihaz',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.colors(context).secondaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              'Son kullanım: ${formatMailTime(session.lastUsedAt)}',
            ),
            trailing: _revokingId == session.id
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: () => _revoke(session),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.colors(context).destructive,
                    ),
                    child: const Text('Kapat'),
                  ),
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
      subtitle: const Text('Bu cihazda yeni e-posta bildirimlerini göster.'),
      value: settings.notificationsEnabled,
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

/// System/light/dark theme picker. The palette itself never changes
/// (grayscale by design per the client's brand guidelines) — only which end
/// of it is the background.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

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
      onChanged: (v) => settings.swipeDeleteEnabled = v,
    );
  }
}
