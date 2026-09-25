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
