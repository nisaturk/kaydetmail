import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/email.dart';
import '../repositories/mail_repository.dart';
import '../state/app_settings_controller.dart';

enum AttachmentConnection { wifi, mobile, other, none }

abstract interface class AttachmentConnectivity {
  Future<List<ConnectivityResult>> current();
}

class PlatformAttachmentConnectivity implements AttachmentConnectivity {
  PlatformAttachmentConnectivity([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> current() =>
      _connectivity.checkConnectivity();
}

AttachmentConnection classifyAttachmentConnection(
  List<ConnectivityResult> results,
) {
  if (results.contains(ConnectivityResult.mobile) ||
      results.contains(ConnectivityResult.satellite)) {
    return AttachmentConnection.mobile;
  }
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return AttachmentConnection.wifi;
  }
  if (results.contains(ConnectivityResult.none) || results.isEmpty) {
    return AttachmentConnection.none;
  }
  return AttachmentConnection.other;
}

bool shouldAutoDownloadAttachment({
  required AttachmentAutoDownloadMode mode,
  required AttachmentConnection connection,
  required int sizeBytes,
  required AttachmentAutoDownloadLimit limit,
}) {
  if (mode == AttachmentAutoDownloadMode.off ||
      sizeBytes <= 0 ||
      sizeBytes > limit.bytes) {
    return false;
  }
  return switch (mode) {
    AttachmentAutoDownloadMode.off => false,
    AttachmentAutoDownloadMode.wifiOnly =>
      connection == AttachmentConnection.wifi,
    AttachmentAutoDownloadMode.wifiAndMobile =>
      connection == AttachmentConnection.wifi ||
          connection == AttachmentConnection.mobile,
  };
}

class AttachmentAutoDownloader {
  AttachmentAutoDownloader({
    AttachmentConnectivity? connectivity,
    AppSettingsController? settings,
  }) : _connectivity = connectivity ?? PlatformAttachmentConnectivity(),
       _settings = settings ?? AppSettingsController.instance;

  final AttachmentConnectivity _connectivity;
  final AppSettingsController _settings;

  final Set<String> _preloading = {};

  /// Best-effort list/cache hydration preload. Detail navigation is not
  /// required; work stays bounded so opening a large mailbox cannot enqueue
  /// every attachment at once.
  Future<void> preloadListed(
    MailRepository repository,
    Iterable<Email> emails, {
    int maxAttachments = 12,
  }) async {
    final mode = _settings.attachmentAutoDownloadMode;
    if (mode == AttachmentAutoDownloadMode.off || maxAttachments <= 0) return;
    late AttachmentConnection network;
    try {
      network = classifyAttachmentConnection(await _connectivity.current());
    } catch (_) {
      return;
    }
    // Background preload is intentionally Wi-Fi-only. Explicit detail-open
    // auto-download below may also honor the user's mobile-enabled mode.
    if (network != AttachmentConnection.wifi) return;

    final pending = <({Email email, Attachment attachment, String key})>[];
    for (final email in emails) {
      for (final attachment in email.attachments) {
        final id = attachment.id;
        final key = '${email.accountId}\u0000${email.id}\u0000$id';
        if (id == null ||
            _preloading.contains(key) ||
            !shouldAutoDownloadAttachment(
              mode: mode,
              connection: network,
              sizeBytes: attachment.sizeBytes,
              limit: _settings.attachmentAutoDownloadLimit,
            )) {
          continue;
        }
        _preloading.add(key);
        pending.add((email: email, attachment: attachment, key: key));
        if (pending.length == maxAttachments) break;
      }
      if (pending.length == maxAttachments) break;
    }

    // Two workers cap simultaneous network/file pressure while still letting
    // one slow attachment make progress beside another.
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final item = pending[next++];
        try {
          await repository.ensureAttachmentFile(item.email.id, item.attachment);
        } catch (_) {
          _preloading.remove(item.key);
        }
      }
    }

    await Future.wait([worker(), worker()]);
  }

  Future<void> onMailOpened(MailRepository repository, Email email) async {
    if (_settings.attachmentAutoDownloadMode ==
            AttachmentAutoDownloadMode.off ||
        email.attachments.isEmpty) {
      return;
    }
    late AttachmentConnection network;
    try {
      network = classifyAttachmentConnection(await _connectivity.current());
    } catch (_) {
      return;
    }
    for (final attachment in email.attachments) {
      if (_settings.attachmentAutoDownloadMode ==
              AttachmentAutoDownloadMode.off ||
          attachment.id == null ||
          !shouldAutoDownloadAttachment(
            mode: _settings.attachmentAutoDownloadMode,
            connection: network,
            sizeBytes: attachment.sizeBytes,
            limit: _settings.attachmentAutoDownloadLimit,
          )) {
        continue;
      }
      try {
        await repository.ensureAttachmentFile(email.id, attachment);
      } catch (_) {
        continue;
      }
    }
  }
}
