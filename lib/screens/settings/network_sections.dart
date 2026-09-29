import 'dart:async';

import 'settings_widgets.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/app_config.dart';
import '../../services/api_health_service.dart';
import '../../state/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_messages.dart';
import '../../widgets/server_address_dialog.dart';
import '../../l10n/l10n.dart';

enum _ApiHealthStatus { checking, healthy, unhealthy }

class ServerSection extends StatefulWidget {
  const ServerSection({super.key});

  @override
  State<ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<ServerSection> {
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
          title: Text(l10nNow.serverAddress),
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
          title: Text(l10nNow.apiConnection),
          subtitle: Text(
            checking
                ? l10nNow.checkingConnection
                : healthy
                ? l10nNow.serverAndServicesAreReady
                : l10nNow.couldntConnect,
          ),
          trailing: checking
              ? null
              : IconButton(
                  tooltip: l10nNow.checkConnectionAgain,
                  onPressed: _checkHealth,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                ),
          onTap: checking ? null : _checkHealth,
        ),
      ],
    );
  }
}

class NetworkSection extends StatelessWidget {
  const NetworkSection({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SettingsGroup(
        title: l10nNow.sync,
        icon: LucideIcons.refreshCw,
        child: SyncSection(),
      ),
      SettingsGroup(
        title: l10nNow.attachments,
        icon: LucideIcons.paperclip,
        child: const AttachmentSettingsSection(),
      ),
      SettingsGroup(
        title: l10nNow.serverConnection,
        icon: LucideIcons.server,
        child: ServerSection(),
      ),
    ],
  );
}

class SyncSection extends StatelessWidget {
  const SyncSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    final secondaryText = AppTheme.colors(context).secondaryText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10nNow.thisSettingOnlyControlsHow,
            style: TextStyle(fontSize: 12.5, color: secondaryText),
          ),
        ),
        for (final interval in SyncInterval.values)
          ListTile(
            dense: true,
            title: Text(interval.label),
            trailing: interval == settings.syncInterval
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.syncInterval = interval,
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l10nNow.autoRefreshNetwork,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondaryText,
            ),
          ),
        ),
        for (final policy in SyncNetworkPolicy.values)
          ListTile(
            dense: true,
            key: ValueKey('sync-network-${policy.name}'),
            title: Text(policy.label),
            trailing: policy == settings.syncNetworkPolicy
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.syncNetworkPolicy = policy,
          ),
        SwitchListTile(
          dense: true,
          title: Text(l10nNow.pauseOnBatterySaver),
          subtitle: Text(l10nNow.whenBatterySaverIsOn),
          value: settings.pauseSyncOnBatterySaver,
          onChanged: (v) => settings.pauseSyncOnBatterySaver = v,
        ),
      ],
    );
  }
}

class AttachmentSettingsSection extends StatefulWidget {
  const AttachmentSettingsSection({super.key});

  @override
  State<AttachmentSettingsSection> createState() =>
      _AttachmentSettingsSectionState();
}

class _AttachmentSettingsSectionState extends State<AttachmentSettingsSection> {
  int? _cacheBytes;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    try {
      final size = await AppConfig.mailRepository.attachmentCacheSize();
      if (mounted) {
        setState(() {
          _cacheBytes = size;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10nNow.clearAttachmentCache),
        content: Text(l10nNow.downloadedAttachmentsTakingUpWill(_sizeLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10nNow.cancel2),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10nNow.clear),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await AppConfig.mailRepository.clearAttachmentCache();
      await _loadSize();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10nNow.attachmentCacheCleared)));
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _sizeLabel {
    final bytes = _cacheBytes ?? 0;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    final secondary = AppTheme.colors(context).secondaryText;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10nNow.attachmentsAreDownloadedAutomaticallyOnly,
            style: TextStyle(fontSize: 12.5, color: secondary),
          ),
        ),
        for (final mode in AttachmentAutoDownloadMode.values)
          ListTile(
            dense: true,
            title: Text(mode.label),
            trailing: mode == settings.attachmentAutoDownloadMode
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.attachmentAutoDownloadMode = mode,
          ),
        const Divider(height: 1),
        for (final limit in AttachmentAutoDownloadLimit.values)
          ListTile(
            dense: true,
            title: Text(l10nNow.autoDownloadLimit(limit.label)),
            trailing: limit == settings.attachmentAutoDownloadLimit
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () => settings.attachmentAutoDownloadLimit = limit,
          ),
        const Divider(height: 1),
        ListTile(
          key: const Key('clear-attachment-cache'),
          leading: Icon(LucideIcons.trash2, size: 20, color: secondary),
          title: Text(l10nNow.clearAttachmentCache2),
          subtitle: _error != null
              ? Row(
                  children: [
                    Expanded(child: Text(_error!)),
                    TextButton(
                      onPressed: _loadSize,
                      child: Text(l10nNow.tryAgain),
                    ),
                  ],
                )
              : Text(
                  _cacheBytes == null ? l10nNow.calculatingSize : _sizeLabel,
                ),
          trailing: _busy || _cacheBytes == null
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _busy || _cacheBytes == null ? null : _clear,
        ),
      ],
    );
  }
}
