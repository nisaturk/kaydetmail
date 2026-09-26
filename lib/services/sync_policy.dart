import 'package:battery_plus/battery_plus.dart';

import '../state/app_settings_controller.dart';
import 'attachment_auto_download_policy.dart';

bool shouldRunPeriodicSync({
  required SyncNetworkPolicy policy,
  required AttachmentConnection connection,
  required bool batterySaverOn,
  required bool pauseOnBatterySaver,
}) {
  if (pauseOnBatterySaver && batterySaverOn) return false;
  return switch (connection) {
    AttachmentConnection.none => false,
    AttachmentConnection.mobile => policy == SyncNetworkPolicy.wifiAndMobile,
    AttachmentConnection.wifi || AttachmentConnection.other => true,
  };
}

abstract interface class DeviceSyncConditions {
  Future<AttachmentConnection> connection();
  Future<bool> batterySaverOn();
}

class PlatformDeviceSyncConditions implements DeviceSyncConditions {
  PlatformDeviceSyncConditions({
    AttachmentConnectivity? connectivity,
    Battery? battery,
  }) : _connectivity = connectivity ?? PlatformAttachmentConnectivity(),
       _battery = battery ?? Battery();

  final AttachmentConnectivity _connectivity;
  final Battery _battery;

  @override
  Future<AttachmentConnection> connection() async {
    try {
      return classifyAttachmentConnection(await _connectivity.current());
    } catch (_) {
      return AttachmentConnection.other;
    }
  }

  @override
  Future<bool> batterySaverOn() async {
    try {
      return await _battery.isInBatterySaveMode;
    } catch (_) {
      return false;
    }
  }
}
